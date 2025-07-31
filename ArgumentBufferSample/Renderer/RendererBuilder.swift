//
//  RendererBuilder.swift
//  ArgumentBufferSample
//
//  Created by Caroline on 30/7/2025.
//

import MetalKit

struct RendererComponents {
  let mtlVertexDescriptor: MTLVertexDescriptor
  let mtlSkyboxVertexDescriptor: MTLVertexDescriptor
  let pipelineState: MTLRenderPipelineState
  let skyboxPipelineState: MTLRenderPipelineState
  let depthState: MTLDepthStencilState
  let cameraDataBuffers: [MTLBuffer]
  let instanceTransformBuffer: MTLBuffer
  let lightDataBuffer: MTLBuffer
}

class RendererBuilder {
  let device: MTLDevice
  let view: MTKView
  
  init(device: MTLDevice, view: MTKView) {
    self.device = device
    self.view = view
  }
  
  func build() -> RendererComponents {
    guard let library = device.makeDefaultLibrary() else {
      fatalError("Failed to create default library.")
    }
    let mtlVertexDescriptor = build_mtlVertexDescriptor()
    let mtlSkyboxVertexDescriptor = build_mtlSkyboxVertexDescriptor()
    let (pipelineState, skyboxPipelineState) =
    build_pipelineStates(
      library: library,
      mtlVertexDescriptor: mtlVertexDescriptor,
      mtlSkyboxVertexDescriptor: mtlSkyboxVertexDescriptor)
    let depthState = build_depthStencilState()
    let cameraDataBuffers = build_cameraDataBuffers()
    let instanceTransformBuffer = build_instanceTransformBuffer()
    let lightDataBuffer = build_lightDataBuffer()
    
    return RendererComponents(
      mtlVertexDescriptor: mtlVertexDescriptor,
      mtlSkyboxVertexDescriptor: mtlSkyboxVertexDescriptor,
      pipelineState: pipelineState,
      skyboxPipelineState: skyboxPipelineState,
      depthState: depthState,
      cameraDataBuffers: cameraDataBuffers,
      instanceTransformBuffer: instanceTransformBuffer,
      lightDataBuffer: lightDataBuffer)
  }
  
  func build_mtlVertexDescriptor() -> MTLVertexDescriptor {
    let vertexDescriptor = MTLVertexDescriptor()
    // Positions
    vertexDescriptor.attributes[Position.index].format = .float3
    vertexDescriptor.attributes[Position.index].offset = 0
    vertexDescriptor.attributes[Position.index].bufferIndex = BufferIndexMeshPositions.index
    
    // Texture Coordinates
    vertexDescriptor.attributes[UV.index].format = .float2
    vertexDescriptor.attributes[UV.index].offset = 0
    vertexDescriptor.attributes[UV.index].bufferIndex = BufferIndexMeshGenerics.index
    
    // Normals
    vertexDescriptor.attributes[Normal.index].format = .half4
    vertexDescriptor.attributes[Normal.index].offset = 8
    vertexDescriptor.attributes[Normal.index].bufferIndex = BufferIndexMeshGenerics.index
    
    // Tangents
    vertexDescriptor.attributes[Tangent.index].format = .half4
    vertexDescriptor.attributes[Tangent.index].offset = 16
    vertexDescriptor.attributes[Tangent.index].bufferIndex = BufferIndexMeshGenerics.index
    
    // Bitangents
    vertexDescriptor.attributes[Bitangent.index].format = .half4
    vertexDescriptor.attributes[Bitangent.index].offset = 25
    vertexDescriptor.attributes[Bitangent.index].bufferIndex = BufferIndexMeshGenerics.index
    
    // Position Buffer Layout
    vertexDescriptor.layouts[BufferIndexMeshPositions.index].stride = 12
    vertexDescriptor.layouts[BufferIndexMeshPositions.index].stepRate = 1
    vertexDescriptor.layouts[BufferIndexMeshPositions.index].stepFunction = .perVertex
    
    // Generaic Buffer Layout
    vertexDescriptor.layouts[BufferIndexMeshGenerics.index].stride = 32
    vertexDescriptor.layouts[BufferIndexMeshGenerics.index].stepRate = 1
    vertexDescriptor.layouts[BufferIndexMeshGenerics.index].stepFunction = .perVertex
    
    return vertexDescriptor
  }
  
  func build_mtlSkyboxVertexDescriptor() -> MTLVertexDescriptor {
    let vertexDescriptor = MTLVertexDescriptor()
    // Positions
    vertexDescriptor.attributes[Position.index].format = .float3
    vertexDescriptor.attributes[Position.index].offset = 0
    vertexDescriptor.attributes[Position.index].bufferIndex = BufferIndexMeshPositions.index
    
    // Texture Coordinates
    vertexDescriptor.attributes[UV.index].format = .float2
    vertexDescriptor.attributes[UV.index].offset = 0
    vertexDescriptor.attributes[UV.index].bufferIndex = BufferIndexMeshGenerics.index
    
    // Position Buffer Layout
    vertexDescriptor.layouts[BufferIndexMeshPositions.index].stride = 12
    vertexDescriptor.layouts[BufferIndexMeshPositions.index].stepRate = 1
    vertexDescriptor.layouts[BufferIndexMeshPositions.index].stepFunction = .perVertex
    
    // Generaic Buffer Layout
    vertexDescriptor.layouts[BufferIndexMeshGenerics.index].stride = MemoryLayout<simd_float2>.stride
    vertexDescriptor.layouts[BufferIndexMeshGenerics.index].stepRate = 1
    vertexDescriptor.layouts[BufferIndexMeshGenerics.index].stepFunction = .perVertex
    
    return vertexDescriptor
  }
  
  func build_pipelineStates(
    library: MTLLibrary,
    mtlVertexDescriptor: MTLVertexDescriptor,
    mtlSkyboxVertexDescriptor: MTLVertexDescriptor
  ) ->
  (pipelineState: MTLRenderPipelineState,
   skyboxPipelineState: MTLRenderPipelineState) {
    let pipelineState: MTLRenderPipelineState
    let skyboxPipelineState: MTLRenderPipelineState
    
    // PipelineState
    guard let vertexFunction = library.makeFunction(name: "vertexShader"),
          let fragmentFunction = library.makeFunction(name: "fragmentShader") else {
      fatalError("Could not load shader functions from library.")
    }
    let pipelineStateDescriptor = MTLRenderPipelineDescriptor()
    pipelineStateDescriptor.label = "No RT Pipeline"
    pipelineStateDescriptor.rasterSampleCount = view.sampleCount
    pipelineStateDescriptor.vertexFunction = vertexFunction
    pipelineStateDescriptor.fragmentFunction = fragmentFunction
    pipelineStateDescriptor.vertexDescriptor = mtlVertexDescriptor
    pipelineStateDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
    pipelineStateDescriptor.depthAttachmentPixelFormat = view.depthStencilPixelFormat
    pipelineStateDescriptor.stencilAttachmentPixelFormat = view.depthStencilPixelFormat
    
    do {
      pipelineState = try device.makeRenderPipelineState(descriptor: pipelineStateDescriptor)
    } catch {
      fatalError("Pipeline State not created")
    }
    
    // skyboxPipelineState
    guard let vertexFunction = library.makeFunction(name: "skyboxVertex"),
          let fragmentFunction = library.makeFunction(name: "skyboxFragment") else {
      fatalError("Could not load shader functions from library.")
    }
    pipelineStateDescriptor.label = "SkyboxPipeline"
    pipelineStateDescriptor.vertexDescriptor = mtlSkyboxVertexDescriptor
    pipelineStateDescriptor.vertexFunction = vertexFunction
    pipelineStateDescriptor.fragmentFunction = fragmentFunction
    pipelineStateDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat

    pipelineStateDescriptor.colorAttachments[1].pixelFormat = .invalid
    
    do {
      skyboxPipelineState = try device.makeRenderPipelineState(descriptor: pipelineStateDescriptor)
    } catch {
      fatalError("Skybox Pipeline State not created")
    }
    return (pipelineState, skyboxPipelineState)
  }
  
 
  func build_depthStencilState() -> MTLDepthStencilState {
    let depthDescriptor = MTLDepthStencilDescriptor()
    depthDescriptor.depthCompareFunction = .less
    depthDescriptor.isDepthWriteEnabled = true
    let depthState = device.makeDepthStencilState(descriptor: depthDescriptor)!
    return depthState
  }
  
  func build_cameraDataBuffers() -> [MTLBuffer] {
    guard let buffer = device.makeBuffer(
      length: MemoryLayout<CameraData>.stride, options: .storageModeShared) else {
      fatalError("Failed to create camera data buffer")
    }
    let buffers = [MTLBuffer](repeating: buffer, count: kMaxBuffersInFlight)
    for (index, buffer) in buffers.enumerated() {
      buffer.label = "CameraDataBuffer \(index)"
    }
    return buffers
  }
  
  func build_instanceTransformBuffer() -> MTLBuffer {
    let instanceBufferSize = kMaxModelInstances * alignedInstanceTransformSize
    guard let instanceTransformBuffer = device.makeBuffer(
      length: instanceBufferSize,
      options: .storageModeShared) else {
      fatalError("Failed to create instance transform buffer")
    }
    instanceTransformBuffer.label = "InstanceTransformBuffer"
    return instanceTransformBuffer
  }
  
  func build_lightDataBuffer() -> MTLBuffer {
    guard let buffer = device.makeBuffer(length: MemoryLayout<LightData>.stride, options: .storageModeShared) else {
      fatalError("Failed to create light data buffer")
    }
    buffer.label = "LightDataBuffer"
    return buffer
  }
}
