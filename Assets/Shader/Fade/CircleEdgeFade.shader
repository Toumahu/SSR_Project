Shader "Custom/CircleEdgeFade"
{
    Properties
    {
        [MainColor] _BaseColor("Base Color", Color) = (1, 1, 1, 1)
        [MainTexture] _BaseMap("Base Map", 2D) = "white"
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

            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);

            CBUFFER_START(UnityPerMaterial)
                half4 _BaseColor;
                float4 _BaseMap_ST;
            CBUFFER_END

            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                OUT.positionHCS = TransformObjectToHClip(IN.positionOS.xyz);
                OUT.uv = TRANSFORM_TEX(IN.uv, _BaseMap);
                return OUT;
            }

            half4 frag(Varyings IN) : SV_Target
            {
                // 円状にフェイドを掛ける
                half2 centerUV = half2(0.5, 0.5);
                half2 diff = IN.uv - centerUV;
                float edge = length(diff); // 三平方の定理
                // 隅の中央が[0.5, x]か[x, 0.5]で、中心[0.5,0.5]の長さを求めると0.5になるので2倍して0~1の範囲にする
                // 上下左右の隅は1を超えるので黒くなる
                edge *= 2; // [1 ~ 0 ~ 1]
                edge *= edge; // 二乗して、中心がより明るく、端がより暗くなるように緩やかなフェイドにする(放物線減衰)
                edge = max(0, 1 - edge);

                return half4(edge, edge, edge, 1);
            }
            ENDHLSL
        }
    }
}
