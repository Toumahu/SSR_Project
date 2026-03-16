// シャドウマップを参照して影を付ける

// このファイルを使用する場合は Shader 内で以下を include してください:
// #include "Assets/ShaderLibrary/Shadow/Depth/RecieverShadow.hlsl"

#ifndef RECIEVER_SHADOW_INCLUDED
#define RECIEVER_SHADOW_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

TEXTURE2D_SHADOW(_ShadowTexture);
SAMPLER_CMP(sampler_ShadowTexture);

float4x4 _lightVP;

/// <summary>
/// 影の影響があるかどうかを返す
/// </summary>
half ShadowAttenuation(float3 positionWS) : SV_Target
{
    float4 posInLVP = mul(_lightVP, float4(positionWS, 1));

    // ----------------------------------------
    // 1. ライト空間 → NDC
    // ----------------------------------------
    float2 ndc = posInLVP.xy / posInLVP.w; // [-1-1]

    // ----------------------------------------
    // 2. NDC → UV (xy: uv, z: depth)
    // ----------------------------------------
    float3 shadowCoord;
    shadowCoord.xy = ndc.xy * float2(0.5f, -0.5f) + 0.5f; // [0-1]
    shadowCoord.z = posInLVP.z / posInLVP.w; // ライト空間のz値

    // ----------------------------------------
    // 3. 範囲内であれば影
    // ----------------------------------------

    if (shadowCoord.x > 0.0f && shadowCoord.x < 1.0f &&
        shadowCoord.y > 0.0f && shadowCoord.y < 1.0f)
    {
        // SampleCmpLevelZeroを使用してソフトシャドウを実装する
        // 近傍4テクセル深度値を参照して遮蔽率を0.0f ~ 1.0fで返す
        return SAMPLE_TEXTURE2D_SHADOW(_ShadowTexture, sampler_ShadowTexture, shadowCoord);
    }

    return 0.0f;
}

#endif