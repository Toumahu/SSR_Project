// 周辺減光（ビネッティング）
Shader "Custom/CircleEdgeFade2"
{
    Properties
    {
        _EdgeDistance("Edge Distance", Float) = 1
        _EdgeExponent("Edge Exponent", Float) = 3
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

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float2 uv : TEXCOORD0;
            };

            CBUFFER_START(UnityPerMaterial)
                float _EdgeDistance;
                float _EdgeExponent;
            CBUFFER_END

            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                OUT.positionHCS = TransformObjectToHClip(IN.positionOS.xyz);
                OUT.uv = IN.uv;//TRANSFORM_TEX(IN.uv, _BaseMap);
                return OUT;
            }

            half4 frag(Varyings IN) : SV_Target
            {
                // 周辺減光（ビネッティング）

                // u(1 - u) * v(1 - v)の形で、中心が0.25、端が0になるような値を作る
                half2 edgeUV = IN.uv * (1 - IN.uv);
                // uかvのどちらかが0なら0（端は黒）、両方に値があるほど緩やかに明るくなる
                // 係数で明るさ調整
                float edge = edgeUV.x * edgeUV.y * _EdgeDistance;
                // フェイドの鋭さ
                edge = saturate(pow(abs(edge), _EdgeExponent));
                return half4(edge, edge, edge, 1);
            }
            ENDHLSL
        }
    }
}
