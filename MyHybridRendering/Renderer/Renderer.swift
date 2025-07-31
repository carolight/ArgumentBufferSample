//
//  Renderer.swift
//  MyHybridRendering
//
//  Created by Caroline on 30/7/2025.
//

import MetalKit

let kMaxBuffersInFlight = 3
let kMaxModelInstances = 4
let alignedInstanceTransformSize = (MemoryLayout<InstanceTransform>.size & ~0xFF) + 0x100

struct ThinGBuffer {
  let positionTexture: MTLTexture
  let directionTexture: MTLTexture
}

class Renderer: NSObject {
  let device: MTLDevice
  let commandQueue: MTLCommandQueue

  // Components
  let mtlVertexDescriptor: MTLVertexDescriptor
  let mtlSkyboxVertexDescriptor: MTLVertexDescriptor
  let pipelineState: MTLRenderPipelineState
  let gBufferPipelineState: MTLRenderPipelineState
  let skyboxPipelineState: MTLRenderPipelineState
  let rtMipmapPipeline: MTLRenderPipelineState
  let bloomThresholdPipeline: MTLRenderPipelineState
  let postMergePipeline: MTLRenderPipelineState
  let depthState: MTLDepthStencilState
  let cameraDataBuffers: [MTLBuffer]
  let instanceTransformBuffer: MTLBuffer
  let lightDataBuffer: MTLBuffer
  
  var rawColorMap: MTLTexture?
  var bloomThresholdMap: MTLTexture?
  var bloomBlurMap: MTLTexture?

  var projectionMatrix: matrix_float4x4 = .identity
  let inFlightSemaphore = DispatchSemaphore(value: kMaxBuffersInFlight)
  var cameraBufferIndex = 0
  
  func projectionMatrix(aspect: Float) -> matrix_float4x4 {
    matrix_float4x4.init(projectionFov: 65 * (.pi / 180.0), aspect: aspect, nearZ: 0.1, farZ: 250)
  }
  var cameraAngle: Float = 0
  var cameraPanSpeedFactor: Float = 0
  var metallicBias: Float = 0
  var roughnessBias: Float = 0
  var exposure: Float = 0
  
  let modelInstances: [ModelInstance]
  
  var meshes: [Mesh] = []  // the entire scene
  var skybox: Mesh!
  var skyMap: MTLTexture!
  
  var thinGBuffer: ThinGBuffer?

  var sceneArgumentBuffer: MTLBuffer!
  var sceneResidencySet: MTLResidencySet!
  var sceneResources: [MTLResource] = []
  var sceneHeaps: [MTLHeap] = []
  
  var instanceArgumentBuffer: MTLBuffer!
  
  init(view: MTKView) {
    guard let device = MTLCreateSystemDefaultDevice(),
      let commandQueue = device.makeCommandQueue() else {
      fatalError("Metal is not available.")
    }
    self.device = device
    self.commandQueue = commandQueue
    view.depthStencilPixelFormat = .depth32Float_stencil8
    view.colorPixelFormat = .bgra8Unorm_srgb

    modelInstances = ModelInstance.configureModelInstances(count: kMaxModelInstances)

    let builder = RendererBuilder(device: device, view: view)
    let components = builder.build()
    mtlVertexDescriptor = components.mtlVertexDescriptor
    mtlSkyboxVertexDescriptor = components.mtlSkyboxVertexDescriptor
    pipelineState = components.pipelineState
    gBufferPipelineState = components.gBufferPipelineState
    skyboxPipelineState = components.skyboxPipelineState
    rtMipmapPipeline = components.rtMipmapPipeline
    bloomThresholdPipeline = components.bloomThresholdPipeline
    postMergePipeline = components.postMergePipeline
    depthState = components.depthState
    cameraDataBuffers = components.cameraDataBuffers
    instanceTransformBuffer = components.instanceTransformBuffer
    lightDataBuffer = components.lightDataBuffer
    
    
    super.init()


    // Initialize view
    initializeView(view: view)
    loadAssets()
  
    buildSceneArgumentsBuffer()
    buildSceneResidencySet()
    
    cameraPanSpeedFactor = 0.5
    metallicBias = 0.0
    roughnessBias = 0.0
    exposure = 1.0
    
    mtkView(view, drawableSizeWillChange: view.drawableSize)
    setStaticState()
  }
  
  func initializeView(view: MTKView) {
    view.device = device
    view.depthStencilPixelFormat = .depth32Float_stencil8
    view.colorPixelFormat = .bgra8Unorm_srgb
    view.clearColor = MTLClearColor(red: 0.65, green: 0.65, blue: 0.65, alpha: 1)
    view.preferredFramesPerSecond = 30
    view.delegate = self
  }
  
  func setStaticState() {
    // reset instances to original position
    for index in 0..<kMaxModelInstances {
      let transforms = instanceTransformBuffer.contents()
        .advanced(by: index * alignedInstanceTransformSize)
        .assumingMemoryBound(to: InstanceTransform.self)
      transforms.pointee.modelViewMatrix = calculateTransform(instance: modelInstances[index])
    }
    
    updateCameraState()
    
    let lightData = lightDataBuffer.contents()
      .assumingMemoryBound(to: LightData.self)
    lightData.pointee.directionalLightInvDirection = -normalize(simd_float3(0, -6, -6))
    lightData.pointee.lightIntensity = 5.0
  }
  
  func calculateTransform(instance: ModelInstance) -> matrix_float4x4 {
    let rotationAxis = simd_float3(0, 1, 0)
    let rotationMatrix = matrix_float4x4(rotation: instance.rotation, axis: rotationAxis)
    let translationMatrix = matrix_float4x4(translation: instance.position)
    return translationMatrix * rotationMatrix
  }
  
  func updateCameraState() {
    // Determine next safe slot
    cameraBufferIndex = (cameraBufferIndex + 1) % kMaxBuffersInFlight
    
    // Update projection matrix
    let cameraData = cameraDataBuffers[cameraBufferIndex].contents()
      .assumingMemoryBound(to: CameraData.self)
    cameraData.pointee.projectionMatrix = projectionMatrix
    
    // Update Camera Position (and View Matrix)
    let cameraPosition = simd_float3(cosf(cameraAngle) * 10.0, 5, sinf(cameraAngle) * 22.5)
    cameraAngle += 0.01 * cameraPanSpeedFactor
    if cameraAngle > 2 * .pi {
      cameraAngle -= 2 * .pi
    }
    
    cameraData.pointee.viewMatrix = matrix_float4x4(translation: -cameraPosition)
    cameraData.pointee.cameraPosition = cameraPosition
    cameraData.pointee.metallicBias = metallicBias
    cameraData.pointee.roughnessBias = roughnessBias
  }
  
  func loadAssets() {
    // Create a Model I/O vertexDescriptor to format the Model I/O mesh vertices to
    // fit the Metal render pipeline's vertex descriptor layout.
    let modelIOVertexDescriptor =
      MTKModelIOVertexDescriptorFromMetal(mtlVertexDescriptor)
    
    // Indicate the Metal vertex descriptor attribute mapping for each Model I/O attribute.
    (modelIOVertexDescriptor.attributes[Position.index] as? MDLVertexAttribute)?.name = MDLVertexAttributePosition
    (modelIOVertexDescriptor.attributes[UV.index] as? MDLVertexAttribute)?.name = MDLVertexAttributeTextureCoordinate
    (modelIOVertexDescriptor.attributes[Normal.index] as? MDLVertexAttribute)?.name = MDLVertexAttributeNormal
    (modelIOVertexDescriptor.attributes[Tangent.index] as? MDLVertexAttribute)?.name = MDLVertexAttributeTangent
    (modelIOVertexDescriptor.attributes[Bitangent.index] as? MDLVertexAttribute)?.name = MDLVertexAttributeBitangent

    guard let modelFileURL = Bundle.main.url(forResource: "firetruck", withExtension: "obj") else {
      fatalError("Firetruck model not found")
    }
    var scene: [Mesh] = Mesh.newMeshesFrom(
      url: modelFileURL,
      vertexDescriptor: modelIOVertexDescriptor,
      device: device)
    scene.append(Mesh.newSphere(
      radius: 8.0,
      device: device,
      vertexDescriptor: modelIOVertexDescriptor))
    scene.append(Mesh.newPlane(
      dimensions: simd_float2(200.0, 200.0),
      device: device,
      vertexDescriptor: modelIOVertexDescriptor))
    
    meshes = scene
            
    do {
      skyMap = try "kloppenheim_06_4k.hdr".textureFromRadianceFile(device: device)
    } catch {
      fatalError("Unable to load sky texture")
    }
    
    let skyboxModelIOVertexDescriptor = MTKModelIOVertexDescriptorFromMetal(mtlSkyboxVertexDescriptor)
    (skyboxModelIOVertexDescriptor.attributes[Position.index]
     as? MDLVertexAttribute)?.name = MDLVertexAttributePosition
    (skyboxModelIOVertexDescriptor.attributes[UV.index]
     as? MDLVertexAttribute)?.name = MDLVertexAttributeTextureCoordinate

    skybox = Mesh.newSkyboxMesh(device: device, vertexDescriptor: skyboxModelIOVertexDescriptor)
  }
  
  func buildSceneArgumentsBuffer() {
    let instanceArgumentSize = MemoryLayout<InstanceData>.stride * kMaxModelInstances
    instanceArgumentBuffer = newBuffer(
      label: "instanceArgumentBuffer",
      length: instanceArgumentSize,
      options: .storageModeShared)
    
    // encode the instances array in `SceneData`
    var instancePtr = instanceArgumentBuffer.contents()
      .assumingMemoryBound(to: InstanceData.self)
    for index in 0..<kMaxModelInstances {
      instancePtr.pointee.meshIndex = UInt32(modelInstances[index].meshIndex)
      instancePtr.pointee.transform = calculateTransform(instance: modelInstances[index])
      instancePtr = instancePtr.successor()
    }
    
    let meshArgumentSize = MemoryLayout<MeshData>.stride * meshes.count
    let meshArgumentbuffer = newBuffer(
      label: "meshArgumentBuffer",
      length: meshArgumentSize,
      options: .storageModeShared)
    
    let meshPtr = meshArgumentbuffer.contents()
      .assumingMemoryBound(to: MeshData.self)
    for index in 0..<meshes.count {
      let mesh = meshes[index]
      let mtkMesh = mesh.mtkMesh
      
      // set positions
      var offset = UInt64(mtkMesh.vertexBuffers[0].offset)
      meshPtr.pointee.positions = mtkMesh.vertexBuffers[0].buffer.gpuAddress + offset
      
      // set generics
      offset = UInt64(mtkMesh.vertexBuffers[1].offset)
      meshPtr.pointee.generics = mtkMesh.vertexBuffers[1].buffer.gpuAddress + offset
      
      assert(mtkMesh.vertexBuffers.count == 2, "Mesh should have 2 vertex buffers")
      
      sceneResources.append(mtkMesh.vertexBuffers[0].buffer)
      sceneResources.append(mtkMesh.vertexBuffers[1].buffer)
      
      // build submeshes into a buffer and reference it through a pointer in the mesh
      
      let submeshArgumentSize = MemoryLayout<SubmeshData>.stride * mesh.submeshes.count
      let submeshArgumentBuffer = newBuffer(
        label: "submeshArgumentBuffer",
        length: submeshArgumentSize,
        options: .storageModeShared)
      
      var submeshPtr = submeshArgumentBuffer.contents()
        .assumingMemoryBound(to: SubmeshData.self)
      for submesh in mesh.submeshes {
        // set submesh indices
        let indexBuffer = submesh.mtkSubmesh.indexBuffer
        submeshPtr.pointee.shortIndexType = submesh.mtkSubmesh.indexType == .uint32 ? 0 : 1
        offset = UInt64(indexBuffer.offset)
        submeshPtr.pointee.indices = indexBuffer.buffer.gpuAddress + offset
        
        for (index, texture) in submesh.textures.enumerated() {
          // SubmeshData.textures is a tuple
          withUnsafeMutableBytes(of: &submeshPtr.pointee.materials) { bytes in
            bytes.bindMemory(to: MTLResourceID.self)[index] = texture.gpuResourceID
          }
        }
        
        let submeshIndexBuffer = submesh.mtkSubmesh.indexBuffer.buffer
        sceneResources.append(submeshIndexBuffer)
        sceneResources += submesh.textures
        submeshPtr = submeshPtr.successor()
      }
      
      meshPtr.pointee.submeshes = submeshArgumentBuffer.gpuAddress
    }
    sceneResources.append(meshArgumentbuffer)
    
    let sceneArgumentBuffer = newBuffer(
        label: "sceneArgumentBuffer",
        length: MemoryLayout<SceneData>.stride,
        options: .storageModeShared)
    
    let scenePtr = sceneArgumentBuffer.contents()
      .assumingMemoryBound(to: SceneData.self)
    scenePtr.pointee.instances = instanceArgumentBuffer.gpuAddress
    scenePtr.pointee.meshes = meshArgumentbuffer.gpuAddress
    
    self.sceneArgumentBuffer = sceneArgumentBuffer
  }
  
  func buildSceneResidencySet() {
    let sceneResidencySet = newResidencySet(label: "sceneResidencySet")
    // add the data to the residency set
    for chunk in sceneResources.chunked(into: 16) {
      sceneResidencySet.addAllocations(chunk)
    }
    for chunk in sceneHeaps.chunked(into: 16) {
      sceneResidencySet.addAllocations(chunk)
    }
    sceneResidencySet.commit()
    sceneResidencySet.requestResidency()
    commandQueue.addResidencySet(sceneResidencySet)
    self.sceneResidencySet = sceneResidencySet
  }
  
  func newBuffer(label: String, length: Int, options: MTLResourceOptions) -> MTLBuffer {
    guard let buffer = device.makeBuffer(length: length, options: options) else {
      fatalError("Failed to make new buffer: \(label)")
    }
    buffer.label = label
    sceneResources.append(buffer)
    return buffer
  }
  
  func newResidencySet(label: String) -> MTLResidencySet {
    let residencySetDescriptor = MTLResidencySetDescriptor()
    residencySetDescriptor.label = label
    do {
      let residencySet = try device.makeResidencySet(descriptor: residencySetDescriptor)
      return residencySet
    } catch {
      fatalError("Could not create residency set")
    }
  }
}

extension Renderer: MTKViewDelegate {
  func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
    projectionMatrix = projectionMatrix(aspect: Float(size.width / size.height))
    
    guard size != .zero else { return }
    let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .rg11b10Float,
      width: Int(size.width),
      height: Int(size.height),
      mipmapped: true)
    textureDescriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
    textureDescriptor.mipmapLevelCount = 1
    rawColorMap = device.makeTexture(descriptor: textureDescriptor)
    bloomThresholdMap = device.makeTexture(descriptor: textureDescriptor)
    bloomBlurMap = device.makeTexture(descriptor: textureDescriptor)
    
    textureDescriptor.pixelFormat = .rgba16Float
    textureDescriptor.usage = [.shaderRead, .renderTarget]
    textureDescriptor.mipmapLevelCount = 1
    
    let positionTexture = device.makeTexture(descriptor: textureDescriptor)!
    let directionTexture = device.makeTexture(descriptor: textureDescriptor)!
    thinGBuffer = ThinGBuffer(
      positionTexture: positionTexture,
      directionTexture: directionTexture)
  }
  
  func encodeSceneRendering(_ renderEncoder: MTLRenderCommandEncoder) {
    for index in 0..<kMaxModelInstances {
      let mesh = meshes[modelInstances[index].meshIndex]
      let mtkMesh = mesh.mtkMesh
      
      // set the mesh's vertex buffers
      for bufferIndex in 0..<mtkMesh.vertexBuffers.count {
        let vertexBuffer = mtkMesh.vertexBuffers[bufferIndex]
          renderEncoder.setVertexBuffer(
            vertexBuffer.buffer,
            offset: vertexBuffer.offset,
            index: bufferIndex)
      }
      
      // draw each submesh of the mesh
      for submeshIndex in 0..<mtkMesh.submeshes.count {
        let submesh = mesh.submeshes[submeshIndex]
        
        // Access textures directly from the argument buffer and avoid rebinding
        // them individually
        // `SubmeshKeypath` provides the path to the argument buffer containing
        // the texture data for this submesh. The shader navigates the scene
        // argument buffer using this key to find the textures
        
        var submeshKeypath = SubmeshKeypath(
          instanceID: UInt32(index),
          submeshID: UInt32(submeshIndex))
        let mtkSubmesh = submesh.mtkSubmesh
        renderEncoder.setVertexBuffer(
          instanceTransformBuffer,
          offset: alignedInstanceTransformSize,
          index: BufferIndexInstanceTransforms.index)
        renderEncoder.setVertexBuffer(
          cameraDataBuffers[cameraBufferIndex],
          offset: 0,
          index: BufferIndexCameraData.index)
        renderEncoder.setFragmentBuffer(
          cameraDataBuffers[cameraBufferIndex],
          offset: 0,
          index: BufferIndexCameraData.index)
        renderEncoder.setFragmentBuffer(
          lightDataBuffer,
          offset: 0,
          index: BufferIndexLightData.index)
        
        // Bind the scene and provide the keypath to retrieve this submesh's data
        renderEncoder.setFragmentBuffer(
          sceneArgumentBuffer,
          offset: 0,
          index: Int(SceneIndex.rawValue))
        renderEncoder.setFragmentBytes(
          &submeshKeypath,
          length: MemoryLayout<SubmeshKeypath>.stride,
          index: BufferIndexSubmeshKeypath.index)
        
        renderEncoder.drawIndexedPrimitives(
          type: mtkSubmesh.primitiveType,
          indexCount: mtkSubmesh.indexCount,
          indexType: mtkSubmesh.indexType,
          indexBuffer: mtkSubmesh.indexBuffer.buffer,
          indexBufferOffset: mtkSubmesh.indexBuffer.offset)
      }
    }
  }
  
  func draw(in view: MTKView) {
    inFlightSemaphore.wait()
    
    guard let commandBuffer = commandQueue.makeCommandBuffer(),
    let renderPassDescriptor = view.currentRenderPassDescriptor,
    let drawableTexture = renderPassDescriptor.colorAttachments[0].texture
      else { return }
    commandBuffer.label = "Render Commands"
    commandBuffer.addCompletedHandler { _ in
      self.inFlightSemaphore.signal()
    }
    
    updateCameraState()
    
    // Encode the forward pass
    renderPassDescriptor.colorAttachments[0].texture = rawColorMap
    
    commandBuffer.pushDebugGroup("Forward Scene Render")
//    commandBuffer.useResidencySet(sceneResidencySet)
    
    guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { return }
    renderEncoder.label = "ForwardPassRenderEncoder"
    renderEncoder.setRenderPipelineState(pipelineState)
    renderEncoder.setCullMode(.front)
    renderEncoder.setFrontFacing(.clockwise)
    renderEncoder.setDepthStencilState(depthState)
    renderEncoder.setFragmentTexture(skyMap, index: SkyDomeTexture.index)
    
    encodeSceneRendering(renderEncoder)
    
    // encode the skybox rendering
    
    renderEncoder.setCullMode(.back)
    renderEncoder.setRenderPipelineState(skyboxPipelineState)
    
    renderEncoder.setVertexBuffer(
      cameraDataBuffers[cameraBufferIndex],
      offset: 0,
      index: BufferIndexCameraData.index)
    
    renderEncoder.setFragmentTexture(skyMap, index: 0)
  
    let mtkMesh = skybox.mtkMesh
    for bufferindex in 0..<mtkMesh.vertexBuffers.count {
      let vertexBuffer = mtkMesh.vertexBuffers[bufferindex]
      renderEncoder.setVertexBuffer(
        vertexBuffer.buffer,
        offset: vertexBuffer.offset,
        index: bufferindex)
    }
    
    for submesh in mtkMesh.submeshes {
      renderEncoder.drawIndexedPrimitives(
        type: submesh.primitiveType,
        indexCount: submesh.indexCount,
        indexType: submesh.indexType,
        indexBuffer: submesh.indexBuffer.buffer,
        indexBufferOffset: submesh.indexBuffer.offset)
    }
    renderEncoder.endEncoding()
    commandBuffer.popDebugGroup()
   
    if let drawable = view.currentDrawable {
      commandBuffer.present(drawable)
    }
    commandBuffer.commit()
    
    
    
    
    
    
  
  }
  
  
}
