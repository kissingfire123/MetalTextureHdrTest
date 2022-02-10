/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Implementation of renderer class which performs Metal setup and per frame rendering
*/

@import simd;
@import MetalKit;

#import "AAPLRenderer.h"
#import "AAPLImage.h"

// Header shared between C code here, which executes Metal API commands, and .metal files, which
//   uses these types as inputs to the shaders
#import "AAPLShaderTypes.h"
#include "hdrSlider.h"

#define  UseHdrProFlag   1

// Main class performing the rendering
@implementation AAPLRenderer
{
    // The device (aka GPU) used to render
    id<MTLDevice> _device;

    id<MTLRenderPipelineState> _pipelineState;

    // The command Queue used to submit commands.
    id<MTLCommandQueue> _commandQueue;

    // The Metal texture object
    id<MTLTexture> _texture;

    // 3D texture rChannel
    id<MTLTexture> _rChannelTex;
    id<MTLTexture> _gChannelTex;
    id<MTLTexture> _bChannelTex;
    // for sampling 3D texture's sampler state
    id<MTLSamplerState> _samplerState;
    
    // The Metal buffer that holds the vertex data.
    id<MTLBuffer> _vertices;

    // hold the 3d params
    id<MTLBuffer> _fragParams;
    
    // The number of vertices in the vertex buffer.
    NSUInteger _numVertices;

    // The current size of the view.
    vector_uint2 _viewportSize;
}

- (id<MTLTexture>)loadTextureUsingAAPLImage: (NSURL *) url {
    
    AAPLImage * image = [[AAPLImage alloc] initWithTGAFileAtLocation:url];
    
    NSAssert(image, @"Failed to create the image from %@", url.absoluteString);

    MTLTextureDescriptor *textureDescriptor = [[MTLTextureDescriptor alloc] init];
    
    // Indicate that each pixel has a blue, green, red, and alpha channel, where each channel is
    // an 8-bit unsigned normalized value (i.e. 0 maps to 0.0 and 255 maps to 1.0)
    textureDescriptor.pixelFormat = MTLPixelFormatBGRA8Unorm;
    
    // Set the pixel dimensions of the texture
    textureDescriptor.width = image.width;
    textureDescriptor.height = image.height;
    
    // Create the texture from the device by using the descriptor
    id<MTLTexture> texture = [_device newTextureWithDescriptor:textureDescriptor];
    
    // Calculate the number of bytes per row in the image.
    NSUInteger bytesPerRow = 4 * image.width;
    
    MTLRegion region = {
        { 0, 0, 0 },                   // MTLOrigin
        {image.width, image.height, 1} // MTLSize
    };
    
    // Copy the bytes from the data object into the texture
    [texture replaceRegion:region
                mipmapLevel:0
                  withBytes:image.data.bytes
                bytesPerRow:bytesPerRow];
    return texture;
}

- (void) CreateSamplerState{
    MTLSamplerDescriptor* desc = [[MTLSamplerDescriptor alloc] init];
    desc.sAddressMode = MTLSamplerAddressModeClampToEdge;
    desc.tAddressMode = MTLSamplerAddressModeClampToEdge;
    desc.rAddressMode = MTLSamplerAddressModeClampToEdge;
    
    desc.minFilter = MTLSamplerMinMagFilterLinear;
    desc.magFilter = MTLSamplerMinMagFilterLinear;
    desc.mipFilter = MTLSamplerMipFilterNotMipmapped;
    desc.lodMinClamp = 0.0f;
    desc.lodMaxClamp = FLT_MAX;
    desc.maxAnisotropy = 1;
    desc.normalizedCoordinates = YES;
    
    _samplerState = [_device newSamplerStateWithDescriptor:desc];
}

- (id<MTLTexture>) CreateRgbChannelTex: (float*)rgbData{
    
    MTLTextureDescriptor* texDesc = [[MTLTextureDescriptor alloc] init];
    texDesc.textureType  = MTLTextureType3D;
    texDesc.pixelFormat  = MTLPixelFormatRGBA32Float;
    texDesc.width       = 16;
    texDesc.height      = 16;
    texDesc.depth       = 8;
    texDesc.mipmapLevelCount  = 1;
    texDesc.arrayLength      = 1;
    texDesc.usage           = MTLTextureUsageShaderRead;
    //texDesc.storageMode      = MTLStorageModeManaged;
    
    id<MTLTexture> tex = [_device newTextureWithDescriptor:texDesc];
    
    MTLRegion region = MTLRegionMake3D(0, 0, 0, 16, 16, 8);
    [tex replaceRegion:region
           mipmapLevel:0
                 slice:0
             withBytes:rgbData
           bytesPerRow:256
         bytesPerImage:4096];

    return tex;
}

- (nonnull instancetype)initWithMetalKitView:(nonnull MTKView *)mtkView
{
    self = [super init];
    if(self)
    {
        _device = mtkView.device;

        NSURL *imageFileLocation = [[NSBundle mainBundle] URLForResource:@"Image"
                                                           withExtension:@"tga"];
        
        _texture = [self loadTextureUsingAAPLImage: imageFileLocation];

        [self CreateSamplerState];
        
        _rChannelTex = [self CreateRgbChannelTex:redFloat_];
        _gChannelTex = [self CreateRgbChannelTex:greenFloat_];
        _bChannelTex = [self CreateRgbChannelTex:blueFloat_];
        
        
        
        // Set up a simple MTLBuffer with vertices which include texture coordinates
#if UseHdrProFlag
        static const AAPLVertex quadVertices[] =
        {
            // Pixel positions, Texture coordinates
            { {  250,  -250 },  { 1.f, 0.f } },//  右下
            { { -250,  -250 },  { 0.f, 0.f } },// 左下
            { { -250,   250 },  { 0.f, 1.f } },// 左上

            { {  250,  -250 },  { 1.f, 0.f } }, // 右下
            { { -250,   250 },  { 0.f, 1.f } }, // 左上
            { {  250,   250 },  { 1.f, 1.f } }, // 右上
        };
#else
        static const AAPLVertex quadVertices[] =
        {
            // Pixel positions, Texture coordinates
            { {  250,  -250 },  { 1.f, 1.f } },
            { { -250,  -250 },  { 0.f, 1.f } },
            { { -250,   250 },  { 0.f, 0.f } },

            { {  250,  -250 },  { 1.f, 1.f } },
            { { -250,   250 },  { 0.f, 0.f } },
            { {  250,   250 },  { 1.f, 0.f } },
        };
#endif
        
        // Create a vertex buffer, and initialize it with the quadVertices array
        _vertices = [_device newBufferWithBytes:quadVertices
                                         length:sizeof(quadVertices)
                                        options:MTLResourceStorageModeShared];

        // Calculate the number of vertices by dividing the byte length by the size of each vertex
        _numVertices = sizeof(quadVertices) / sizeof(AAPLVertex);

        
        static  AAPLFragParams threeDFragParams;
        threeDFragParams.ccmMat = ccmMat;
        threeDFragParams.mixWeight3f = mixWeight3f;
        threeDFragParams.mixBias1f  = mixBias1f;
        for(int i =0 ; i< 16 ;++i){
            threeDFragParams.shifts3f[i] = shifts3f[i];
            threeDFragParams.slopes3f[i]  = slopes3f[i];
        }
        _fragParams = [_device newBufferWithBytes:&threeDFragParams
                                           length:sizeof(threeDFragParams)
                                          options:MTLResourceStorageModeShared];
        
        /// Create the render pipeline.

        // Load the shaders from the default library
        id<MTLLibrary> defaultLibrary = [_device newDefaultLibrary];
        id<MTLFunction> vertexFunction = [defaultLibrary newFunctionWithName:@"vertexShader"];
#if UseHdrProFlag
        id<MTLFunction> fragmentFunction = [defaultLibrary newFunctionWithName:@"frag3DSample"];
#else
        id<MTLFunction> fragmentFunction = [defaultLibrary newFunctionWithName:@"samplingShader"];
#endif
        // Set up a descriptor for creating a pipeline state object
        MTLRenderPipelineDescriptor *pipelineStateDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
        pipelineStateDescriptor.label = @"Texturing Pipeline";
        pipelineStateDescriptor.vertexFunction = vertexFunction;
        pipelineStateDescriptor.fragmentFunction = fragmentFunction;
        pipelineStateDescriptor.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat;

        NSError *error = NULL;
        _pipelineState = [_device newRenderPipelineStateWithDescriptor:pipelineStateDescriptor
                                                                 error:&error];

        NSAssert(_pipelineState, @"Failed to create pipeline state: %@", error);

        _commandQueue = [_device newCommandQueue];
    }

    return self;
}

/// Called whenever view changes orientation or is resized
- (void)mtkView:(nonnull MTKView *)view drawableSizeWillChange:(CGSize)size
{
    // Save the size of the drawable to pass to the vertex shader.
    _viewportSize.x = size.width;
    _viewportSize.y = size.height;
}

/// Called whenever the view needs to render a frame
- (void)drawInMTKView:(nonnull MTKView *)view
{
    // Create a new command buffer for each render pass to the current drawable
    id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    commandBuffer.label = @"MyCommand";

    // Obtain a renderPassDescriptor generated from the view's drawable textures
    MTLRenderPassDescriptor *renderPassDescriptor = view.currentRenderPassDescriptor;

    if(renderPassDescriptor != nil)
    {
        id<MTLRenderCommandEncoder> renderEncoder =
        [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
        renderEncoder.label = @"MyRenderEncoder";

        // Set the region of the drawable to draw into.
        [renderEncoder setViewport:(MTLViewport){0.0, 0.0, _viewportSize.x, _viewportSize.y, -1.0, 1.0 }];

        [renderEncoder setRenderPipelineState:_pipelineState];

        [renderEncoder setVertexBuffer:_vertices
                                offset:0
                              atIndex:AAPLVertexInputIndexVertices];

        [renderEncoder setVertexBytes:&_viewportSize
                               length:sizeof(_viewportSize)
                              atIndex:AAPLVertexInputIndexViewportSize];
        
        [renderEncoder  setFragmentBuffer:_fragParams
                                   offset:0
                                  atIndex:0];

        // Set the texture object.  The AAPLTextureIndexBaseColor enum value corresponds
        ///  to the 'colorMap' argument in the 'samplingShader' function because its
        //   texture attribute qualifier also uses AAPLTextureIndexBaseColor for its index.
        [renderEncoder setFragmentTexture:_texture
                                  atIndex:AAPLTextureIndexBaseColor];
        
        [renderEncoder setFragmentTexture:_rChannelTex atIndex:AAPLTexRedChannel];
        [renderEncoder setFragmentTexture:_gChannelTex atIndex:AAPLTexGreenChannel];
        [renderEncoder setFragmentTexture:_bChannelTex atIndex:AAPLTexBlueChannel];

        [renderEncoder setFragmentSamplerState:_samplerState atIndex:AAPLTextureIndexBaseColor];
        [renderEncoder setFragmentSamplerState:_samplerState atIndex:AAPLTexRedChannel];
        [renderEncoder setFragmentSamplerState:_samplerState atIndex:AAPLTexGreenChannel];
        [renderEncoder setFragmentSamplerState:_samplerState atIndex:AAPLTexBlueChannel];
        
        // Draw the triangles.
        [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle
                          vertexStart:0
                          vertexCount:_numVertices];

        [renderEncoder endEncoding];

        // Schedule a present once the framebuffer is complete using the current drawable
        [commandBuffer presentDrawable:view.currentDrawable];
        [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> buffer){
            id<MTLTexture> curTex =  view.currentDrawable.texture;
            //NSLog(@"wathch this time's texture!\n");
        }];

    }

    // Finalize rendering here & push the command buffer to the GPU
    [commandBuffer commit];
    
}

@end
