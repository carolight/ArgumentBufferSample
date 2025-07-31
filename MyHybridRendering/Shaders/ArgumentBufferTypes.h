//
//  ArgumentBufferTypes.h
//  MyHybridRendering
//
//  Created by Caroline on 30/7/2025.
//

#ifndef ArgumentBufferTypes_h
#define ArgumentBufferTypes_h

typedef enum {
  BaseColorTexture = 0,
  MetallicTexture = 1,
  RoughnessTexture = 2,
  NormalTexture = 3,
  AOTexture = 4,
  IrradianceMap = 5,
  Reflections = 6,
  SkyDomeTexture = 7,
  MaterialTextureCount = AOTexture + 1
} TextureIndices;

typedef enum {
  ArgumentBufferIDGenericsTexcoord,
  ArgumentBufferIDGenericsNormal,
  ArgumentBufferIDGenericsTangent,
  ArgumentBufferIDGenericsBitangent,
  
  ArgumentBufferIDSubmeshIndices,
  ArgumentBufferIDSubmeshMaterials,
  
  ArgumentBufferIDMeshPositions,
  ArgumentBufferIDMeshGenerics,
  ArgumentBufferIDMeshSubmeshes,
  
  ArgumentBufferIDInstanceMesh,
  ArgumentBufferIDInstanceTransform,
  
  ArgumentBufferIDSceneInstances,
  ArgumentBufferIDSceneMeshes
} ArgumentBufferID;

#if __METAL_VERSION__
// MARK: - Metal Shading Language

#include <metal_stdlib>
using namespace metal;

struct MeshGenericsData
{
  float2 texcoord  [[id(ArgumentBufferIDGenericsTexcoord)]];
  half4  normal    [[id(ArgumentBufferIDGenericsNormal)]];
  half4  tangent   [[id(ArgumentBufferIDGenericsTangent)]];
  half4  bitangent [[id(ArgumentBufferIDGenericsBitangent)]];
};

struct SubmeshData
{
  // The container mesh stores positions and generic vertex attribute arrays.
  // The submesh stores only indices into these vertex arrays.
  uint32_t shortIndexType [[id(0)]];
  
  // The indices for the container mesh's position and generics arrays.
  constant uint32_t* indices   [[ id(ArgumentBufferIDSubmeshIndices)]];
  
  // The fixed size array of material textures.
  array<texture2d<float>, MaterialTextureCount> materials [[ id(ArgumentBufferIDSubmeshMaterials)]];
};

struct MeshData
{
  // The arrays of vertices.
  constant packed_float3* positions [[ id(ArgumentBufferIDMeshPositions ) ]];
  constant MeshGenericsData* generics   [[ id(ArgumentBufferIDMeshGenerics  ) ]];
  
  // The array of submeshes.
  uint64_t submeshes       [[ id(ArgumentBufferIDMeshSubmeshes ) ]];
};

struct InstanceData
{
  // A reference to a single mesh in the meshes array stored in structure `Scene`.
  uint32_t meshIndex [[id(0)]];
  
  // The location of the mesh for this instance.
  float4x4 transform [[id(1)]];
};

struct SceneData
{
  // The array of instances.
//  uint64_t instances [[ id(ArgumentBufferIDSceneInstances ) ]];
//  uint64_t meshes [[ id(ArgumentBufferIDSceneMeshes )]];
  constant InstanceData* instances [[ id(ArgumentBufferIDSceneInstances)]];
  constant MeshData* meshes [[ id(ArgumentBufferIDSceneMeshes)]];
};

#else

// MARK: - Swift side
#include <Metal/Metal.h>

struct SubmeshData
{
  // The container mesh stores positions and generic vertex attribute arrays.
  // The submesh stores only indices in these vertex arrays.
  uint32_t shortIndexType;
  
  // Indices for the container mesh's position and generics arrays.
  uint64_t indices;
  
  // The fixed size array of material textures.
//  MTLResourceID materials[MaterialTextureCount];
  MTLResourceID materials[5];
};

struct MeshData
{
  // The arrays of vertices.
  uint64_t positions;
  uint64_t generics;
  
  // The array of submeshes.
  uint64_t submeshes;
};

struct InstanceData
{
  // A reference to a single mesh.
  uint32_t meshIndex;
  
  // The location of the mesh for this instance.
  matrix_float4x4 transform;
};

struct SceneData
{
  // The array of instances.
  uint64_t instances;
  uint64_t meshes;
};

#endif

#endif /* ArgumentBufferTypes_h */
