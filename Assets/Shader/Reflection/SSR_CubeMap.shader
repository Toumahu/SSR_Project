// 深度からワールド座標への変換を行うシェーダー
// フレームバッファフェッチ: https://docs.unity3d.com/ja/6000.0/Manual/urp/render-graph-framebuffer-fetch.html
// GPU のオンチップメモリからフレームバッファにアクセスできます

// cubeMapをc#側からAPIを通して作る

Shader "Custom/SSR_CubeMap"
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
        _SSRFade("SSR Fade", Range(0.0, 1.0)) = 1.0 // SSR全体のフェイド
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" }

        Pass
        {
            // ポストエフェクトへ
            Name "CubeMapReflection"
            
            HLSLPROGRAM
            
            #pragma vertex Vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/BRDF.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/GlobalIllumination.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Color.hlsl"

            // _CameraDepthTexture使えるように
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

            // gBuffer
            // https://docs.unity3d.com/jp/current/Manual/urp/rendering/g-buffer-layout.html
            #define GBUFFER0 0 // albedo
            #define GBUFFER1 1 // specular
            #define GBUFFER2 2 // normal
            #define GBUFFER3 3 // depth

            FRAMEBUFFER_INPUT_X_HALF(GBUFFER1);
            FRAMEBUFFER_INPUT_X_HALF(GBUFFER2);
            FRAMEBUFFER_INPUT_X_HALF(GBUFFER3);

            // cubemap
            TEXTURECUBE(_ReflectionProbe);
            SAMPLER(sampler_ReflectionProbe);

            float4 _CubeMapMax;    // w contains the blend distance
            float4 _CubeMapMin;    // w contains the importance
            float4 _ProbePosition; // w is positive for box projection, |w| is max mip level
            float4 _CubeMapHDR;

            /// <summary>
            /// 反射ベクトルがprobe中心からずれた場合に、中心からの反射ベクトル方向へ戻す処理
            /// </summary>
            float3 boxProjection(float3 reflDir, float3 worldPos)
            {
                // 移り込み補正のために反射ベクトルの長さの調整
                // それぞれの面との距離を求める
                float3 boxMin = (_CubeMapMin - worldPos) / reflDir;
                float3 boxMax = (_CubeMapMax - worldPos) / reflDir;
                // cubeMapのどこの壁に当たるかチェック
                // x = worldPos + reflDir * magnitude;
                // magnitude = (x - worldPos) / reflDir
                float magnitudeX = reflDir.x > 0 ? boxMax.x : boxMin.x;
                float magnitudeY = reflDir.y > 0 ? boxMax.y : boxMin.y;
                float magnitudeZ = reflDir.z > 0 ? boxMax.z : boxMin.z;

                float magnitude = min(min(magnitudeX, magnitudeY), magnitudeZ);

                // probe中心からの斜辺(ベクトル方向)を求める
                float3 a = worldPos - _ProbePosition;
                float3 c = reflDir * magnitude;
                float3 b = a + c;

                // probeの中心座標
                // 反射ベクトル
                return b;
            }

            half3 GlossyEnvironmentReflection2(half3 reflectVector, half perceptualRoughness, half occlusion)
            {
                half mip = PerceptualRoughnessToMipmapLevel(perceptualRoughness);
                half4 encodedIrradiance = half4(SAMPLE_TEXTURECUBE_LOD(_ReflectionProbe, sampler_ReflectionProbe, reflectVector, mip));
                half3 irradiance = DecodeHDREnvironment(encodedIrradiance, _CubeMapHDR);
                return irradiance * occlusion;
            }
            
            half4 frag (Varyings IN) : SV_Target
            {
                half depth = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, sampler_PointClamp, IN.texcoord).r; // Before Rendering Post Processing実行の際に取得される
                // float depth = SampleSceneDepth(IN.texcoord);
                // float depth = LOAD_FRAMEBUFFER_X_INPUT(GBUFFER3, IN.positionCS.xy).r;
                float3 positionWS = ComputeWorldSpacePosition(IN.texcoord, depth, UNITY_MATRIX_I_VP);
                half3 viewDir = normalize(_WorldSpaceCameraPos - positionWS); // obj -> camera

                float4 gbuffer2 = LOAD_FRAMEBUFFER_X_INPUT(GBUFFER2, IN.positionCS.xy); // GBuffer Normal[-1~1]/Smoothness
                float3 normalWS = normalize(gbuffer2.xyz);
                half3 reflDir = reflect(-viewDir, normalWS);
                reflDir = boxProjection(reflDir, positionWS);
            
                float occlusion = LOAD_FRAMEBUFFER_X_INPUT(GBUFFER1, IN.positionCS.xy).a; // GBuffer Occlusion
                float roughness = 1 - gbuffer2.a; // Smoothness -> Roughness
                
                // unity_SpecCube1はUnityで定義されているキューブマップ
                half3 reflectionColor = GlossyEnvironmentReflection2(reflDir, roughness, occlusion);
                return half4(reflectionColor, 1);
            }
            ENDHLSL
        }

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

            // SSR全体フェイド ------------------------------------
            float _SSRFade; // SSR全体フェイド 
            CBUFFER_END

            TEXTURE2D(_CubeMapTexture);

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

                // レイマーチング
                float dotNV = dot(normal, viewDir);
                float rayDistance = _MaxRayDistance * (1.0 - saturate(dotNV) * step(0.6, dotNV));
                float3 startWS = worldPos;
                float3 endWS = worldPos + reflectDir * rayDistance; // 適当な距離
                float3 deltaStep = (endWS - startWS) / _StepCount; // 1stepあたりの移動量

                float3 startRayWS = startWS; // レイ開始位置
                float2 rayUV; // レイのUV座標
                uint hitFlag = -1;

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
                        hitFlag = 1;
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
                        hitFlag = 2;
                        continue;
                    }

                    // ---------------------------------------------------
                    // めり込み判定・厚み付き 
                    // ---------------------------------------------------
                    // rayDepth,depth: 0(手前) ~ 1(奥)
                    float depthDiff = rayDepth - depth;

                    // 厚みが大きい場合はリターン
                    // 400は手動で調整した値, _Thicknessは0~1の範囲にしたかった
                    if (depthDiff >= 0 && depthDiff * 400 <= _Thickness)
                    {
                        hitFlag = 3;
                        break;
                    }
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

                float4 color = 0;
                int mask = 0;
                if (hitFlag == 3) {
                    IN.texcoord = rayUV;
                    color = FragNearest(IN);
                    mask = 1;
                } else {
                    // color = SAMPLE_TEXTURE2D_X_LOD(_CubeMapTexture, sampler_LinearClamp, IN.texcoord, 0); UnityのReflection Probeのオートモードが解除できず断念...
                }

                return color * mask * distanceFade * edge * _SSRFade;
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
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/UnityGBuffer.deprecated.hlsl" // Gbufferのコンポーネント一覧

            #define GBUFFER0 0 // albedo(rgb)/materialFlags
            #define GBUFFER1 1 // specular(rgb)/occlusion
            #define GBUFFER2 2 // normal(rgb)/smootheness
            FRAMEBUFFER_INPUT_X_HALF(GBUFFER0);
            FRAMEBUFFER_INPUT_X_HALF(GBUFFER1);
            FRAMEBUFFER_INPUT_X_HALF(GBUFFER2);

            TEXTURE2D_X(_GaussTexture);

            half4 frag(Varyings IN) : SV_Target
            {
                float4 gbuffer0 = LOAD_FRAMEBUFFER_X_INPUT(GBUFFER0, IN.positionCS.xy);
                float4 gbuffer1 = LOAD_FRAMEBUFFER_X_INPUT(GBUFFER1, IN.positionCS.xy);
                float4 gbuffer2 = LOAD_FRAMEBUFFER_X_INPUT(GBUFFER2, IN.positionCS.xy); // GBuffer Normal[-1~1]/Smoothness

                uint materialFlags = UnpackGBufferMaterialFlags(gbuffer0.a);
                bool isSpecularWorkflow = (materialFlags & kMaterialFlagSpecularSetup) != 0;

                half3 specular;
                if (isSpecularWorkflow)
                {
                    // specular workflow specular項を使う
                    specular = gbuffer1.rgb;
                }
                else
                {
                    // metallic workflow
                    half3 albedo = gbuffer0.rgb;
                    half3 metallic = gbuffer1.r;
                    specular = lerp(kDielectricSpec.rgb, albedo, metallic);
                }

                float4 gauss = SAMPLE_TEXTURE2D(_GaussTexture, sampler_LinearClamp, IN.texcoord);
                half3 reflection = gauss * specular; // RGBの反映率を求める
                half roughness = 1 - gbuffer2.a; // Smoothness -> Roughness (反射率)

                half4 color = FragNearest(IN) + half4(reflection, roughness);
                return color;
            }
            ENDHLSL
        }
    }
}