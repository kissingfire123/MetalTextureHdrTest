/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Metal shaders used for this sample
*/

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

// Include header shared between this Metal shader code and C code executing Metal API commands
#include "AAPLShaderTypes.h"

struct RasterizerData
{
    // The [[position]] attribute qualifier of this member indicates this value is
    // the clip space position of the vertex when this structure is returned from
    // the vertex shader
    float4 position [[position]];

    // Since this member does not have a special attribute qualifier, the rasterizer
    // will interpolate its value with values of other vertices making up the triangle
    // and pass that interpolated value to the fragment shader for each fragment in
    // that triangle.
    float2 textureCoordinate;

};

// Vertex Function
vertex RasterizerData
vertexShader(uint vertexID [[ vertex_id ]],
             constant AAPLVertex *vertexArray [[ buffer(AAPLVertexInputIndexVertices) ]],
             constant vector_uint2 *viewportSizePointer  [[ buffer(AAPLVertexInputIndexViewportSize) ]])

{

    RasterizerData out;

    // Index into the array of positions to get the current vertex.
    //   Positions are specified in pixel dimensions (i.e. a value of 100 is 100 pixels from
    //   the origin)
    float2 pixelSpacePosition = vertexArray[vertexID].position.xy;

    // Get the viewport size and cast to float.
    float2 viewportSize = float2(*viewportSizePointer);

    // To convert from positions in pixel space to positions in clip-space,
    //  divide the pixel coordinates by half the size of the viewport.
    // Z is set to 0.0 and w to 1.0 because this is 2D sample.
    out.position = vector_float4(0.0, 0.0, 0.0, 1.0);
    out.position.xy = pixelSpacePosition / (viewportSize / 2.0);

    // Pass the input textureCoordinate straight to the output RasterizerData. This value will be
    //   interpolated with the other textureCoordinate values in the vertices that make up the
    //   triangle.
    out.textureCoordinate = vertexArray[vertexID].textureCoordinate;

    return out;
}

// Fragment function
fragment float4
samplingShader(RasterizerData in [[stage_in]],
               texture2d<half> colorTexture [[ texture(AAPLTextureIndexBaseColor) ]])
{
    constexpr sampler textureSampler (mag_filter::linear,
                                      min_filter::linear);

    // Sample the texture to obtain a color
    const half4 colorSample = colorTexture.sample(textureSampler, in.textureCoordinate);

    // return the color of the texture
    return float4(colorSample);
}



struct FSParams
{
    float4x4 ccmMat;
    float4 shifts3f[16];
    float4 slopes3f[16];
    float4 mixWeight3f;
    float4 mixBias1f;
};

struct main0_out
{
    float4 fragColor [[color(0)]];
};

struct main0_in
{
    float2 texcoord [[user(locn0)]];
};

static inline __attribute__((always_inline))
float CaculateGuide(thread texture2d<float> inputTexture,
                    thread const sampler inputTextureSmplr,
                    thread float2& texcoord,
                    constant FSParams& v_52)
{
    float4 sColor = inputTexture.sample(inputTextureSmplr, float2(texcoord.x, ((-1.0) * texcoord.y) + 1.0));
    float4 color = float4(sColor.x, sColor.y, sColor.z, 1.0);
    float4 newColor = v_52.ccmMat * color;
    float3 newColor3f = float3(newColor.x, newColor.y, newColor.z);
    float3 guideColor = float3(0.0);
    for (int i = 0; i < 16; i++)
    {
        guideColor += (v_52.slopes3f[i].xyz * fast::max(newColor3f - v_52.shifts3f[i].xyz, float3(0.0)));
    }
    float guideValue = 0.0;
    guideValue = dot(guideColor, v_52.mixWeight3f.xyz) + v_52.mixBias1f.x;
    return guideValue;
}

fragment main0_out frag3DSample(RasterizerData in [[stage_in]], constant FSParams& v_52 [[buffer(0)]],
                         texture2d<float> inputTexture [[texture(0)]],
                         texture3d<float> redChannelTexture [[texture(1)]],
                         texture3d<float> greenChannelTexture [[texture(2)]],
                         texture3d<float> blueChannelTexture [[texture(3)]],
                         sampler inputTextureSmplr [[sampler(0)]],
                         sampler redChannelTextureSmplr [[sampler(1)]],
                         sampler greenChannelTextureSmplr [[sampler(2)]],
                         sampler blueChannelTextureSmplr [[sampler(3)]])
{
    main0_out out = {};
    float guideValue = CaculateGuide(inputTexture, inputTextureSmplr, in.textureCoordinate, v_52);
    float3 coord3D = float3(in.textureCoordinate.x, in.textureCoordinate.y, guideValue);
    float4 rColor = redChannelTexture.sample(redChannelTextureSmplr, coord3D,0);
    float4 gColor = greenChannelTexture.sample(greenChannelTextureSmplr, coord3D,0);
    float4 bColor = blueChannelTexture.sample(blueChannelTextureSmplr, coord3D,0);
    float4 inputColor = float4(inputTexture.sample(inputTextureSmplr, float2(in.textureCoordinate.x, ((-1.0) * in.textureCoordinate.y) + 1.0)).xyz, 1.0);
    float r = dot(float4(inputColor.xyz, 1.0), rColor);
    float g = dot(float4(inputColor.xyz, 1.0), gColor);
    float b = dot(float4(inputColor.xyz, 1.0), bColor);
    out.fragColor = float4(fast::clamp(float3(r, g, b), float3(0.0), float3(1.0)), 1.0);
    return out;
}
