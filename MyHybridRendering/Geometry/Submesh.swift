//
//  Submesh.swift
//  MyHybridRendering
//
//  Created by Caroline on 30/7/2025.
//

import MetalKit

class Submesh {
  let mtkSubmesh: MTKSubmesh
  let textures: [MTLTexture]
  
  static func createMetalTexture(
    material: MDLMaterial,
    materialSemantic: MDLMaterialSemantic,
    defaultPropertyType: MDLMaterialPropertyType,
    textureLoader: MTKTextureLoader) -> MTLTexture {
      var texture: MTLTexture?
      let propertiesWithSemantic = material.properties(with: materialSemantic)
      for property in propertiesWithSemantic {
        assert(property.semantic == materialSemantic)
        
        if property.type != .string {
          continue
        }
        
        // load textures with TextureUsageShaderRead and StorageModePrivate
        let options: [MTKTextureLoader.Option : Any] = [
          .textureUsage: MTLTextureUsage.shaderRead.rawValue,
          .textureStorageMode: MTLStorageMode.private.rawValue
        ]
        
        // interpret the string as a file path and attempt to load it
        if let url = property.urlValue,
           let stringValue = property.stringValue {
          var URLString: String
          if property.type == .URL {
            URLString = url.absoluteString
          } else {
            URLString = "file://" + stringValue
          }
          
          guard let textureURL = URL(string: URLString) else {
            fatalError()
          }
          texture = try? textureLoader.newTexture(URL: textureURL, options: options)
          if let texture {
            return texture
          }
        }

        // if the texture loader doesn't find a texture by interpreting
        // the URL as a path, interpret the string as an asset catalog
        // name and attempt to load it
        
        let lastComponent = String(property.stringValue?.split(separator: "/").last ?? "")
        texture = try? textureLoader.newTexture(name: lastComponent, scaleFactor: 1.0, bundle: Bundle.main, options: options)
        if let texture {
          return texture
        }
        // the texture is missing
        fatalError("Texture for semantic \(materialSemantic) string: \(property.stringValue ?? "") not found")
      }
      print(MDLMaterialSemantic.baseColor.rawValue)
      fatalError("No material property found for \(materialSemantic)")
    }
  
  init(
    mdlSubmesh: MDLSubmesh,
    mtkSubmesh: MTKSubmesh,
    textureLoader: MTKTextureLoader) {
      self.mtkSubmesh = mtkSubmesh
      guard let material = mdlSubmesh.material else {
        fatalError("Submesh doesn't have a material")
      }
      let baseColorTexture = Self.createMetalTexture(
        material:material,
        materialSemantic: .baseColor,
        defaultPropertyType: .float3,
        textureLoader: textureLoader)
      let metallicTexture = Self.createMetalTexture(
        material:material,
        materialSemantic: .metallic,
        defaultPropertyType: .float3,
        textureLoader: textureLoader)
      let roughnessTexture = Self.createMetalTexture(
        material: material,
        materialSemantic: .roughness,
        defaultPropertyType: .float3,
        textureLoader: textureLoader)
      let normalTexture = Self.createMetalTexture(
        material: material,
        materialSemantic: .tangentSpaceNormal,
        defaultPropertyType: .none,
        textureLoader: textureLoader)
      let aoTexture = Self.createMetalTexture(
        material: material,
        materialSemantic: .ambientOcclusion,
        defaultPropertyType: .none,
        textureLoader: textureLoader)
    
      textures = [baseColorTexture, metallicTexture, roughnessTexture, normalTexture, aoTexture]
    }
}
