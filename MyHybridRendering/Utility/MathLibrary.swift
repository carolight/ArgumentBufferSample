//
//  MathLibrary.swift
//  MyHybridRendering
//
//  Created by Caroline on 30/7/2025.
//

import simd

extension matrix_float4x4 {
  static var identity: float4x4 {
    matrix_identity_float4x4
  }

  init(projectionFov fov: Float, aspect: Float, nearZ: Float, farZ: Float) {
    let ys = 1 / tanf(fov * 0.5)
    let xs = ys / aspect
    let zs = farZ / (nearZ - farZ)
    self = matrix_float4x4(
        simd_float4(xs, 0, 0, 0),
        simd_float4(0, ys, 0, 0),
        simd_float4(0, 0, zs, -1),
        simd_float4(0, 0, nearZ * zs, 0)
    )
  }
  
  init(rotation radians: Float, axis: simd_float3) {
    let axis = normalize(axis)
    let ct = cosf(radians)
    let st = sinf(radians)
    let ci = 1 - ct
    let x = axis.x, y = axis.y, z = axis.z
    self = matrix_float4x4(rows: [
        simd_float4(ct + x * x * ci, x * y * ci - z * st, x * z * ci + y * st, 0),
        simd_float4(y * x * ci + z * st, ct + y * y * ci, y * z * ci - x * st, 0),
        simd_float4(z * x * ci - y * st, z * y * ci + x * st, ct + z * z * ci, 0),
        simd_float4(0, 0, 0, 1)
    ])
  }
  
  init(translation: simd_float3) {
    let t = translation
    self = matrix_float4x4(rows: [
        simd_float4(1, 0, 0, t.x),
        simd_float4(0, 1, 0, t.y),
        simd_float4(0, 0, 1, t.z),
        simd_float4(0, 0, 0, 1)
    ])
  }
}
