// 組み込み入力変数を整形担当するHLSL
// #include "Assets/ShaderLibrary/MyInput.hlsl"

#ifndef MY_INPUT_INCLUDED
#define MY_INPUT_INCLUDED

struct MyInputData
{
    float3 positionWS; // ワールド空間の座標
    float3 normalWS;   // ワールド空間の法線ベクトル
    float3 viewDirWS;  // サーフェスから視線に向かうベクトル
};

#endif