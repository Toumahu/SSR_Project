// 深度からワールド座標への変換を行うシェーダー
// フレームバッファフェッチ: https://docs.unity3d.com/ja/6000.0/Manual/urp/render-graph-framebuffer-fetch.html
// GPU のオンチップメモリからフレームバッファにアクセスできます

Shader "Custom/ScreenSpaceReflection"
{
    Properties
    {
        _MaxRayDistance("Max Ray Distance", Range(1, 100)) = 10.0 // レイの最大距離
        _StepCount("Step Count", Range(1, 100)) = 10 // step数が多いと読み込みが長く重くなりやすい感じ
        _Thickness("Thickness", Range(0.0, 64.0)) = 0.0 // 厚み
        // _BinarySearchIterations("Binary Search Iterations", Range(0, 32)) = 5 // 二分探索の反復回数
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

            // ノイズにパターンが無いため、途中で変な模様になる
            // float hash(float2 p)
            // {
            //     p = frac(p * 0.3183099 + 0.1);
            //     p *= 17.0;
            //     return frac(p.x * p.y * (p.x + p.y));
            // }

            /// <summary>
            /// 入力したワールド座標が深度バッファにヒットしているか
            /// </summary>
            bool isRayHit(float3 startRayWS, out float2 rayUV)
            {
                float4 rayHCS = TransformWorldToHClip(startRayWS);

                rayUV = rayHCS.xy / rayHCS.w * 0.5 + 0.5;
                #if UNITY_UV_STARTS_AT_TOP // 上下逆問題を修正
                rayUV.y = 1 - rayUV.y;
                #endif

                // 画面外チェック
                if (rayUV.x < 0 || rayUV.x > 1 ||
                    rayUV.y < 0 || rayUV.y > 1)
                    return false;

                // レイ空間の仮想深度
                float deviceDepth = rayHCS.z / rayHCS.w;
                float rayDepth = Linear01Depth(deviceDepth, _ZBufferParams); // 手前0,奥1

                // 実際に表示されている画面からレイの深度を取得
                float rawDepth = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, sampler_PointClamp, rayUV);
                float depth = Linear01Depth(rawDepth, _ZBufferParams); // 手前0,奥1

                if (depth >= 1.0)
                    return false; // 画面上のどこにもオブジェクトがない場合はヒットしない

                // めり込み判定・厚み付き 
                // rayDepthの方が手前ならめり込んでいる
                // rayDepth,depth: 0 ~ 1
                return rayDepth > depth && (rayDepth - depth)*10000 < _Thickness;
            }

            /// <summary>
            /// Screen Space Reflectionのレイマーチング処理
            /// </summary>
            bool isSsrRayTrace(
                float3 worldPos, 
                float3 reflectDir,
                float dotNV, // 法線と視線の内積
                out float2 hitUV,
                float2 uv)
            {
                // 正面に近いほど反射の影響を受けにくくする (SSRの都合上、カメラにオブジェクトが近いと大きく映る現象の回避)
                // 0.6未満は減衰無し
                float rayDistance = _MaxRayDistance * (1.0 - saturate(dotNV) * step(0.6, dotNV));
                // レイの最大長さ TODO: カメラ範囲内からレイがはみ出すのを防ぐ必要有
                // float rayLength = worldPos.z + reflectDir.z * rayDistance;

                float3 startWS = worldPos;
                float3 endWS = worldPos + reflectDir * rayDistance; // 適当な距離
                float3 deltaStep = (endWS - startWS) / _StepCount; // 1stepあたりの移動量
                bool isHit = false;

                float3 startRayWS = startWS; // レイ開始位置
                float2 rayUV; // レイのUV座標

                // レイマーチング
                [loop]
                for (int n = 1; n <= _StepCount; n++)
                {
                    startRayWS = startWS + deltaStep * (n + noise(uv/*+ _Time.x*/));
                    isHit = isRayHit(startRayWS, rayUV);
                    if (isHit)
                    {
                        hitUV = rayUV;
                        break;
                    }
                }

                // // 2分探索 TODO: あまり効果的ではなさそう
                // if (_BinarySearchIterations > 0 && isHit)
                // {
                //     startRayWS -= deltaStep; // 最後のステップでめり込んでいるので、1step分戻る
                //     deltaStep /= _BinarySearchIterations; // ステップ距離をさらに細かく

                //     // 二分探索 開始
                //     float mid = _BinarySearchIterations * 0.5; // 中心点から見ていく
                //     float nextDirection = mid; // 正なら奥、負なら手前 [ 未めり込み ] ---- 表面 ---- [ めり込み ]

                //     [loop]
                //     for (int n = 0; n < _BinarySearchIterations; n++)
                //     {
                //         startRayWS += deltaStep * nextDirection;
                //         mid *= 0.5; // さらに半分にして反射座標を絞る
                //         nextDirection = isRayHit(startRayWS, rayUV) ? -mid : mid;
                //         hitUV = rayUV;
                //     }
                // }

                return isHit;
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
                half4 color = 0;// = FragNearest(IN);

                // レイマーチング
                float dotNV = dot(normal, viewDir);
                float2 hitUV;
                bool isHit = isSsrRayTrace(worldPos, reflectDir, dotNV, hitUV, IN.texcoord);
                if (isHit)
                {
                    IN.texcoord = hitUV;
                    color = FragNearest(IN) * 0.2;
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
            }
            ENDHLSL
        }
    }


}

// // 検証用
// {
//     float4 cs = TransformWorldToHClip(worldPos);
//     float2 uv = cs.xy / cs.w * 0.5 + 0.5;
//     #if UNITY_UV_STARTS_AT_TOP // 上下逆問題を修正
//     uv.y = 1.0 - uv.y;
//     #endif
//     float rayDepth = cs.z / cs.w; // 深度値のそのままの絵(オブジェクト以外の空間の深度もある)
//     rayDepth = Linear01Depth(rayDepth, _ZBufferParams); // 手前0,奥1

//     float depth = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, sampler_PointClamp, uv);
//     depth = Linear01Depth(depth, _ZBufferParams); // 手前0,奥1

//     return half4(rayDepth,0,0,1);
// }