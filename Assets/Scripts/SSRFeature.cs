using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using UnityEngine.Rendering.RenderGraphModule;

/// <summary>
/// Screen Space Reflection (SSR)
/// </summary>
public class SSRFeature : ScriptableRendererFeature
{
    [System.Serializable]
    public class Settings
    {
        public RenderPassEvent renderPassEvent = RenderPassEvent.AfterRenderingTransparents;
        public Material material = null;
    }

    [SerializeField] private Settings settings = new Settings();
    private SSRPass pass;

    [SerializeField]
    private Material gaussMaterial = null;

    [Header("ガウス分布パラメータ")]
    [SerializeField, Range(1, 10)]
    private float dispersion = 5;

    private GaussRenderer gaussRenderer;

    public override void Create()
    {
        gaussRenderer = new GaussRenderer(gaussMaterial, dispersion);

        this.pass = new SSRPass(
            this.settings.renderPassEvent,
            this.settings.material,
            gaussRenderer
        );
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        renderer.EnqueuePass(this.pass);
    }

    protected override void Dispose(bool disposing)
    {
        // Use Dispose for cleanup
    }

    public class SSRPass : ScriptableRenderPass
    {
        private Material material;
        private GaussRenderer gaussRenderer;

        private class PassData
        {
            public TextureHandle sourceTextureHandle;
            public Material material;
        }

        public SSRPass(RenderPassEvent renderPassEvent, Material material, GaussRenderer gaussRenderer)
        {
            this.renderPassEvent = renderPassEvent;
            this.material = material;
            this.profilingSampler = new ProfilingSampler(nameof(SSRPass));
            this.gaussRenderer = gaussRenderer;
        }

        public override void RecordRenderGraph(RenderGraph renderGraph, ContextContainer frameData)
        {
            // Recording phase; add passes to RenderGraph

            // FrameData objects
            // ResourceData
            UniversalResourceData resourceData = frameData.Get<UniversalResourceData>();
            // RenderingData
            UniversalRenderingData renderingData = frameData.Get<UniversalRenderingData>();
            // CameraData
            UniversalCameraData cameraData = frameData.Get<UniversalCameraData>();
            // LightData
            UniversalLightData lightData = frameData.Get<UniversalLightData>();

            TextureHandle cameraColorTextureHandler = resourceData.activeColorTexture;
            TextureHandle cameraDepthTextureHandle = resourceData.activeDepthTexture;

            // テクスチャー情報
            RenderTextureDescriptor desc = cameraData.cameraTargetDescriptor;
            // desc.colorFormat = RenderTextureFormat.ARGB64; // Enable alpha
            desc.msaaSamples = 1;
            desc.depthBufferBits = 0;

            // SSRテクスチャー
            TextureHandle ssrTextureHandle = UniversalRenderer.CreateRenderGraphTexture(renderGraph, desc, "_SSRTexture", true, FilterMode.Point);

            // ------------------------------------------------------------ 
            // camera color texture -> ssr texture
            // ------------------------------------------------------------

            // bloom texture RT -> camera color RT
            using (IRasterRenderGraphBuilder builder = renderGraph.AddRasterRenderPass(passName, out PassData passData, this.profilingSampler))
            {
                // Set tempRT for read
                builder.UseTexture(cameraColorTextureHandler, AccessFlags.Read);
                // Set camera color RT for write
                builder.SetRenderAttachment(ssrTextureHandle, 0, AccessFlags.Write);

                // Resources/References for pass execution
                // Blit source texture
                passData.sourceTextureHandle = cameraColorTextureHandler;
                passData.material = material;

                // ShaderのGlobal変数への設定ができるように
                // 要注意！
                builder.AllowGlobalStateModification(true);
                // 解説 *2
                // negativeTextureHandleが描画された後に、"_NormalEdgeTexture"という名前のGlobalTextureに設定する
                builder.SetGlobalTextureAfterPass(ssrTextureHandle, Shader.PropertyToID("_SSRTexture"));

                builder.SetRenderFunc((PassData passData, RasterGraphContext graphContext) =>
                {
                    RasterCommandBuffer cmd = graphContext.cmd;
                    Blitter.BlitTexture(cmd, passData.sourceTextureHandle, new Vector4(1, 1, 0, 0), passData.material, 0);
                });
            }

            // ------------------------------------------------------------ 
            // ssr texture -> blur texture
            // ------------------------------------------------------------

            // グローバル変数用登録 indexは0から始まるので注意
            gaussRenderer.RecordRenderGraph(renderGraph, cameraData.cameraTargetDescriptor, ssrTextureHandle, Shader.PropertyToID("_GaussTexture"));

            // ------------------------------------------------------------ 
            // blur texture -> combine texture
            // ------------------------------------------------------------

            // combineテクスチャー
            TextureHandle combineTextureHandle = UniversalRenderer.CreateRenderGraphTexture(renderGraph, desc, "_CombineTexture", true, FilterMode.Point);

            // bloom texture RT -> camera color RT
            using (IRasterRenderGraphBuilder builder = renderGraph.AddRasterRenderPass(passName, out PassData passData, this.profilingSampler))
            {
                // Set tempRT for read
                builder.UseTexture(cameraColorTextureHandler, AccessFlags.Read);
                // Set camera color RT for write
                builder.SetRenderAttachment(combineTextureHandle, 0, AccessFlags.Write);

                // Resources/References for pass execution
                // Blit source texture
                passData.sourceTextureHandle = cameraColorTextureHandler;
                passData.material = material;

                builder.SetRenderFunc((PassData passData, RasterGraphContext graphContext) =>
                {
                    RasterCommandBuffer cmd = graphContext.cmd;
                    Blitter.BlitTexture(cmd, passData.sourceTextureHandle, new Vector4(1, 1, 0, 0), passData.material, 1);
                });
            }

            // ------------------------------------------------------------ 
            // combineTextureHandle texture -> camera color texture
            // ------------------------------------------------------------

            // combineTextureHandle texture RT -> camera color RT
            using (IRasterRenderGraphBuilder builder = renderGraph.AddRasterRenderPass(passName, out PassData passData, this.profilingSampler))
            {
                // Set tempRT for read
                builder.UseTexture(combineTextureHandle, AccessFlags.Read);
                // Set camera color RT for write
                builder.SetRenderAttachment(cameraColorTextureHandler, 0, AccessFlags.Write);

                // Resources/References for pass execution
                // Blit source texture
                passData.sourceTextureHandle = combineTextureHandle;
                passData.material = null;

                builder.SetRenderFunc((PassData passData, RasterGraphContext graphContext) =>
                {
                    RasterCommandBuffer cmd = graphContext.cmd;
                    Blitter.BlitTexture(cmd, passData.sourceTextureHandle, new Vector4(1, 1, 0, 0), 0, false);
                });
            }
        }
    }
}
