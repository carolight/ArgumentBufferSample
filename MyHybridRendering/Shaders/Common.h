//
//  Common.h
//  MyHybridRendering
//
//  Created by Caroline on 30/7/2025.
//

#ifndef Common_h
#define Common_h

#import <simd/simd.h>
#import "ArgumentBufferTypes.h"

typedef enum {
  Position = 0,
  Normal = 1,
  UV = 2,
  Tangent = 3,
  Bitangent = 4,
} Attributes;

typedef enum {
  BufferIndexMeshPositions = 0,
  BufferIndexMeshGenerics = 1,
  BufferIndexInstanceTransforms   = 2,
  BufferIndexCameraData           = 3,
  BufferIndexLightData            = 4,
  BufferIndexSubmeshKeypath       = 5,
  BufferIndexScene                = 11
  
} BufferIndices;

typedef struct {
  matrix_float4x4 projectionMatrix;
  matrix_float4x4 viewMatrix;
  vector_float3 cameraPosition;
  float metallicBias;
  float roughnessBias;
} CameraData;

typedef struct {
  matrix_float4x4 modelViewMatrix;
} InstanceTransform;

typedef struct {
  // Per Light Properties
  vector_float3 directionalLightInvDirection;
  float lightIntensity;
} LightData;

typedef struct SubmeshKeypath
{
  uint32_t instanceID;
  uint32_t submeshID;
} SubmeshKeypath;

#endif /* Common_h */
