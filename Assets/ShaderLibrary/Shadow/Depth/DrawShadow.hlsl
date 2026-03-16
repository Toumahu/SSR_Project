// シャドウマップに影を書き込むシェーダー
// オブジェクト単体へ割り当てる

// このファイルを使用する場合は Shader 内で以下を include してください:
// #include "Assets/ShaderLibrary/Shadow/Depth/DrawShadow.hlsl"

#ifndef DEPTH_DRAW_SHADOW_INCLUDED
#define DEPTH_DRAW_SHADOW_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

CBUFFER_START(UnityPerMaterial)
float4x4 _lightVP; // ライト用のviewProjection行列
CBUFFER_END

struct Attributes
{
    float4 positionOS : POSITION;
};

struct Varyings
{
    float4 positionHCS : SV_POSITION;
};

Varyings vert(Attributes IN)
{
    Varyings OUT;
    // world行列に変換 -> view行列に変換 -> proj行列に変換
    // world行列は共通のものを使用する
    float3 world = TransformObjectToWorld(IN.positionOS.xyz);
    OUT.positionHCS = mul(_lightVP, float4(world, 1.0));
    return OUT;
}

half4 frag(Varyings IN) : SV_Target
{
    float z = IN.positionHCS.z;
    return half4(z, z, z, 1.0f); // 白がカメラに近い(1,1,1,1), 黒が遠い(0,0,0,1)
}

#endif