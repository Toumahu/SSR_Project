// シャドウマップに影を書き込むシェーダー
// オブジェクト単体へ割り当てる

// このファイルを使用する場合は Shader 内で以下を include してください:
// #include "Assets/ShaderLibrary/Shadow/Vsm/DrawShadow.hlsl"

#ifndef VSM_DRAW_SHADOW_INCLUDED
#define VSM_DRAW_SHADOW_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

CBUFFER_START(UnityPerMaterial)
float4x4 _lightVP; // ライト用のviewProjection行列
float3 _lightPos; // ライト座標
CBUFFER_END

struct Attributes
{
    float4 positionOS : POSITION;
};

struct Varyings
{
    float4 positionHCS : SV_POSITION;
    float2 depth : TEXCOORD0;
};

Varyings vert(Attributes IN)
{
    Varyings OUT;
    // world行列に変換 -> view行列に変換 -> proj行列に変換
    // world行列は共通のものを使用する
    float3 world = TransformObjectToWorld(IN.positionOS.xyz);
    
    OUT.positionHCS = mul(_lightVP, float4(world, 1.0));

    OUT.depth.x = length(world - _lightPos); // ライトからの距離をdepthとして使用
    OUT.depth.y = OUT.depth.x * OUT.depth.x; // 距離の二乗
    
    return OUT;
}

half4 frag(Varyings IN) : SV_Target
{
    // step-10 ライトから見た深度値と、ライトから見た深度値の2乗を出力する
    // ブラー後に平均をとることで値が変化する
    // x: [10, 12, 14]の平均をとる、(10+12+14)/3=12
    // y: [10^2, 12^2, 14^2]の平均を取る、(100+144+169)/3=146.666..
    return float4(IN.depth.x, IN.depth.y, 0.0f, 1.0f);
}

#endif