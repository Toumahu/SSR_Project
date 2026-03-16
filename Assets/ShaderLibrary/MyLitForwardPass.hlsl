// 光の影響を受ける汎用シェーダー
// 窓口として使う

// このファイルを使用する場合は Shader 内で以下を include してください:
// #include "Assets/ShaderLibrary/MyLitForwardPass.hlsl"

#ifndef MY_LIT_FORWARD_PASS_INCLUDED
#define MY_LIT_FORWARD_PASS_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

#include "Assets/ShaderLibrary/MySurfaceData.hlsl"
#include "Assets/ShaderLibrary/LightingInputData.hlsl"
#include "Assets/ShaderLibrary/MyInput.hlsl"
#include "Assets/ShaderLibrary/MyLitInput.hlsl"
#include "Assets/ShaderLibrary/MyLighting.hlsl"

struct Attributes
{
    float4 positionOS : POSITION;
    float2 uv : TEXCOORD0;
    float3 normalOS: NORMAL;
    float4 tangentOS: TANGENT;
};

struct Varyings
{
    float4 positionHCS : SV_POSITION;
    float3 normalWS : NORMAL;
    float4 tangentWS : TANGENT;
    float2 uv : TEXCOORD0;
    float3 positionWS : TEXCOORD1; // ワールド座標系の位置
};

void InitializeInputData(Varyings IN, float3 normalTS, out MyInputData inputData)
{
    inputData.positionWS = IN.positionWS;

    float crossSign = (IN.tangentWS.w > 0.0 ? 1.0 : -1.0) * GetOddNegativeScale(); // GetOddNegativeScale() モデルが反転したときに補正する役割
    float3 bitangentWS = crossSign * cross(IN.normalWS, IN.tangentWS.xyz);
    inputData.normalWS = normalTS.x * IN.tangentWS.xyz + 
                         normalTS.y * bitangentWS + 
                         normalTS.z * IN.normalWS;
        
    inputData.viewDirWS = normalize(_WorldSpaceCameraPos - IN.positionWS);
}

// -------------------------------------------------------------------
// Index Pass Shader Functions
// -------------------------------------------------------------------

Varyings PBRPassVertex(Attributes IN)
{
    Varyings OUT;
    OUT.positionHCS = TransformObjectToHClip(IN.positionOS.xyz);
    OUT.positionWS = TransformObjectToWorld(IN.positionOS.xyz); // ローカル->ワールド変換
    OUT.uv = TRANSFORM_TEX(IN.uv, _BaseMap);
    OUT.normalWS = TransformObjectToWorldNormal(IN.normalOS); // 正規化済み
    OUT.tangentWS = float4(TransformObjectToWorldDir(IN.tangentOS.xyz), IN.tangentOS.w); // 正規化済み
    return OUT;
}

half4 PBRPassFragment(Varyings IN) : SV_Target
{
    // サーフェス情報
    MySurfaceData surfaceData;
    LightingInputData lightingInputData;
    InitializeStandardLitSurfaceData(IN.uv, surfaceData, lightingInputData);

    // 入力情報
    MyInputData inputData;
    InitializeInputData(IN, surfaceData.normalTS, inputData);

    float3 light = MyUniversalFragmentPBR(inputData, surfaceData, lightingInputData);
    //light += surfaceData.occlusion;

    // ------------------------------------
    // テクスチャーカラーとライティングの合成
    // ------------------------------------

    // メインテクスチャカラー取得
    half4 albedo = half4(surfaceData.albedo, surfaceData.alpha);

    albedo.xyz *= light;

    return albedo;
}

#endif