//
//  Shaders.metal
//  MyHybridRendering
//
//  Created by Caroline on 30/7/2025.
//

#include <metal_stdlib>
#include "Common.h"

using namespace metal;


constant float kMaxHDRValue = 500.0f;

typedef struct
{
    float4 position [[position]];
    float3 ndcpos;
    float3 worldPosition;
    float3 normal;
    float3 tangent;
    float3 bitangent;
    float3 r;
    float2 texCoord;
} ColorInOut;

#pragma mark - Lighting

struct LightingParameters
{
    float3  lightDir;
    float3  viewDir;
    float3  halfVector;
    float3  reflectedVector;
    float3  normal;
    float3  reflectedColor;
    float3  irradiatedColor;
    float4  baseColor;
    float   nDoth;
    float   nDotv;
    float   nDotl;
    float   hDotl;
    float   metalness;
    float   roughness;
    float   ambientOcclusion;
};

constexpr sampler linearSampler (address::repeat,
                                 mip_filter::linear,
                                 mag_filter::linear,
                                 min_filter::linear);

constexpr sampler nearestSampler(address::repeat,
                                 min_filter::nearest,
                                 mag_filter::nearest,
                                 mip_filter::none);

inline float Fresnel(float dotProduct);
inline float sqr(float a);
float3 computeSpecular(LightingParameters parameters);
float Geometry(float Ndotv, float alphaG);
float3 computeNormalMap(ColorInOut in, texture2d<float> normalMapTexture);
float3 computeDiffuse(LightingParameters parameters);
float Distribution(float NdotH, float roughness);

inline float Fresnel(float dotProduct) {
    return pow(clamp(1.0 - dotProduct, 0.0, 1.0), 5.0);
}

inline float sqr(float a) {
    return a * a;
}

float Geometry(float Ndotv, float alphaG) {
  float a = alphaG * alphaG;
  float b = Ndotv * Ndotv;
  return (float)(1.0 / (Ndotv + sqrt(a + b - a*b)));
}

float3 computeNormalMap(ColorInOut in, texture2d<float> normalMapTexture) {
    float4 encodedNormal = normalMapTexture.sample(nearestSampler, float2(in.texCoord));
    float4 normalMap = float4(normalize(encodedNormal.xyz * 2.0 - float3(1,1,1)), 0.0);
    return float3(normalize(in.normal * normalMap.z + in.tangent * normalMap.x + in.bitangent * normalMap.y));
}

float3 computeDiffuse(LightingParameters parameters)
{
    float3 diffuseRawValue = float3(((1.0/M_PI_F) * parameters.baseColor) * (1.0 - parameters.metalness));
    return diffuseRawValue * (parameters.nDotl * parameters.ambientOcclusion);
}

float Distribution(float NdotH, float roughness)
{
    if (roughness >= 1.0)
        return 1.0 / M_PI_F;

    float roughnessSqr = saturate( roughness * roughness );

    float d = (NdotH * roughnessSqr - NdotH) * NdotH + 1;
    return roughnessSqr / (M_PI_F * d * d);
}

float3 computeSpecular(LightingParameters parameters)
{
    float specularRoughness = saturate( parameters.roughness * (1.0 - parameters.metalness) + parameters.metalness );

    float Ds = Distribution(parameters.nDoth, specularRoughness);

    float3 Cspec0 = parameters.baseColor.rgb;
    float3 Fs = float3(mix(float3(Cspec0), float3(1), Fresnel(parameters.hDotl)));
    float alphaG = sqr(specularRoughness * 0.5 + 0.5);
    float Gs = Geometry(parameters.nDotl, alphaG) * Geometry(parameters.nDotv, alphaG);

    float3 specularOutput = (Ds * Gs * Fs * parameters.irradiatedColor) * (1.0 + parameters.metalness * float3(parameters.baseColor))
    + float3(parameters.metalness) * parameters.irradiatedColor * float3(parameters.baseColor);

    return specularOutput * parameters.ambientOcclusion;
}

// The helper for the equirectangular textures.
float4 equirectangularSample(float3 direction, sampler s, texture2d<float> image)
{
    float3 d = normalize(direction);

    float2 t = float2((atan2(d.z, d.x) + M_PI_F) / (2.f * M_PI_F), acos(d.y) / M_PI_F);

    return image.sample(s, t);
}

LightingParameters calculateParameters(ColorInOut in,
                                       CameraData cameraData,
                                       constant LightData& lightData,
                                       texture2d<float>   baseColorMap,
                                       texture2d<float>   normalMap,
                                       texture2d<float>   metallicMap,
                                       texture2d<float>   roughnessMap,
                                       texture2d<float>   ambientOcclusionMap,
                                       texture2d<float>   skydomeMap)
{
    LightingParameters parameters;

    parameters.baseColor = baseColorMap.sample(linearSampler, in.texCoord.xy);

    parameters.normal = computeNormalMap(in, normalMap);

    parameters.viewDir = normalize(cameraData.cameraPosition - float3(in.worldPosition));

    parameters.roughness = max(roughnessMap.sample(linearSampler, in.texCoord.xy).x, 0.001f) * 0.8;

    parameters.metalness = max(metallicMap.sample(linearSampler, in.texCoord.xy).x, 0.1);

    parameters.ambientOcclusion = ambientOcclusionMap.sample(linearSampler, in.texCoord.xy).x;

    parameters.reflectedVector = reflect(-parameters.viewDir, parameters.normal);
    
    constexpr sampler linearFilterSampler(coord::normalized, address::clamp_to_edge, filter::linear);
    float3 c = equirectangularSample(parameters.reflectedVector, linearFilterSampler, skydomeMap).rgb;
    parameters.irradiatedColor = clamp(c, 0.f, kMaxHDRValue);

    parameters.lightDir = lightData.directionalLightInvDirection;
    parameters.nDotl = max(0.001f,saturate(dot(parameters.normal, parameters.lightDir)));

    parameters.halfVector = normalize(parameters.lightDir + parameters.viewDir);
    parameters.nDoth = max(0.001f,saturate(dot(parameters.normal, parameters.halfVector)));
    parameters.nDotv = max(0.001f,saturate(dot(parameters.normal, parameters.viewDir)));
    parameters.hDotl = max(0.001f,saturate(dot(parameters.lightDir, parameters.halfVector)));

    return parameters;
}

#pragma mark - Skybox

struct SkyboxVertex
{
    float3 position [[ attribute(Position) ]];
    float2 texcoord [[ attribute(UV)]];
};

struct SkyboxV2F
{
    float4 position [[position]];
    float4 cameraToPointV;
    float2 texcoord;
    float y;
};

vertex SkyboxV2F skyboxVertex(SkyboxVertex in [[stage_in]],
                                 constant CameraData& cameraData [[buffer(BufferIndexCameraData)]])
{
    SkyboxV2F v;
    v.cameraToPointV = cameraData.viewMatrix * float4( in.position, 1.0f );
    v.position = cameraData.projectionMatrix * v.cameraToPointV;
    v.texcoord = in.texcoord;
    v.y = v.cameraToPointV.y / v.cameraToPointV.w;
    return v;
}

fragment float4 skyboxFragment(SkyboxV2F v [[stage_in]], texture2d<float> skytexture [[texture(0)]])
{
    constexpr sampler linearFilterSampler(coord::normalized, address::clamp_to_edge, filter::linear);
    float3 c = equirectangularSample(v.cameraToPointV.xyz/v.cameraToPointV.w, linearFilterSampler, skytexture).rgb;
    return float4(clamp(c, 0.f, kMaxHDRValue), 1.f);
}

#pragma mark - Rasterization

typedef struct
{
    float3 position  [[ attribute(Position) ]];
    float2 texCoord  [[ attribute(UV) ]];
    float3 normal    [[ attribute(Normal) ]];
    float3 tangent   [[ attribute(Tangent) ]];
    float3 bitangent [[ attribute(Bitangent) ]];
} Vertex;

vertex ColorInOut vertexShader(Vertex in [[stage_in]],
                               constant InstanceTransform& instanceTransform [[ buffer(BufferIndexInstanceTransforms) ]],
                               constant CameraData& cameraData [[ buffer(BufferIndexCameraData) ]])
{
    ColorInOut out;

    float4 position = float4(in.position, 1.0);
    out.position = cameraData.projectionMatrix * cameraData.viewMatrix * instanceTransform.modelViewMatrix * position;
    out.ndcpos = out.position.xyz/out.position.w;

    // Reflections and lighting that occur in the world space, so
    // `camera.viewMatrix` isn’t taken into consideration here.
    float4x4 objToWorld = instanceTransform.modelViewMatrix;
    out.worldPosition = (objToWorld * position).xyz;

    float3x3 normalMx = float3x3(objToWorld.columns[0].xyz,
                                 objToWorld.columns[1].xyz,
                                 objToWorld.columns[2].xyz);
    out.normal = normalMx * normalize(in.normal);
    out.tangent = normalMx * normalize(in.tangent);
    out.bitangent = normalMx * normalize(in.bitangent);

    float3 v = out.worldPosition - cameraData.cameraPosition;
    out.r = reflect( v, out.normal );

    out.texCoord = in.texCoord;

    return out;
}

float2 calculateScreenCoord( float3 ndcpos )
{
    float2 screenTexcoord = (ndcpos.xy) * 0.5 + float2(0.5);
    screenTexcoord.y = 1.0 - screenTexcoord.y;
    return screenTexcoord;
}

fragment float4 fragmentShader(
                    ColorInOut                  in                    [[stage_in]],
                    constant CameraData&    cameraData            [[ buffer(BufferIndexCameraData) ]],
                    constant LightData&     lightData             [[ buffer(BufferIndexLightData) ]],
                    constant SubmeshKeypath&submeshKeypath        [[ buffer(BufferIndexSubmeshKeypath)]],
                    constant SceneData*             pScene                [[ buffer(SceneIndex)]],
                    texture2d<float>            skydomeMap            [[ texture(SkyDomeTexture) ]])
{
    constexpr sampler colorSampler(mip_filter::linear,
                                   mag_filter::linear,
                                   min_filter::linear);

    float2 screenTexcoord = calculateScreenCoord( in.ndcpos );
    
    constant InstanceData *instancesArray = (constant InstanceData*)pScene->instances;
  uint32_t meshIndex = instancesArray[submeshKeypath.instanceID].meshIndex;
  constant MeshData* meshesArray = (constant MeshData*)pScene->meshes;
  constant MeshData& mesh = meshesArray[meshIndex];
  constant SubmeshData* submeshesArray = (constant SubmeshData*) mesh.submeshes;
  constant SubmeshData& submesh = submeshesArray[submeshKeypath.submeshID];
//    constant MeshData* pMesh = &(pScene->meshes[ pScene->instances[submeshKeypath.instanceID].meshIndex]);
//    constant SubmeshData* pSubmesh = &(pMesh->submeshes[submeshKeypath.submeshID]);

    LightingParameters params = calculateParameters(in,
                                                    cameraData,
                                                    lightData,
                                                    submesh.materials[BaseColorTexture],        //colorMap
                                                    submesh.materials[NormalTexture],           //normalMap
                                                    submesh.materials[MetallicTexture],         //metallicMap
                                                    submesh.materials[RoughnessTexture],        //roughnessMap
                                                    submesh.materials[AOTexture], //ambientOcclusionMap
                                                    skydomeMap);

    float li = lightData.lightIntensity;
    params.roughness += cameraData.roughnessBias;
    clamp( params.roughness, 0.f, 0.8f );

    params.metalness += cameraData.metallicBias;
    float4 final_color = float4(computeSpecular(params) + li * computeDiffuse(params), 1.0f);
    return final_color;
}

struct ThinGBufferOut
{
    float4 position [[color(0)]];
    float4 direction [[color(1)]];
};

fragment ThinGBufferOut gBufferFragmentShader(ColorInOut in [[stage_in]])
{
    ThinGBufferOut out;

    out.position = float4(in.worldPosition, 1.0);
    out.direction = float4(in.r, 0.0);

    return out;
}

#if __METAL_VERSION__ >= 230

struct VertexInOut
{
    float4 position [[position]];
    float2 uv;
};

constant float4 s_quad[] = {
    float4( -1.0f, +1.0f, 0.0f, 1.0f ),
    float4( -1.0f, -1.0f, 0.0f, 1.0f ),
    float4( +1.0f, -1.0f, 0.0f, 1.0f ),
    float4( +1.0f, -1.0f, 0.0f, 1.0f ),
    float4( +1.0f, +1.0f, 0.0f, 1.0f ),
    float4( -1.0f, +1.0f, 0.0f, 1.0f )
};

constant float2 s_quadtc[] = {
    float2( 0.0f, 0.0f ),
    float2( 0.0f, 1.0f ),
    float2( 1.0f, 1.0f ),
    float2( 1.0f, 1.0f ),
    float2( 1.0f, 0.0f ),
    float2( 0.0f, 0.0f )
};

vertex VertexInOut vertexPassthrough( uint vid [[vertex_id]] )
{
    VertexInOut o;
    o.position = s_quad[vid];
    o.uv = s_quadtc[vid];
    return o;
}

fragment float4 fragmentPassthrough( VertexInOut in [[stage_in]], texture2d< float > tin )
{
    constexpr sampler s( address::repeat, min_filter::linear, mag_filter::linear );
    return tin.sample( s, in.uv );
}

fragment float4 fragmentBloomThreshold( VertexInOut in [[stage_in]],
                                       texture2d< float > tin [[texture(0)]],
                                       constant float* threshold [[buffer(0)]] )
{
    constexpr sampler s( address::repeat, min_filter::linear, mag_filter::linear );
    float4 c = tin.sample( s, in.uv );
    if ( dot( c.rgb, float3( 0.299f, 0.587f, 0.144f ) ) > (*threshold) )
    {
        return c;
    }
    return float4(0.f, 0.f, 0.f, 1.f );
}

// The standard ACES tonemap function from "Modern Rendering" sample.
static float3 ToneMapACES(float3 x)
{
    float a = 2.51f;
    float b = 0.03f;
    float c = 2.43f;
    float d = 0.59f;
    float e = 0.14f;
    return saturate((x*(a*x+b))/(x*(c*x+d)+e));
}

fragment float4 fragmentPostprocessMerge( VertexInOut in [[stage_in]],
                                         constant float& exposure [[buffer(0)]],
                                         texture2d< float > texture0 [[texture(0)]],
                                         texture2d< float > texture1 [[texture(1)]])
{
    constexpr sampler s( address::repeat, min_filter::linear, mag_filter::linear );
    float4 t0 = texture0.sample( s, in.uv );
    float4 t1 = texture1.sample( s, in.uv );
    float3 c = t0.rgb + t1.rgb;
    c = ToneMapACES( c * exposure );
    return float4( c, 1.0f );
}

#endif
