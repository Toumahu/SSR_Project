// 深度からワールド座標への変換を行うシェーダー
// フレームバッファフェッチ: https://docs.unity3d.com/ja/6000.0/Manual/urp/render-graph-framebuffer-fetch.html
// GPU のオンチップメモリからフレームバッファにアクセスできます

Shader "Custom/ScreenSpaceReflection5"
{
    Properties
    {
        _MaxRayDistance("Max Ray Distance", Range(1, 10)) = 5.0 // レイの最大距離
        _StepCount("Step Count", Range(1, 100)) = 10 // step数が多いと読み込みが長く重くなりやすい感じ
        _Thickness("Thickness", Range(0.0, 1.0)) = 0.0 // 厚み
        _FadeDistance("Fade Distance", Range(1.0, 100.0)) = 5.0 // フェイド距離
        _FadeDistanceExponent("Fade Distance Exponent", Range(1.0, 10.0)) = 2.0 // フェイド距離の指数
        _EdgeDistance("Edge Distance", Range(0.0, 100.0)) = 1.0 // 周辺フェイドの距離
        _EdgeExponent("Edge Exponent", Range(1.0, 10.0)) = 3.0 // 周辺フェイドの指数
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" }

        Pass
        {
            Name "ScreenSpaceReflection"

            HLSLPROGRAM

            #pragma vertex Vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Color.hlsl"

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

            // gBuffer
            // https://docs.unity3d.com/jp/current/Manual/urp/rendering/g-buffer-layout.html
            #define GBUFFER0 0 // albedo
            #define GBUFFER1 1 // specular
            #define GBUFFER2 2 // normal
            #define GBUFFER3 3 // depth

            FRAMEBUFFER_INPUT_X_HALF(GBUFFER2);

            CBUFFER_START(UnityPerMaterial)
            int _MaxRayDistance; // レイの最大距離
            int _StepCount; // レイマーチングのステップ数
            float _Thickness; // 厚み
            // int _BinarySearchIterations; // 二分探索の反復回数

            // 距離フェイド ---------------------------------------
            float _FadeDistance; // フェイド距離
            float _FadeDistanceExponent; // フェイド距離の指数

            // 周辺フェイド ---------------------------------------
            float _EdgeDistance; // 周辺フェイドの距離
            float _EdgeExponent; // 周辺フェイドの指数
            CBUFFER_END

            // ノイズにパターンがある
            float noise(float2 uv)
            {
                return frac(sin(dot(uv, float2(12.9898, 78.233))) * 43758.5453);
            }

            half4 frag(Varyings IN) : SV_Target
            {
                // 深度からワールド座標への変換
                // https://docs.unity3d.com/ja/Packages/com.unity.render-pipelines.universal@14.0/manual/writing-shaders-urp-reconstruct-world-position.html
                half depth = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, sampler_PointClamp, IN.texcoord).r; //LOAD_FRAMEBUFFER_X_INPUT(GBUFFER3, IN.positionCS).r;
                float3 worldPos = ComputeWorldSpacePosition(IN.texcoord, depth, UNITY_MATRIX_I_VP);

                // 反射ベクトルを計算
                float3 viewDir = normalize(worldPos - _WorldSpaceCameraPos);
                float3 normal = LOAD_FRAMEBUFFER_X_INPUT(GBUFFER2, IN.positionCS); // GBuffer Normal[-1~1]
                float3 reflectDir = reflect(viewDir, normal);

                // カラー
                half4 color = 0;

                // レイマーチング
                float dotNV = dot(normal, viewDir);
                float rayDistance = _MaxRayDistance * (1.0 - saturate(dotNV) * step(0.6, dotNV));
                float3 startWS = worldPos;
                float3 endWS = worldPos + reflectDir * rayDistance; // 適当な距離
                float3 deltaStep = (endWS - startWS) / _StepCount; // 1stepあたりの移動量

                float3 startRayWS = startWS; // レイ開始位置
                float2 rayUV; // レイのUV座標
                float hitMask = 0;

                // レイマーチング
                [loop]
                for (int n = 1; n <= _StepCount; n++)
                {
                    startRayWS = startWS + deltaStep * (n + noise(IN.texcoord));
                    float4 rayHCS = TransformWorldToHClip(startRayWS);

                    rayUV = rayHCS.xy / rayHCS.w * 0.5 + 0.5;
                    #if UNITY_UV_STARTS_AT_TOP // 上下逆問題を修正
                    rayUV.y = 1 - rayUV.y;
                    #endif

                    // 画面外チェック
                    // 壁反射に変な色が混じるのを防ぐ（レイが長いときに発生する）
                    if (rayUV.x < 0 || rayUV.x > 1 || rayUV.y < 0 || rayUV.y > 1)
                    {
                        hitMask = 0.0;
                        break;
                    }

                    // レイ空間の仮想深度
                    float deviceDepth = rayHCS.z / rayHCS.w;
                    float rayDepth = Linear01Depth(deviceDepth, _ZBufferParams); // 手前0,奥1

                    // 実際に表示されている画面からレイの深度を取得
                    float rawDepth = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, sampler_PointClamp, rayUV);
                    float depth = Linear01Depth(rawDepth, _ZBufferParams); // 手前0,奥1

                    // 画面上のどこにもオブジェクトがない場合はヒットしない
                    // 背景などに白い粒子が見えるのを防ぐ
                    if (depth >= 1.0)
                    {
                        hitMask = 0;
                        break;
                    }

                    // ---------------------------------------------------
                    // めり込み判定・厚み付き 
                    // ---------------------------------------------------
                    // rayDepth,depth: 0(手前) ~ 1(奥)
                    float depthDiff = rayDepth - depth;

                    // 厚みが大きい場合はリターン
                    // 400は手動で調整した値, _Thicknessは0~1の範囲にしたかった
                    if (depthDiff < 0)
                    {
                        hitMask = 0.05;
                        continue;
                    }

                    if (depthDiff * 400 > _Thickness)
                    {
                        hitMask = 0.05;
                        continue;
                    }

                    hitMask = 0.1;
                    break;
                }

                // ---------------------------------------------------
                // フェイド
                // ---------------------------------------------------

                // 距離フェイド
                float distanceFade = length(startRayWS - worldPos);
                distanceFade = saturate(1 - pow(distanceFade / _FadeDistance, _FadeDistanceExponent));

                // 周辺フェイド
                // u(1 - u) * v(1 - v)の形で、中心が0.25、端が0になるような値を作る
                half2 edgeUV = IN.texcoord * (1 - IN.texcoord);
                // uかvのどちらかが0なら0（端は黒）、両方に値があるほど緩やかに明るくなる
                // 係数で明るさ調整
                float edge = edgeUV.x * edgeUV.y * _EdgeDistance;
                // フェイドの鋭さ
                edge = saturate(pow(abs(edge), _EdgeExponent));

                IN.texcoord = rayUV;
                return FragNearest(IN) * hitMask * distanceFade * edge;
            }
            ENDHLSL
        }        
        
        Pass
        {
            Name "Composite"

            HLSLPROGRAM

            #pragma vertex Vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Color.hlsl"

            TEXTURE2D_X(_GaussTexture);
            //TEXTURE2D_X(_SSRTexture);

            half4 frag(Varyings IN) : SV_Target
            {
                float4 gauss = SAMPLE_TEXTURE2D(_GaussTexture, sampler_LinearClamp, IN.texcoord);
                return FragNearest(IN) + gauss;
                // return ssr;
            }
            ENDHLSL
        }
    }
}

// フェードであった方がよいもの
// 距離、端