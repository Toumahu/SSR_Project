Shader "Custom/Cubmap_Original"
{
    Properties
    {
        _Roughness("Roughness", Range(0.0, 1.0)) = 1.0
        _Occlusion("Occlusion", Range(0.0, 1.0)) = 1.0
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" }

        Pass
        {
            HLSLPROGRAM

            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/BRDF.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/GlobalIllumination.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Color.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
                float3 normalOS : NORMAL;
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 positionWS : TEXCOORD1;
                float3 normalWS : NORMAL;
            };

            // cubemap
            TEXTURECUBE(_ReflectionProbe);
            SAMPLER(sampler_ReflectionProbe);

            float4 _CubeMapMax;    // w contains the blend distance
            float4 _CubeMapMin;    // w contains the importance
            float4 _ProbePosition; // w is positive for box projection, |w| is max mip level
            float4 _CubeMapHDR;

            CBUFFER_START(UnityPerMaterial)
            float _Roughness;
            float _Occlusion;
            CBUFFER_END

            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                OUT.positionHCS = TransformObjectToHClip(IN.positionOS.xyz);
                OUT.uv = IN.uv;
                OUT.normalWS = TransformObjectToWorldNormal(IN.normalOS);
                OUT.positionWS = TransformObjectToWorld(IN.positionOS.xyz);
                return OUT;
            }

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
                return normalize(b);
            }

            half3 GlossyEnvironmentReflection2(half3 reflectVector, half perceptualRoughness, half occlusion)
            {
                half mip = PerceptualRoughnessToMipmapLevel(perceptualRoughness);
                half4 encodedIrradiance = half4(SAMPLE_TEXTURECUBE_LOD(_ReflectionProbe, sampler_ReflectionProbe, reflectVector, mip));
                half3 irradiance = DecodeHDREnvironment(encodedIrradiance, _CubeMapHDR);
                return irradiance * occlusion;
            }

            half4 frag(Varyings IN) : SV_Target
            {
                half3 viewDir = normalize(_WorldSpaceCameraPos - IN.positionWS);
                half3 refDir = reflect(-viewDir, IN.normalWS);
                refDir = boxProjection(refDir, IN.positionWS);
                half3 reflectionColor = GlossyEnvironmentReflection2(refDir, _Roughness, _Occlusion);
                return half4(IN.normalWS, 1);
            }
            ENDHLSL
        }
    }
}
