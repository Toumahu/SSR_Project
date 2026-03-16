// #include "Assets/ShaderLibrary/LightingInputData.hlsl"

#ifndef MY_LIGHTING_INPUT_DATA_INCLUDED
#define MY_LIGHTING_INPUT_DATA_INCLUDED

struct LightingInputData
{
    float specularThreshold;   // 鏡面反射の鋭さ
    float limLightThreshold;   // リムライトの鋭さ
    float hemiLightThreshold;  // 半球ライトの強さ
};

#endif