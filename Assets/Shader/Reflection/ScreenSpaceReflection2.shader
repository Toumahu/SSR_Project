// 深度からワールド座標への変換を行うシェーダー
// フレームバッファフェッチ: https://docs.unity3d.com/ja/6000.0/Manual/urp/render-graph-framebuffer-fetch.html
// GPU のオンチップメモリからフレームバッファにアクセスできます

Shader "Custom/ScreenSpaceReflection2"
{
    Properties
    {
        _MaxRayDistance("Max Ray Distance", Range(1, 100)) = 10.0 // レイの最大距離
        _StepCount("Step Count", Range(1, 100)) = 10 // step数が多いと読み込みが長く重くなりやすい感じ
        _Thickness("Thickness", Range(0.0, 0.1)) = 0.0 // 厚み
        _BinarySearchIterations("Binary Search Iterations", Range(0, 32)) = 5 // 二分探索の反復回数
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" }

        Pass
        {
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
            int _BinarySearchIterations; // 二分探索の反復回数
            CBUFFER_END

            /// <summary>
            /// Screen Space Reflectionのレイマーチング処理
            /// </summary>
            bool isSsrRayTrace(
                float3 worldPos, 
                float3 reflectDir,
                float dotNV, // 法線と視線の内積
                out float2 hitUV)
            {
                float3 startWS = worldPos;
                float3 endWS = worldPos + reflectDir * _StepCount; // 適当な距離
                float3 deltaStep = (endWS - startWS) / _StepCount; // 1stepあたりの移動量
                bool isHit = false;

                float3 startRayWS; // レイ開始位置

                // レイマーチング
                [loop]
                for (int n = 1; n <= _StepCount; n++)
                {
                    startRayWS = startWS + deltaStep * n;
                    float4 rayHCS = TransformWorldToHClip(startRayWS);

                    float2 rayUV = rayHCS.xy / rayHCS.w * 0.5 + 0.5;
                    #if UNITY_UV_STARTS_AT_TOP // 上下逆問題を修正
                    rayUV.y = 1 - rayUV.y;
                    #endif

                    // 画面外チェック
                    if (rayUV.x < 0 || rayUV.x > 1 ||
                        rayUV.y < 0 || rayUV.y > 1)
                        break;

                    // レイ空間の仮想深度
                    float deviceDepth = rayHCS.z / rayHCS.w;
                    float rayDepth = Linear01Depth(deviceDepth, _ZBufferParams); // 手前0,奥1

                    // 実際に表示されている画面からレイの深度を取得
                    float rawDepth = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, sampler_PointClamp, rayUV);
                    float depth = Linear01Depth(rawDepth, _ZBufferParams); // 手前0,奥1

                    // めり込み判定・厚み付き 
                    // rayDepthの方が手前ならめり込んでいる
                    // rayDepth,depth: 0 ~ 1
                    isHit = rayDepth > depth && rayDepth - depth < _Thickness;
                    if (isHit)
                    {
                        hitUV = rayUV;
                        break;
                    }
                }

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
                half4 color = FragNearest(IN);

                // レイマーチング
                float dotNV = dot(normal, viewDir);
                float2 hitUV;
                bool isHit = isSsrRayTrace(worldPos, reflectDir, dotNV, hitUV);
                if (isHit)
                {
                    IN.texcoord = hitUV;
                    color += FragNearest(IN) * 0.2;
                }

                return color;
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