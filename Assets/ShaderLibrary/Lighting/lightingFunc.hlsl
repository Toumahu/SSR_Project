// Assets/ShaderLibrary/lightingFunc.hlsl
// このファイルを使用する場合は Shader 内で以下を include してください:
// #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

// ランバート反射モデル計算関数
float3 CalcLambertDiffuse(float3 lightDirection, float3 lightColor, float3 normal)
{
    float diffuse = dot(normal, lightDirection);
    return lightColor * saturate(diffuse);
}

// フォン鏡面反射モデル計算関数
float3 CalcPhongSpecular(float3 lightDirection, float3 lightColor, float3 positionWS, float3 normal, float _SpecThreshold)
{
    float3 reflectDir = lightDirection + 2 * dot(normal, -lightDirection) * normal;
    float3 viewDir = normalize(positionWS - _WorldSpaceCameraPos); // カメラからポリゴンへの方向
    float specular = dot(reflectDir, viewDir);
    specular = pow(saturate(specular), _SpecThreshold); // 適当な鏡面反射の強さ
    return lightColor * specular;
}

// リムライト計算関数
float3 CalcLimLight(float3 lightDirection, float3 lightColor, float3 positionWS, float3 normalWS, float _LimLightThreshold)
{
    // ディレクショナルライトの入射角と法線からリムライトの強さ計算
    float power1 = 1.0f - max(0.0f, dot(lightDirection, normalWS));

    // 視線方向と法線からリムライトの強さ計算
    float3 viewDir = normalize(positionWS - _WorldSpaceCameraPos);
    float power2 = 1.0f - max(0.0f, dot(-viewDir, normalWS));

    float limPower = power1 * power2;
    limPower = pow(limPower, _LimLightThreshold); // リムライトの鋭さ調整
    return limPower * lightColor;
}

float3 CalcLight(float3 positionWS, float3 normalWS, float _SpecThreshold, float _LimLightThreshold, float _IsHemiLight, float _FinalLightThreshold)
{
    // ------------------------------- メインライトのライティング -------------------------------

    Light mainLight;
    mainLight = GetMainLight();

    // ランバート反射モデル
    float3 diffuseLight = CalcLambertDiffuse(mainLight.direction, mainLight.color, normalWS);
    // フォン反射モデル
    float3 specularLight = CalcPhongSpecular(mainLight.direction, mainLight.color, positionWS, normalWS, _SpecThreshold);
    // リムライト
    float3 limLight = CalcLimLight(mainLight.direction, mainLight.color, positionWS, normalWS, _LimLightThreshold);
    float3 directionLight = diffuseLight + specularLight + limLight;

    // ------------------------------- 追加のライティング(ポイントライト・スポットライトなど) -------------------------------
    Light addLight;
    int addLightCount = GetAdditionalLightsCount();
    float3 addFinalLight;

    for (int index = 0; index < addLightCount; index++) {
        addLight = GetAdditionalLight(index, positionWS);
        float3 addDiffuseLight = CalcLambertDiffuse(addLight.direction, addLight.color, normalWS);
        float3 addSpecularLight = CalcPhongSpecular(addLight.direction, addLight.color, positionWS, normalWS, _SpecThreshold);
        float3 addLimLight = CalcLimLight(addLight.direction, addLight.color, positionWS, normalWS, _LimLightThreshold);

        // 減衰を考慮したポイントライトの合成
        addDiffuseLight = addDiffuseLight * addLight.distanceAttenuation;
        addSpecularLight = addSpecularLight * addLight.distanceAttenuation;
        addLimLight = addLimLight * addLight.distanceAttenuation;

        addFinalLight += addDiffuseLight + addSpecularLight + addLimLight;
    }

    // ------------------------------- 半球ライト -------------------------------
    float3 skyColor = mainLight.color;
    float3 groundColor = float3(1,0,0); // 地面の色を赤
    float3 groundNormal = float3(0, 1, 0); // 地面の法線を真上

    float t = dot(normalWS, groundNormal);
    t = (t + 1.0) / 2; // [0,1]に変換

    float3 hemiLight = lerp(groundColor, skyColor, t);
    hemiLight = lerp(float3(0,0,0), hemiLight, _IsHemiLight); // 半球ライトの有効/無効切り替え

    // ------------------------------- ライティングの合成 -------------------------------

    // 最終的なライティング計算
    float3 finalLight = directionLight + addFinalLight + hemiLight;

    // ライトの効果を一律で底上げする
    finalLight.xyz += _FinalLightThreshold;

    return finalLight;
}