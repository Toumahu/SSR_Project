// ---------------------------------------------------
// PBRライティング計算関数群
// ---------------------------------------------------

#ifndef MY_LIGHTING_INCLUDED
#define MY_LIGHTING_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
#include "Assets/ShaderLibrary/LightingInputData.hlsl"
#include "Assets/ShaderLibrary/MyInput.hlsl"
#include "Assets/ShaderLibrary/MySurfaceData.hlsl"

/// <summary>
/// ベックマン分布を計算する
/// </summary>
/// <remark>
/// 微小面（microfacet）の法線がハーフベクトル方向を向いている確率を表す
/// </remark>
/// <param name="m">粗さ(microfacet)</param>
/// <param name="t">cosθ、ここでは N·H のように法線とハーフベクトルの内積</param>
float Beckmann(float m, float t)
{
    // t が小さい（法線とハーフベクトルが大きくずれている） と指数項が小さくなり、Dも小さくなる
    // Dが大きいほど、鏡面反射が強くなる（ ハイライトが鋭くなる）

    // 公式
    // D = 1 / (4 * m^2 * t^4) * exp(-(1/m^2) * (1 - t^2) / t^2)

    float t2 = t * t;
    float t4 = t * t * t * t;
    float m2 = m * m;
    float D = 1.0f / (4.0f * m2 * t4);
    D *= exp((-1.0f / m2) * (1.0f-t2)/ t2);
    return D;
}

/// <summary>
/// フレネルを計算。Schlick近似を使用
/// </summary>
/// <remark>
/// 入射角による反射率の変化（フレネル効果）
/// 浅い角度（視線が表面に対して斜め）では反射率が増加する
/// </remark>
/// <param name="f0">垂直入射時の反射率（金属度を使用）</param>
/// <param name="u">視線とハーフベクトル(微小面の法線)の内積</param>
float SpcFresnel(float f0, float u)
{
    // from Schlick
    return f0 + (1-f0) * pow(1-u, 5);
}

/// <summary>
/// Cook-Torranceモデルの鏡面反射を計算
/// </summary>
/// <remark>
/// BRDFというのは、「光が特定の方向から入射したとき、どの方向にどれだけ反射されるか」を表す関数です。反射の角度や強度を決める「反射の分布」を表します
/// Bidirectional Reflectance Distribution Function(双方向反射分布関数)
/// BRDFの特徴：ヘルムホルツの法則とエネルギー保存則を満たすものである（現実世界に近い表現が可能）
/// 主に微小面反射(Microfacet Model)を考慮した式が使われる：物体の表面は完全に平坦ではなく、それぞれ小さな「傾いた面（微小面）」で構成されています
/// Cook-Torranceモデル ：
/// D項（法線分布関数） ：微小面の向きの分布を表す
/// F項（フレネル項）   ：視線による反射率の変化を表す（視線に近いほど反射が強くなる）
/// G項（幾何減衰）     ：視点と光源から見て、自己遮蔽などでどれだけ反射が妨げられるかを表す
/// </remark>
/// <remark>
/// ハーフベクトルを使用する理由：
/// 微小面の法線が入射方向と視線方向の丁度中間であるため使用する
/// https://cedec.cesa.or.jp/2009/ssn_archive/pdf/sep3rd/PG42.pdf#page=40
/// </remark>
/// <param name="L">光源に向かうベクトル</param>
/// <param name="V">視点に向かうベクトル</param>
/// <param name="N">法線ベクトル</param>
/// <param name="microfacet">粗さ roughnessを用いる</param>
/// <param name="metallic">金属度</param>
float CookTorranceSpecular(float3 L, float3 V, float3 N, float microfacet, float metallic)
{
    // 金属度を垂直入射の時のフレネル反射率として扱う
    // 金属度が高いほどフレネル反射は大きくなる
    float f0 = metallic;

    // ライトに向かうベクトルと視線に向かうベクトルのハーフベクトルを求める
    float3 H = normalize(L + V);

    // 各種ベクトルがどれくらい似ているかを内積を利用して求める
    float NdotH = saturate(dot(N, H));
    float VdotH = saturate(dot(V, H));
    float NdotL = saturate(dot(N, L));
    float NdotV = saturate(dot(N, V));

    // D項をベックマン分布を用いて計算する
    float D = Beckmann(microfacet, NdotH);

    // F項をSchlick近似を用いて計算する
    float F = SpcFresnel(f0, VdotH);

    // G項を求める
    // 幾何減衰項: 影や遮蔽による反射の減衰を補正
    // 光源方向や視線方向から見えなくなる微小面の影響を考慮
    float G = min(1.0f, min(2*NdotH*NdotV/VdotH, 2*NdotH*NdotL/VdotH));

    // m項を求める
    // BRDFを正規化して、エネルギー保存則を満たすための調整
    // 基本式：4 * N・L * N・V
    float m = PI * NdotV * NdotH;

    // ここまで求めた、値を利用して、Cook-Torranceモデルの鏡面反射を求める
    return max(F * D * G / m, 0.0);
}

/// <summary>
/// フレネル反射を考慮した拡散反射を計算
/// </summary>
/// <remark>
/// この関数はフレネル反射を考慮した拡散反射率を計算します
/// フレネル反射は、光が物体の表面で反射する現象のとこで、鏡面反射の強さになります
/// 一方拡散反射は、光が物体の内部に入って、内部錯乱を起こして、拡散して反射してきた光のことです
/// つまりフレネル反射が弱いときには、拡散反射が大きくなり、フレネル反射が強いときは、拡散反射が小さくなります
/// </remark>
/// <param name="N">法線</param>
/// <param name="L">光源に向かうベクトル。光の方向と逆向きのベクトル。</param>
/// <param name="V">視線に向かうベクトル。</param>
/// <param name="roughness">粗さ。0～1の範囲。</param>
float CalcDiffuseFromFresnel(float3 N, float3 L, float3 V, float roughness)
{
    // step-1 ディズニーベースのフレネル反射による拡散反射を真面目に実装する。

    // =========================================================================================================
    // 公式
    // baseColor * ( (1 + (Fd90 - 1)(1 - cosΘl)^5) * (1 + (Fd90 - 1)(1 - cosΘv)^5) ) / π
    // この関数で行っている部分は( (1 + (Fd90 - 1)(1 - cosΘl)^5) * (1 + (Fd90 - 1)(1 - cosΘv)^5) )だけ

    // 前半の(1 + (Fd90 - 1)(1 - cosΘl)^5)：法線と光源ベクトル基準の拡散反射率
    // 後半の(1 + (Fd90 - 1)(1 - cosΘv)^5)：法線と視線ベクトル基準の拡散反射率
    // π：求めた拡散反射率の正規化定数

    // 期待される結果（cosΘの値に応じて変わるようなイメージ、要はlerpみたいな式）
    // 入射ベクトル = 法線: cosΘ = 1 ==> 拡散反射率 = 1
    // 入射ベクトル ⊥ 法線: cosΘ = 0 ==> 拡散反射率 = Fd90

    // Fd90 = 0.5f + 2.0f * roughness * cosΘ^2
    // 0.5をEAの(0.0~0.5)の範囲内だと全体の拡散反射を0.0~1.0に調整できる

    // =========================================================================================================

    // 光源に向かうベクトルと視線に向かうベクトルのハーフベクトルを求める
    float3 H = normalize(L + V); // 粗さを考慮するために反射ベクトル方向ではなくて，ハーフベクトル方向とするらしい

    //  Disney拡散反射BRDF はエネルギー保存則を満たさないため正規化を行う
    // https://zenn.dev/mebiusbox/books/619c81d2fbeafd/viewer/77aea9#%E6%AD%A3%E8%A6%8F%E5%8C%96
    float energyBias = lerp(0.0f, 0.5f, roughness);
    float energyFactor = lerp(1.0f, 1.0f / 1.51f, roughness); // 正規化値

    // 光源に向かうベクトルとハーフベクトルがどれだけ似ているかを内積で求める
    float dotLH = saturate(dot(L, H));

    // 光源に向かうベクトルとハーフベクトル
    // 光が平行に入射したときの拡散反射量を求める
    float Fd90 = energyBias + 2.0f * roughness * dotLH * dotLH;

    // 法線と光源に向かうベクトルを利用して拡散反射率を求める
    float dotNL = saturate(dot(N, L));
    float FL = (1.0f + (Fd90 - 1.0f) * pow(1.0f - dotNL, 5.0f));

    // 法線と視線に向かうベクトルを利用して拡散反射率を求める
    float dotNV = saturate(dot(N, V));
    float FV = (1.0f + (Fd90 - 1.0f) * pow(1.0f - dotNV, 5.0f));

    // それぞれの拡散反射率を掛け合わせて、エネルギー保存の法則を満たすように正規化する
    return (FL * FV) * energyFactor;
}

/// ランバート反射モデル計算関数
float3 CalcLambertDiffuse(float3 lightDirection, float3 lightColor, float3 normalWS)
{
    float NdotL = saturate(dot(normalWS, lightDirection));
    float3 diffuse = lightColor * NdotL;
    diffuse /= 3.14159f; // ランバート反射モデルの正規化 ヘルムホルツの相反性
    return diffuse;
}

/// フォン鏡面反射モデル計算関数
float3 CalcPhongSpecular(float3 lightDirection, float3 lightColor, float3 positionWS, float3 normalWS, float specularThreshold)
{
    float3 reflectDir = lightDirection + 2 * dot(normalWS, -lightDirection) * normalWS;
    float3 viewDir = normalize(positionWS - _WorldSpaceCameraPos); // カメラからポリゴンへの方向
    float specular = dot(reflectDir, viewDir);
    specular = pow(saturate(specular), specularThreshold); // 適当な鏡面反射の強さ
    return lightColor * specular;
}

/// リムライト計算関数
float3 CalcLimLight(float3 lightDirection, float3 lightColor, float3 positionWS, float3 normalWS, float limLightThreshold)
{
    // ディレクショナルライトの入射角と法線からリムライトの強さ計算
    float power1 = 1.0f - max(0.0f, dot(lightDirection, normalWS));

    // 視線方向と法線からリムライトの強さ計算
    float3 viewDir = normalize(positionWS - _WorldSpaceCameraPos);
    float power2 = 1.0f - max(0.0f, dot(-viewDir, normalWS));

    float limPower = power1 * power2;
    limPower = pow(limPower, limLightThreshold); // リムライトの鋭さ調整
    return limPower * lightColor;
}

/// 最終ライティング計算関数
float3 MyUniversalFragmentPBR(MyInputData inputData, MySurfaceData surfaceData, LightingInputData lightInputData)
{
    float3 positionWS = inputData.positionWS;
    float3 normalWS = inputData.normalWS;

    float specularThreshold = lightInputData.specularThreshold;
    float limLightThreshold = lightInputData.limLightThreshold;
    float hemiLightThreshold = lightInputData.hemiLightThreshold;

    float roughness = 1.0 - surfaceData.smoothness; // 滑らかさから粗さを計算

    // ------------------------------- メインライトのライティング -------------------------------

    Light mainLight;
    mainLight = GetMainLight();

    // ランバート反射モデル
    float3 diffuseLight = CalcLambertDiffuse(mainLight.direction, mainLight.color, normalWS);
    diffuseLight *= CalcDiffuseFromFresnel(normalWS, mainLight.direction, inputData.viewDirWS, roughness); // フレネル反射を考慮した拡散反射
    diffuseLight *= roughness; // 滑らかさが高ければ、拡散反射は弱くなる
    // フォン反射モデル
    // float3 specularLight = CalcPhongSpecular(mainLight.direction, mainLight.color, positionWS, normalWS, specularThreshold); //* surfaceData.specular;
    float3 specularLight = CookTorranceSpecular(mainLight.direction, inputData.viewDirWS, normalWS, roughness, surfaceData.metallic) * mainLight.color;
    // 金属度が高ければ、鏡面反射はスペキュラカラー、低ければ白
    // スペキュラカラーの強さを鏡面反射率として扱う
    specularLight *= lerp(float3(1,1,1), surfaceData.specular.rgb, surfaceData.metallic); // 金属度に応じてスペキュラーカラーを変化させる
    // リムライト
    float3 limLight = CalcLimLight(mainLight.direction, mainLight.color, positionWS, normalWS, limLightThreshold);
    float3 directionLight = diffuseLight + specularLight;// + limLight;

    // ------------------------------- 追加のライティング(ポイントライト・スポットライトなど) -------------------------------
    Light addLight;
    int addLightCount = GetAdditionalLightsCount();
    float3 addFinalLight = float3(0,0,0);

    // for (int index = 0; index < addLightCount; index++) {
    //     addLight = GetAdditionalLight(index, positionWS);
    //     float3 addDiffuseLight = CalcLambertDiffuse(addLight.direction, addLight.color, normalWS);
    //     //float3 addSpecularLight = CalcPhongSpecular(addLight.direction, addLight.color, positionWS, normalWS, specularThreshold) * surfaceData.specular;
    //     float3 addSpecularLight = CookTorranceSpecular(addLight.direction, inputData.viewDirWS, normalWS, roughness, surfaceData.metallic) * addLight.color;
    //     // 金属度が高ければ、鏡面反射はスペキュラカラー、低ければ白
    //     // スペキュラカラーの強さを鏡面反射率として扱う
    //     addSpecularLight *= lerp(float3(1,1,1), surfaceData.specular.rgb, surfaceData.metallic); // 金属度に応じてスペキュラーカラーを変化させる
    //     float3 addLimLight = CalcLimLight(addLight.direction, addLight.color, positionWS, normalWS, limLightThreshold);

    //     addDiffuseLight *= CalcDiffuseFromFresnel(normalWS, addLight.direction, inputData.viewDirWS, roughness); // フレネル反射を考慮した拡散反射
    //     addDiffuseLight *= roughness; // 滑らかさが高ければ、拡散反射は弱くなる

    //     // 減衰を考慮したポイントライトの合成
    //     addDiffuseLight = addDiffuseLight * addLight.distanceAttenuation;
    //     addSpecularLight = addSpecularLight * addLight.distanceAttenuation;
    //     addLimLight = addLimLight * addLight.distanceAttenuation;

    //     addFinalLight += addDiffuseLight + addSpecularLight + addLimLight;
    // }

    // ------------------------------- 半球ライト -------------------------------
    float3 skyColor = mainLight.color;
    float3 groundColor = float3(1,0,0); // 地面の色を赤
    float3 groundNormal = float3(0, 1, 0); // 地面の法線を真上

    float t = dot(normalWS, groundNormal);
    t = (t + 1.0) / 2; // [0,1]に変換

    float3 hemiLight = lerp(groundColor, skyColor, t);
    hemiLight = lerp(float3(0,0,0), hemiLight, hemiLightThreshold); // 半球ライトの有効/無効切り替え

    // ------------------------------- ライティングの合成 -------------------------------

    // 最終的なライティング計算
    float3 lig = directionLight + addFinalLight + hemiLight;
    //lig += float3(0.3,0.3,0.3) * surfaceData.occlusion; // 間接光の影響を加算
    return directionLight;
}

#endif