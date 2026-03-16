// 深度からワールド座標への変換を行うシェーダー
// フレームバッファフェッチ: https://docs.unity3d.com/ja/6000.0/Manual/urp/render-graph-framebuffer-fetch.html
// GPU のオンチップメモリからフレームバッファにアクセスできます

Shader "Custom/ScreenSpaceReflection4"
{
    Properties
    {
        _MaxRayDistance("Max Ray Distance", Range(1, 10)) = 5.0 // レイの最大距離
        _StepCount("Step Count", Range(1, 100)) = 10 // step数が多いと読み込みが長く重くなりやすい感じ
        _Thickness("Thickness", Range(0.0, 1.0)) = 0.0 // 厚み
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
            CBUFFER_END

            // ノイズにパターンがある
            float noise(float2 uv)
            {
                return frac(sin(dot(uv, float2(12.9898, 78.233))) * 43758.5453);
            }

            /// <summary>
            /// 入力したワールド座標が深度バッファにヒットしているか
            /// </summary>
            int isRayHit(float3 startRayWS, out float2 rayUV)
            {
                float4 rayHCS = TransformWorldToHClip(startRayWS);

                rayUV = rayHCS.xy / rayHCS.w * 0.5 + 0.5;
                #if UNITY_UV_STARTS_AT_TOP // 上下逆問題を修正
                rayUV.y = 1 - rayUV.y;
                #endif

                // 画面外チェック
                if (rayUV.x < 0 || rayUV.x > 1 || rayUV.y < 0 || rayUV.y > 1)
                {
                    return 0;
                }

                // レイ空間の仮想深度
                float deviceDepth = rayHCS.z / rayHCS.w;
                float rayDepth = Linear01Depth(deviceDepth, _ZBufferParams); // 手前0,奥1

                // 実際に表示されている画面からレイの深度を取得
                float rawDepth = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, sampler_PointClamp, rayUV);
                float depth = Linear01Depth(rawDepth, _ZBufferParams); // 手前0,奥1

                if (depth >= 1.0) // 画面上のどこにもオブジェクトがない場合はヒットしない
                {
                    return 0;
                }

                // めり込み判定・厚み付き 
                // rayDepthの方が手前ならめり込んでいる
                // rayDepth,depth: 0(手前) ~ 1(奥)
                float depthDiff = rayDepth - depth;
                if (depthDiff < 0) // 手前ならめり込んでいない
                {
                    return 0;
                }

                if (depthDiff * 400 > _Thickness) // 400は手動で調整した値, _Thicknessは0~1の範囲にしたかった
                {
                    return 1;
                }

                return 2;
            }

            /// <summary>
            /// Screen Space Reflectionのレイマーチング処理
            /// </summary>
            int isSsrRayTrace(
                float3 worldPos, 
                float3 reflectDir,
                float dotNV, // 法線と視線の内積
                out float2 hitUV,
                float2 uv)
            {
                // 正面に近いほど反射の影響を受けにくくする (SSRの都合上、カメラにオブジェクトが近いと大きく映る現象の回避)
                // 0.6未満は減衰無し
                float rayDistance = _MaxRayDistance * (1.0 - saturate(dotNV) * step(0.6, dotNV));
                float3 startWS = worldPos;
                float3 endWS = worldPos + reflectDir * rayDistance; // 適当な距離
                float3 deltaStep = (endWS - startWS) / _StepCount; // 1stepあたりの移動量
                bool isHit = false;

                float3 startRayWS = startWS; // レイ開始位置
                float2 rayUV; // レイのUV座標
                int hitFlag = 0;

                // レイマーチング
                [loop]
                for (int n = 1; n <= _StepCount; n++)
                {
                    startRayWS = startWS + deltaStep * (n + noise(uv/*+ _Time.x*/));
                    int flag = isRayHit(startRayWS, rayUV);
                    hitUV = rayUV;

                    if (flag > 0)
                    {
                        hitFlag = flag;
                    }

                    if (flag == 2) // 厚みの範囲内でヒットしたら終了
                    {
                        break;
                    }
                }

                return hitFlag;
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
                float2 hitUV;
                int hitFlag = isSsrRayTrace(worldPos, reflectDir, dotNV, hitUV, IN.texcoord);
                if (hitFlag > 0)
                {
                    IN.texcoord = hitUV;
                    color = FragNearest(IN) * 0.2;
                }
                else if (hitFlag == 1)
                {
                    color = 1;
                }

                return color;
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

            // TEXTURE2D_X(_GaussTexture);
            TEXTURE2D_X(_SSRTexture);

            half4 frag(Varyings IN) : SV_Target
            {
                float4 ssr = SAMPLE_TEXTURE2D(_SSRTexture, sampler_LinearClamp, IN.texcoord);
                return FragNearest(IN) + ssr;
                // return ssr;
            }
            ENDHLSL
        }
    }
}