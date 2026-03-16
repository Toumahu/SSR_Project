// アプリケーション側でmaterial.SetBufferしている影響か、ctrl+SをUnityEditorで押すとキャッシュが削除されて画面が黒くなる
// 尚、ゲーム再生中にすると正常に動作する
Shader "Custom/GaussShader"
{
    Properties
    {
        _TintColor("Tint Color", Color) = (1, 1, 1, 1)
    }

    SubShader
    {
        Tags { "RenderPipeline" = "UniversalPipeline" }
        ZWrite Off
        Cull Off
        Pass
        {
            Name "GaussX"

            HLSLPROGRAM

            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Color.hlsl"

            struct VaryingsEX : Varyings
            {
                float2 tex1 : TEXCOORD1;
                float2 tex2 : TEXCOORD2;
                float2 tex3 : TEXCOORD3;
                float2 tex4 : TEXCOORD4;
                float2 tex5 : TEXCOORD5;
                float2 tex6 : TEXCOORD6;
                float2 tex7 : TEXCOORD7;
                float2 tex8 : TEXCOORD8;
            };

            StructuredBuffer<float> _Weights;

            CBUFFER_START(UnityPerMaterial)
                half4 _TintColor;
            CBUFFER_END

            VaryingsEX vert(Attributes input)
            {
                Varyings o = Vert((Attributes)input);
                
                VaryingsEX output;
                output.positionCS = o.positionCS;
                output.texcoord = o.texcoord;

                float2 tex = o.texcoord;
                int screenWidth = _ScreenParams.x / 2; // テクスチャーサイズ:スクリーン画面の半分の幅

                output.tex1 = tex + float2(-1.0f / screenWidth, 0);
                output.tex2 = tex + float2(-3.0f / screenWidth, 0);
                output.tex3 = tex + float2(-5.0f / screenWidth, 0);
                output.tex4 = tex + float2(-7.0f / screenWidth, 0);
                output.tex5 = tex + float2(-9.0f / screenWidth, 0);
                output.tex6 = tex + float2(-11.0f / screenWidth, 0);
                output.tex7 = tex + float2(-13.0f / screenWidth, 0);
                output.tex8 = tex + float2(-15.0f / screenWidth, 0);

                return output;
            }

            half4 BlitColor(float weight, float2 uv1, float2 uv2, Varyings input1, Varyings input2)
            {
                input1.texcoord = uv1;
                input2.texcoord = uv2;
                return weight * (FragBlit(input1, sampler_LinearClamp) + FragBlit(input2, sampler_LinearClamp));
            }

            half4 frag(VaryingsEX input) : SV_Target
            {
                half4 color;
                float2 offset = float2(16.0 / (_ScreenParams.x / 2), 0); // テクスチャーサイズ:スクリーン画面の半分の幅

                Varyings input1 = (Varyings)input;
                Varyings input2 = input1;

                color =  BlitColor(_Weights[0], input.tex1, input.tex8 + offset, input1, input2);
                color += BlitColor(_Weights[1], input.tex2, input.tex7 + offset, input1, input2);
                color += BlitColor(_Weights[2], input.tex3, input.tex6 + offset, input1, input2);
                color += BlitColor(_Weights[3], input.tex4, input.tex5 + offset, input1, input2);
                color += BlitColor(_Weights[4], input.tex5, input.tex4 + offset, input1, input2);
                color += BlitColor(_Weights[5], input.tex6, input.tex3 + offset, input1, input2);
                color += BlitColor(_Weights[6], input.tex7, input.tex2 + offset, input1, input2);
                color += BlitColor(_Weights[7], input.tex8, input.tex1 + offset, input1, input2);

                return color;
            }

            ENDHLSL
        }

        Pass
        {
            Name "GaussY"

            HLSLPROGRAM

            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Color.hlsl"

            struct VaryingsEX : Varyings
            {
                float2 tex1 : TEXCOORD1;
                float2 tex2 : TEXCOORD2;
                float2 tex3 : TEXCOORD3;
                float2 tex4 : TEXCOORD4;
                float2 tex5 : TEXCOORD5;
                float2 tex6 : TEXCOORD6;
                float2 tex7 : TEXCOORD7;
                float2 tex8 : TEXCOORD8;
            };

            StructuredBuffer<float> _Weights;

            CBUFFER_START(UnityPerMaterial)
                half4 _TintColor;
            CBUFFER_END

            VaryingsEX vert(Attributes input)
            {
                Varyings o = Vert((Attributes)input);
                
                VaryingsEX output;
                output.positionCS = o.positionCS;
                output.texcoord = o.texcoord;

                float2 tex = o.texcoord;
                int screenWidth = _ScreenParams.y / 2; // テクスチャーサイズ:スクリーン画面の半分の幅

                output.tex1 = tex + float2(0, -1.0f / screenWidth);
                output.tex2 = tex + float2(0, -3.0f / screenWidth);
                output.tex3 = tex + float2(0, -5.0f / screenWidth);
                output.tex4 = tex + float2(0, -7.0f / screenWidth);
                output.tex5 = tex + float2(0, -9.0f / screenWidth);
                output.tex6 = tex + float2(0, -11.0f / screenWidth);
                output.tex7 = tex + float2(0, -13.0f / screenWidth);
                output.tex8 = tex + float2(0, -15.0f / screenWidth);

                return output;
            }

            half4 BlitColor(float weight, float2 uv1, float2 uv2, Varyings input1, Varyings input2)
            {
                input1.texcoord = uv1;
                input2.texcoord = uv2;
                return weight * (FragBlit(input1, sampler_LinearClamp) + FragBlit(input2, sampler_LinearClamp));
            }

            half4 frag(VaryingsEX input) : SV_Target
            {
                half4 color;
                float2 offset = float2(0, 16.0 / (_ScreenParams.y / 2)); // テクスチャーサイズ:スクリーン画面の半分の幅

                Varyings input1 = (Varyings)input;
                Varyings input2 = input1;

                color =  BlitColor(_Weights[0], input.tex1, input.tex8 + offset, input1, input2);
                color += BlitColor(_Weights[1], input.tex2, input.tex7 + offset, input1, input2);
                color += BlitColor(_Weights[2], input.tex3, input.tex6 + offset, input1, input2);
                color += BlitColor(_Weights[3], input.tex4, input.tex5 + offset, input1, input2);
                color += BlitColor(_Weights[4], input.tex5, input.tex4 + offset, input1, input2);
                color += BlitColor(_Weights[5], input.tex6, input.tex3 + offset, input1, input2);
                color += BlitColor(_Weights[6], input.tex7, input.tex2 + offset, input1, input2);
                color += BlitColor(_Weights[7], input.tex8, input.tex1 + offset, input1, input2);

                return color;
            }

            ENDHLSL
        }
    }
}