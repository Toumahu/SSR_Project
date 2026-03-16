using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using UnityEngine.Rendering.RenderGraphModule;

public class DepthToWorldFeature : ScriptableRendererFeature
{
    [System.Serializable]
    public class Settings
    {
        public RenderPassEvent renderPassEvent = RenderPassEvent.AfterRenderingTransparents;
        public Material material = null;
        [Range(0, 4)] public int gBufferIndex = 0;
    }

    [SerializeField] private Settings settings = new Settings();
    private DepthToWorldPass pass;

    public override void Create()
    {
        this.pass = new DepthToWorldPass(
            this.settings.renderPassEvent,
            this.settings.material,
            this.settings.gBufferIndex
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

    public class DepthToWorldPass : ScriptableRenderPass
    {
        private Material material;

        private int gBufferIndex = 0;

        private class PassData
        {
            public TextureHandle sourceTextureHandle;
            public Material material;
        }

        public DepthToWorldPass(RenderPassEvent renderPassEvent, Material material, int gBufferIndex)
        {
            this.renderPassEvent = renderPassEvent;
            this.material = material;
            this.profilingSampler = new ProfilingSampler(nameof(DepthToWorldPass));
            this.gBufferIndex = gBufferIndex;
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
            desc.colorFormat = RenderTextureFormat.ARGB32; // Enable alpha
            desc.msaaSamples = 1;
            desc.depthBufferBits = 0;

            // 輝度テクスチャー
            TextureHandle textureHandle = UniversalRenderer.CreateRenderGraphTexture(renderGraph, desc, "_WorldTexture", true, FilterMode.Point);

            // ------------------------------------------------------------ 
            // camera color texture -> dof texture
            // ------------------------------------------------------------

            // bloom texture RT -> camera color RT
            using (IRasterRenderGraphBuilder builder = renderGraph.AddRasterRenderPass(passName, out PassData passData, this.profilingSampler))
            {
                // Set tempRT for read
                builder.UseTexture(cameraColorTextureHandler, AccessFlags.Read);
                // Set camera color RT for write
                builder.SetRenderAttachment(textureHandle, 0, AccessFlags.Write);

                // Resources/References for pass execution
                // Blit source texture
                passData.sourceTextureHandle = cameraColorTextureHandler;
                passData.material = material;

                builder.SetRenderFunc((PassData passData, RasterGraphContext graphContext) =>
                {
                    RasterCommandBuffer cmd = graphContext.cmd;
                    Blitter.BlitTexture(cmd, passData.sourceTextureHandle, new Vector4(1, 1, 0, 0), passData.material, 0);
                });
            }

            // ------------------------------------------------------------ 
            // dof texture -> camera color texture
            // ------------------------------------------------------------

            // bloom texture RT -> camera color RT
            using (IRasterRenderGraphBuilder builder = renderGraph.AddRasterRenderPass(passName, out PassData passData, this.profilingSampler))
            {
                // Set tempRT for read
                builder.UseTexture(textureHandle, AccessFlags.Read);
                // Set camera color RT for write
                builder.SetRenderAttachment(cameraColorTextureHandler, 0, AccessFlags.Write);

                // Resources/References for pass execution
                // Blit source texture
                passData.sourceTextureHandle = textureHandle;
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
