// #include "Assets/ShaderLibrary/MySurfaceData.hlsl"

#ifndef MY_SURFACE_DATA_INCLUDED
#define MY_SURFACE_DATA_INCLUDED

struct MySurfaceData
{
    half3 albedo;
    half4 specular;
    half  metallic;
    half  smoothness;
    half3 normalTS;
    // half3 emission;
    half occlusion;
    half alpha;
    // half  clearCoatMask;
    // half  clearCoatSmoothness;
};

#endif