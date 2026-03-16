using UnityEngine;
using UnityEngine.Rendering;

[ExecuteAlways]
public class SSRCubeMapControl : MonoBehaviour
{
    [SerializeField] private ReflectionProbe probe = null;
    [SerializeField] private Material material = null;

    void Update()
    {
        UpdateParam();
    }

    // void OnEnable()
    // {
    //     probe.RenderProbe();
    // }

    private void UpdateParam()
    {
        probe.RenderProbe();
        material.SetTexture("_ReflectionProbe", probe.texture);

        // unity公式と同じパラメータ
        var probeTransform = probe.transform;
        material.SetVector("_ProbePosition", new Vector4(probeTransform.position.x, probeTransform.position.y, probeTransform.position.z, probe.texture.mipmapCount));
        material.SetVector("_CubeMapMax", new Vector4(probe.bounds.max.x, probe.bounds.max.y, probe.bounds.max.z, probe.blendDistance));
        material.SetVector("_CubeMapMin", new Vector4(probe.bounds.min.x, probe.bounds.min.y, probe.bounds.min.z, probe.importance));

        material.SetVector("_CubeMapHDR", probe.textureHDRDecodeValues);
        //probe.enabled = false;
    }
}
