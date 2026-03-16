// シャドウマップを参照して影を付ける

// このファイルを使用する場合は Shader 内で以下を include してください:
// #include "Assets/ShaderLibrary/Shadow/Vsm/RecieverShadow.hlsl"

#ifndef VSM_RECIEVER_SHADOW_INCLUDED
#define VSM_RECIEVER_SHADOW_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

TEXTURE2D_SHADOW(_ShadowTexture);
SAMPLER_CMP(sampler_ShadowTexture);

float4x4 _lightVP;
float3 _lightPos;

/// <summary>
/// 影の影響があるかどうかを返す
/// 明るい所は1以上の値に、暗い所は0に近い値になる
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
        float2 shadowValue = SAMPLE_TEXTURE2D(_ShadowTexture, sampler_LinearClamp, shadowCoord.xy).xy;

        if (shadowCoord.z > shadowValue.x && shadowCoord.z <= 1.0f)
        {
            // チェビシェフの不等式を利用して光が当たる確率を求める
            float depth_sq = shadowValue.x * shadowValue.x;
            
            // グループの分散具合を求める
            // 分散が大きいほど、varianceの数値は大きくなる
            // ブラー後には値が変化しているため、146.666 - 12^2 = 2.666..のように分散値が出力
            float variance = min(max(shadowValue.y - depth_sq, 0.0001f), 1.0f);
            
            // このピクセルのライトから見た深度値とシャドウマップの平均の深度値の差を求める
            float md = shadowCoord.z - shadowValue.x;
            float lit_factor = variance / (variance + md * md);
            return 1 - lit_factor;
        }
    }

    return 0.0f;
}

#endif