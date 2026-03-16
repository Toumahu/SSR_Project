Shader "CubeMapReflectProbe"
{
    Properties
    {
        [MaterialToggle] _BoxProjection("Box Projection", float) = 0
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" }

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            float _BoxProjection;
                
            #include "UnityCG.cginc"
            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
                float4 normal: NORMAL;
            };

            struct v2f
            {
                float4 vertex : SV_POSITION;
                float3 worldPos : TEXCOORD0;
                float3 worldNormal : TEXCOORD1;
                float3 pos : TEXCOORD2;
                float2 uv : TEXCOORD3;
            };
            
            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.worldPos = mul(unity_ObjectToWorld, v.vertex);
                o.worldNormal = UnityObjectToWorldNormal(v.normal);
                o.uv = v.uv;
                return o;
            }

            /// <summary>
            /// 反射ベクトルがprobe中心からずれた場合に、中心からの反射ベクトル方向へ戻す処理
            /// </summary>
            float3 boxProjection(float3 worldPos, float3 reflDir)
            {
                // 移り込み補正のために反射ベクトルの長さの調整
                // それぞれの面との距離を求める
                float3 boxMin = unity_SpecCube0_BoxMin;
                float3 boxMax = unity_SpecCube0_BoxMax;
                // cubeMapのどこの壁に当たるかチェック
                // x = worldPos + reflDir * magnitude;
                // magnitude = (x - worldPos) / reflDir
                float magnitudeX = ((reflDir.x > 0 ? boxMax.x : boxMin.x) - worldPos.x) / reflDir.x;
                float magnitudeY = ((reflDir.y > 0 ? boxMax.y : boxMin.y) - worldPos.y) / reflDir.y;
                float magnitudeZ = ((reflDir.z > 0 ? boxMax.z : boxMin.z) - worldPos.z) / reflDir.z;

                float magnitude = min(min(magnitudeX, magnitudeY), magnitudeZ);

                // probe中心からの斜辺(ベクトル方向)を求める
                float3 a = worldPos - unity_SpecCube0_ProbePosition;
                float3 c = reflDir * magnitude;
                float3 b = a + c;

                // probeの中心座標
                // 反射ベクトル
                return b;
            }
            
            fixed4 frag (v2f i) : SV_Target
            {
                half3 worldViewDir = normalize(_WorldSpaceCameraPos - i.worldPos);
                half3 reflDir = reflect(-worldViewDir, i.worldNormal);
                reflDir = _BoxProjection == 1 ? boxProjection(i.worldPos, reflDir) : reflDir;
                
                // unity_SpecCube0はUnityで定義されているキューブマップ
                half4 refColor = UNITY_SAMPLE_TEXCUBE_LOD(unity_SpecCube0, reflDir, 0);

                // Reflection ProbeがHDR設定だった時に必要な処理
                refColor.rgb = DecodeHDR(refColor, unity_SpecCube0_HDR);

                return refColor;
            }
            ENDCG
        }
    }
}