//
//  Mesh.swift
//  ArgumentBufferSample
//
//  Created by Caroline on 30/7/2025.
//

import MetalKit

class Mesh {
  let mtkMesh: MTKMesh
  let submeshes: [Submesh]
  
  /// Load the Model I/O Mesh, including vertex data and submesh data that have index buffers and textures.
  /// Also generate tangent and bitangent attributes.
  init(
    mdlMesh: MDLMesh,
    vertexDescriptor: MDLVertexDescriptor,
    textureLoader: MTKTextureLoader,
    device: MTLDevice) {
      mdlMesh.addNormals(withAttributeNamed: MDLVertexAttributeNormal, creaseThreshold: 0.98)
      
      // Have Model I/O create the tangents from the mesh texture coordinates and normals.
      mdlMesh.addTangentBasis(
        forTextureCoordinateAttributeNamed: MDLVertexAttributeTextureCoordinate,
        normalAttributeNamed: MDLVertexAttributeNormal,
        tangentAttributeNamed: MDLVertexAttributeTangent)
      
      // Have Model I/O create bitangents from the mesh texture coordinates and the newly created tangents.
      mdlMesh.addTangentBasis(
        forTextureCoordinateAttributeNamed: MDLVertexAttributeTextureCoordinate,
        tangentAttributeNamed: MDLVertexAttributeTangent,
        bitangentAttributeNamed: MDLVertexAttributeBitangent)
      
      // change the layout of the vertex data
      mdlMesh.vertexDescriptor = vertexDescriptor
      
      do {
        mtkMesh = try MTKMesh(mesh: mdlMesh, device: device)
      } catch {
        fatalError("Failed to create MTKMesh")
      }
      
      guard let mdlSubmeshes = mdlMesh.submeshes as? [MDLSubmesh] else {
        fatalError("No MDLSubmeshes found")
      }
      assert(mtkMesh.submeshes.count == mdlSubmeshes.count)
      submeshes = zip(mdlSubmeshes, Array(mtkMesh.submeshes)).map {
        Submesh(mdlSubmesh: $0.0, mtkSubmesh: $0.1, textureLoader: textureLoader)
      }
      
    }
  
  init(mtkMesh: MTKMesh) {
    self.mtkMesh = mtkMesh
    submeshes = []
  }
  
  init(mtkMesh: MTKMesh, submeshes: [Submesh]) {
    self.mtkMesh = mtkMesh
    self.submeshes = submeshes
  }
  
  /// Traverses the Model I/O object hierarchy that picks out Model I/O mesh objects and creates Metal
  /// vertex buffers, index buffers and textures
  static func newMeshesFrom(
    object: MDLObject,
    vertexDescriptor: MDLVertexDescriptor,
    textureLoader: MTKTextureLoader,
    device: MTLDevice
  ) -> [Mesh] {
    var newMeshes: [Mesh] = []
    
    func traverse(object: MDLObject) {
      if let mdlMesh = object as? MDLMesh {
        newMeshes.append(
          Mesh(
            mdlMesh: mdlMesh,
            vertexDescriptor: vertexDescriptor,
            textureLoader: textureLoader,
            device: device))
      }
      for index in 0..<object.children.count {
        traverse(object: object.children[index])
      }
    }
    traverse(object: object)
    return newMeshes
  }
  
  /// Uses Model I/O to load a model at the given URL, create Model I/O vertex buffers, index buffers
  /// and textures, applying the given Model I/O vertex descriptor to lay out vertex attribute data
  /// in the way that the Metal vertex shaders expect
  static func newMeshesFrom(
    url: URL,
    vertexDescriptor: MDLVertexDescriptor,
    device: MTLDevice
  ) -> [Mesh] {
    // Create a buffer allocator so that Model I/O loads mesh data directly into
    // Metal buffers accessible by the GPU
    let bufferAllocator = MTKMeshBufferAllocator(device: device)
    
    let asset = MDLAsset(
      url: url,
      vertexDescriptor: nil,
      bufferAllocator: bufferAllocator)
    
    let textureLoader = MTKTextureLoader(device: device)
    
    var newMeshes: [Mesh] = []
    
    for object in asset.childObjects(of: MDLObject.self) {
      let assetMeshes = Mesh.newMeshesFrom(
        object: object,
        vertexDescriptor: vertexDescriptor,
        textureLoader: textureLoader,
        device: device)
      newMeshes += assetMeshes
    }
    return newMeshes
  }
  
  static func newSkyboxMesh(
    device: MTLDevice,
    vertexDescriptor: MDLVertexDescriptor
  ) -> Mesh {
  let bufferAllocator = MTKMeshBufferAllocator(device: device)
    let mdlMesh = MDLMesh.newEllipsoid(
      withRadii: simd_float3(200, 200, 200),
      radialSegments: 10,
      verticalSegments: 10,
      geometryType: .triangles,
      inwardNormals: true,
      hemisphere: false,
      allocator: bufferAllocator)
    mdlMesh.vertexDescriptor = vertexDescriptor
    
    do {
      let mtkMesh = try MTKMesh(mesh: mdlMesh, device: device)
      return Mesh(mtkMesh: mtkMesh)
    } catch {
      fatalError("Failed to create mesh")
    }
  }
  
  static func new(
    mdlMesh: MDLMesh,
    material: MDLMaterial,
    device: MTLDevice,
    vertexDescriptor: MDLVertexDescriptor)
  -> Mesh {
    // layout vertex data
    mdlMesh.vertexDescriptor = vertexDescriptor
    let mtkMesh = try? MTKMesh(mesh: mdlMesh, device: device)
    guard let mtkMesh else {
      fatalError("Unable to create mesh")
    }
    
    let textureLoader = MTKTextureLoader(device: device)

    guard let mdlSubmeshes = mdlMesh.submeshes as? [MDLSubmesh] else {
      fatalError("No MDLSubmeshes found")
    }
    let submeshes = zip(mdlSubmeshes, Array(mtkMesh.submeshes)).map {
      $0.0.material = material
      return Submesh(mdlSubmesh: $0.0, mtkSubmesh: $0.1, textureLoader: textureLoader)
    }
    return Mesh(mtkMesh: mtkMesh, submeshes: submeshes)
  }
  
  static func newSphere(
    radius: Float,
    device: MTLDevice,
    vertexDescriptor: MDLVertexDescriptor)
  -> Mesh {
    let bufferAllocator = MTKMeshBufferAllocator(device: device)
    let mdlMesh = MDLMesh.newEllipsoid(
      withRadii: simd_float3(radius, radius, radius),
      radialSegments: 20,
      verticalSegments: 20,
      geometryType: .triangles,
      inwardNormals: false,
      hemisphere: false,
      allocator: bufferAllocator)
    
    mdlMesh.addTangentBasis(
      forTextureCoordinateAttributeNamed: MDLVertexAttributeTextureCoordinate,
      normalAttributeNamed: MDLVertexAttributeNormal,
      tangentAttributeNamed: MDLVertexAttributeTangent)
    
    mdlMesh.addTangentBasis(
      forTextureCoordinateAttributeNamed: MDLVertexAttributeTextureCoordinate,
      tangentAttributeNamed: MDLVertexAttributeTangent,
      bitangentAttributeNamed: MDLVertexAttributeBitangent)
    
    mdlMesh.vertexDescriptor = vertexDescriptor
    let material = MDLMaterial()
    material.setProperty(MDLMaterialProperty(
      name: "baseColor",
      semantic: .baseColor,
      string: "white"))
    material.setProperty(MDLMaterialProperty(
      name: "metallic",
      semantic: .metallic,
      string: "white"))
    material.setProperty(MDLMaterialProperty(
      name: "roughness",
      semantic: .roughness,
      string: "black"))
    material.setProperty(MDLMaterialProperty(
      name: "tangentNormal",
      semantic: .tangentSpaceNormal,
      string: "BodyNormalMap"))
    material.setProperty(MDLMaterialProperty(
      name: "ao",
      semantic: .ambientOcclusion,
      string: "white"))

    return Mesh.new(
      mdlMesh: mdlMesh,
      material: material,
      device: device,
      vertexDescriptor: vertexDescriptor)
  }
  
  static func newPlane(
    dimensions: simd_float2,
    device: MTLDevice,
    vertexDescriptor: MDLVertexDescriptor)
  -> Mesh {
    let bufferAllocator = MTKMeshBufferAllocator(device: device)
    let mdlMesh = MDLMesh.newPlane(
      withDimensions: dimensions,
      segments: simd_uint2(100, 100),
      geometryType: .triangles,
      allocator: bufferAllocator)
    
    mdlMesh.addTangentBasis(
      forTextureCoordinateAttributeNamed: MDLVertexAttributeTextureCoordinate,
      normalAttributeNamed: MDLVertexAttributeNormal,
      tangentAttributeNamed: MDLVertexAttributeTangent)
    
    mdlMesh.addTangentBasis(
      forTextureCoordinateAttributeNamed: MDLVertexAttributeTextureCoordinate,
      tangentAttributeNamed: MDLVertexAttributeTangent,
      bitangentAttributeNamed: MDLVertexAttributeBitangent)
    
    mdlMesh.vertexDescriptor = vertexDescriptor
    
    // repeat the floor texture 20 times over
    // this remaps the uv coordinates
    let kFloorRepeat: Float = 20.0
    guard let texcoords = mdlMesh.vertexAttributeData(forAttributeNamed: MDLVertexAttributeTextureCoordinate)
      else {
      fatalError("Mesh contains no texture coordinate data")
    }
    let map = texcoords.map
    let uv = map.bytes.assumingMemoryBound(to: simd_float2.self)
    let count = texcoords.bufferSize / MemoryLayout<simd_float2>.stride
    for index in 0..<count {
      uv[index].x *= kFloorRepeat
      uv[index].y *= kFloorRepeat
    }
    
    let material = MDLMaterial()
    material.setProperty(MDLMaterialProperty(
      name: "baseColor",
      semantic: .baseColor,
      string: "checkerboard_gray"))
    material.setProperty(MDLMaterialProperty(
      name: "metallic",
      semantic: .metallic,
      string: "white"))
    material.setProperty(MDLMaterialProperty(
      name: "roughness",
      semantic: .roughness,
      string: "black"))
    material.setProperty(MDLMaterialProperty(
      name: "tangentNormal",
      semantic: .tangentSpaceNormal,
      string: "BodyNormalMap"))
    material.setProperty(MDLMaterialProperty(
      name: "ao",
      semantic: .ambientOcclusion,
      string: "white"))

    return Mesh.new(
      mdlMesh: mdlMesh,
      material: material,
      device: device,
      vertexDescriptor: vertexDescriptor)
  }

}
