//
//  ImageExtensions.swift
//  MyHybridRendering
//
//  Created by Caroline on 30/7/2025.
//

import Foundation
import CoreGraphics
import ImageIO
import MetalKit

extension String {
  func createCGImageFromFile() throws -> CGImage {
    let url = URL(fileURLWithPath: self)
    
    let options: [CFString: Any] = [
      kCGImageSourceShouldCache: false,
      kCGImageSourceShouldAllowFloat: true
    ]
    guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, options as CFDictionary) else {
      fatalError("Image source is NULL")
    }
    guard let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
      fatalError("Image not created from image source")
    }
    return image
  }
}

extension String {
  func textureFromRadianceFile(device: MTLDevice) throws -> MTLTexture {
    // Validate the function inputs
    guard self.contains(".") else {
      throw NSError(domain: "File load failure.",
                    code: 0xdeadbeef,
                    userInfo: [NSLocalizedDescriptionKey: "No file extension provided."])
    }
    
    let subStrings = self.components(separatedBy: ".")
    
    guard subStrings.count >= 2 && subStrings[1] == "hdr" else {
      throw NSError(domain: "File load failure.",
                    code: 0xdeadbeef,
                    userInfo: [NSLocalizedDescriptionKey: "Only (.hdr) files are supported."])
    }
    
    // Load and validate the image
    guard let loadedImage = try? self.createCGImageFromFile() else {
      throw NSError(domain: "File load failure.",
                    code: 0xdeadbeef,
                    userInfo: [NSLocalizedDescriptionKey: "Unable to create CGImage."])
    }
    
    let bpp = loadedImage.bitsPerPixel
    let alphaInfo = loadedImage.alphaInfo
    let srcChannelCount = (alphaInfo == .none) ? 3 : 4
    let bitsPerByte = 8
    let expectedBitsPerPixel = MemoryLayout<UInt16>.size * srcChannelCount * bitsPerByte
    
    guard bpp == expectedBitsPerPixel else {
      throw NSError(domain: "File load failure.",
                    code: 0xdeadbeef,
                    userInfo: [NSLocalizedDescriptionKey: "Expected \(expectedBitsPerPixel) bits per pixel, but file returns \(bpp)"])
    }
    
    // Copy the image into a temporary buffer
    let width = loadedImage.width
    let height = loadedImage.height
    
    // Make the CG image data accessible
    guard let dataProvider = loadedImage.dataProvider,
          let cgImageData = dataProvider.data else {
      throw NSError(domain: "File load failure.",
                    code: 0xdeadbeef,
                    userInfo: [NSLocalizedDescriptionKey: "Unable to get image data."])
    }
    
    guard let bytePtr = CFDataGetBytePtr(cgImageData) else {
      fatalError("Failed to get byte pointer from image data")
    }
    
    let rawPtr = UnsafeRawPointer(bytePtr)
    let srcData = rawPtr.assumingMemoryBound(to: UInt16.self)
    
    var paddedData: UnsafeMutablePointer<UInt16>? = nil
    let dstChannelCount = 4
    
    if srcChannelCount == 3 {
      // Pads the data with an extra channel because the source data is RGB16F,
      // but Metal exposes it as an RGBA16Float format.
      let pixelCount = width * height
      paddedData = UnsafeMutablePointer<UInt16>.allocate(capacity: pixelCount * dstChannelCount)
      
      for texIdx in 0..<pixelCount {
        let currSrc = srcData.advanced(by: texIdx * srcChannelCount)
        let currDst = paddedData!.advanced(by: texIdx * dstChannelCount)
        
        currDst[0] = currSrc[0]
        currDst[1] = currSrc[1]
        currDst[2] = currSrc[2]
        currDst[3] = float16FromFloat32(1.0)  // You'll need to implement this function
      }
    }
    
    // Create an MTLTexture
    let texDesc = MTLTextureDescriptor()
    texDesc.pixelFormat = .rgba16Float
    texDesc.width = width
    texDesc.height = height
    
    guard let texture = device.makeTexture(descriptor: texDesc) else {
      if let paddedData = paddedData {
        paddedData.deallocate()
      }
      throw NSError(domain: "File load failure.",
                    code: 0xdeadbeef,
                    userInfo: [NSLocalizedDescriptionKey: "Unable to create MTLTexture."])
    }
    
    let bytesPerRow = MemoryLayout<UInt16>.size * dstChannelCount * width
    let region = MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                           size: MTLSize(width: width, height: height, depth: 1))
    
    let dataToUse = paddedData.map { UnsafePointer($0) } ?? srcData
    texture.replace(region: region, mipmapLevel: 0, withBytes: dataToUse, bytesPerRow: bytesPerRow)
    
    // Clean up
    if let paddedData = paddedData {
      paddedData.deallocate()
    }
    
    return texture
  }
  
  // Helper function - you'll need to implement this
  func float16FromFloat32(_ value: Float) -> UInt16 {
    // Convert Float32 to Float16 representation
    // This is a simplified version - you might want to use proper IEEE 754 conversion
    let bits = value.bitPattern
    let sign = (bits >> 31) & 0x1
    let exponent = ((bits >> 23) & 0xFF) - 127 + 15
    let mantissa = (bits >> 13) & 0x3FF
    
    guard exponent > 0 && exponent < 31 else {
      return UInt16((sign << 15) | (exponent > 0 ? 0x7C00 : 0))
    }
    
    return UInt16((sign << 15) | (UInt32(exponent) << 10) | mantissa)
  }
}
