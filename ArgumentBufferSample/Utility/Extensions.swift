//
//  Extensions.swift
//  ArgumentBufferSample
//
//  Created by Caroline on 30/7/2025.
//

import Foundation

extension MemoryLayout {
  static func alignedSize(alignment: Int) -> Int {
    (Self.size + alignment - 1) & ~(alignment - 1)
  }
}

extension Array {
  func chunked(into size: Int) -> [[Element]] {
    stride(from: 0, to: count, by: size).map {
      Array(self[$0..<Swift.min($0 + size, count)])
    }
  }
}
