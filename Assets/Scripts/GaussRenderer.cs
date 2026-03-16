using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using UnityEngine.Rendering.RenderGraphModule;

public class GaussRenderer
{
    private Material material;

    private ProfilingSampler profilingSampler;

    private TextureHandle gaussXTextureHandle;
    private TextureHandle gaussYTextureHandle;

    /// <summary>
    /// ガウスブラー実行後のテクスチャハンドル
    /// </summary>
    public TextureHandle TextureHandle => gaussYTextureHandle;

#if UNITY_EDITOR
        private float debugDispersion = -1;
#endif

    private class PassData
    {
        public TextureHandle sourceTextureHandle;
        public Material material;
    }

    /// <summary>
    /// ガウスブラーコンストラクタ
    /// </summary>
    /// <param name="material">ガウスブラーのマテリアル</param>
    /// <param name="dispersion">分散度</param>
    public GaussRenderer(Material material, float dispersion)
    {
        this.material = material;
        this.profilingSampler = new ProfilingSampler(nameof(GaussRenderer));

#if UNITY_EDITOR
        this.debugDispersion = dispersion;
#endif

        // ガウス分布の重みを計算してシェーダーに渡す
        CreateWieght(dispersion);
    }

    /// <summary>
    /// ガウスブラー実行
    /// </summary>
    public void RecordRenderGraph(RenderGraph renderGraph, RenderTextureDescriptor cameraTargetDescriptor, TextureHandle sourceTextureHandle, int propertyId)
    {
        // TextureHandle作成
        CreateTextureHandle(renderGraph, cameraTargetDescriptor, sourceTextureHandle);

#if UNITY_EDITOR
        CreateWieght(debugDispersion); // ctrl+Sするとmaterialがリセットされるので再設定
#endif

        // ------------------------------------------------------------ 
        // source -> gaussX texture
        // ------------------------------------------------------------

        // source texture -> gaussXTexture RT
        using (IRasterRenderGraphBuilder builder = renderGraph.AddRasterRenderPass("GaussXPass", out PassData passData, profilingSampler))
        {
            builder.UseTexture(sourceTextureHandle, AccessFlags.Read);

            builder.SetRenderAttachment(gaussXTextureHandle, 0, AccessFlags.Write);

            // Resources/References for pass execution
            // Blit source texture
            passData.sourceTextureHandle = sourceTextureHandle;
            // Blit material
            passData.material = material;

            // Set render function
            // X方向ブラー: 0パス目を使用
            builder.SetRenderFunc((PassData passData, RasterGraphContext graphContext) =>
            {
                RasterCommandBuffer cmd = graphContext.cmd;

                Blitter.BlitTexture(cmd, passData.sourceTextureHandle, new Vector4(1, 1, 0, 0), passData.material, 0);
            });
        }

        // ------------------------------------------------------------ 
        // gaussX texture -> gaussY texture
        // ------------------------------------------------------------

        // gaussXTexture RT -> gaussYTexture RT
        using (IRasterRenderGraphBuilder builder = renderGraph.AddRasterRenderPass("GaussYPass", out PassData passData, profilingSampler))
        {
            builder.UseTexture(gaussXTextureHandle, AccessFlags.Read);

            builder.SetRenderAttachment(gaussYTextureHandle, 0, AccessFlags.Write);

            // Resources/References for pass execution
            // Blit source texture
            passData.sourceTextureHandle = gaussXTextureHandle;
            // Blit material
            passData.material = material;

            // ShaderのGlobal変数への設定ができるように
            // 要注意！
            builder.AllowGlobalStateModification(true);
            // 解説 *2
            // negativeTextureHandleが描画された後に、"_NormalEdgeTexture"という名前のGlobalTextureに設定する
            builder.SetGlobalTextureAfterPass(gaussYTextureHandle, propertyId);

            // Set render function
            // Y方向ブラー: 1パス目を使用
            builder.SetRenderFunc((PassData passData, RasterGraphContext graphContext) =>
            {
                RasterCommandBuffer cmd = graphContext.cmd;
                Blitter.BlitTexture(cmd, passData.sourceTextureHandle, new Vector4(1, 1, 0, 0), passData.material, 1);
            });
        }
    }

    private void CreateTextureHandle(RenderGraph renderGraph, RenderTextureDescriptor cameraTargetDescriptor, TextureHandle sourceTextureHandle)
    {
        // 横サイズは半分のテクスチャー: ダウンサンプリング
        RenderTextureDescriptor desc = cameraTargetDescriptor;
        TextureDesc textureDesc = sourceTextureHandle.GetDescriptor(renderGraph);
        desc.colorFormat = RenderTextureFormat.ARGB32; // Enable alpha
        desc.msaaSamples = 1;
        desc.depthBufferBits = 0;

        desc.height = textureDesc.height;
        desc.width = textureDesc.width / 2;

        // X方向ブラー用テクスチャ作成
        gaussXTextureHandle = UniversalRenderer.CreateRenderGraphTexture(renderGraph, desc, "_GaussXTexture", true, FilterMode.Bilinear);

        // 横サイズは半分のテクスチャー: ダウンサンプリング
        desc.height = textureDesc.height / 2;
        desc.width = textureDesc.width / 2;

        // Y方向ブラー用テクスチャ作成
        gaussYTextureHandle = UniversalRenderer.CreateRenderGraphTexture(renderGraph, desc, "_GaussYTexture", true, FilterMode.Bilinear);

        Debug.Log($"before texture size: {textureDesc.width}x{textureDesc.height} -> gauss texture size: {desc.width}x{desc.height}");
    }

    /// <summary>
    /// ガウス分布の重みを計算して配列に格納する
    /// </summary>
    /// <param name="dispersion">分散具合。この数値が大きくなると分散具合が強くなる</param>
    private void CreateWieght(float dispersion)
    {
        float[] wieghts = new float[8];

        float total = 0;
        for (int i = 0; i < wieghts.Length; i++)
        {
            float pos = 1.0f + 2.0f * (float)i; // 左右対称となる位置 1,3,5,7
            wieghts[i] = Mathf.Exp(-0.5f * (float)(pos * pos) / dispersion); // ガウス分布の計算
            total += 2.0f * wieghts[i]; // 左右対称なので2倍する, 1であれば左右対称で左が1右が2となるようにi分計算
        }

        // wieghts[i] は片側8個分の重み。
        // シェーダーでは±の両側に使われ、計16個分の重みになるため、
        // 合計が1になるよう16個分として正規化する。
        for (int i = 0; i < wieghts.Length; i++)
        {
            wieghts[i] /= total;
        }

        ComputeBuffer weightBuffer = new ComputeBuffer(wieghts.Length, sizeof(float));
        weightBuffer.SetData(wieghts);
        material.SetBuffer("_Weights", weightBuffer);

        Debug.Log("Gauss Weights: " + string.Join(", ", wieghts));
    }
}
