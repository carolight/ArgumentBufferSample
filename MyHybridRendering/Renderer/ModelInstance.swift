//
//  ModelInstance.swift
//  MyHybridRendering
//
//  Created by Caroline on 30/7/2025.
//

import simd

struct ModelInstance {
  var meshIndex: Int
  var position: simd_float3
  var rotation: Float
  
  static func configureModelInstances(count: Int) -> [ModelInstance] {
    let modelInstances: [ModelInstance] = [
      ModelInstance(
        meshIndex: 0,
        position: [20, -5, -40],
        rotation: 135 * .pi / 180),
      ModelInstance(
        meshIndex: 0,
        position: [-13, -5, -20],
        rotation: 235 * .pi / 180),
      ModelInstance(
        meshIndex: 1,
        position: [-5, 2.75, -55],
        rotation: 0),
      ModelInstance(
        meshIndex: 2,
        position: [0, -5, 0],
        rotation: 0)
    ]
    return Array(modelInstances.prefix(count))
  }
}
