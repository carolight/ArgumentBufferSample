//
//  Configuration.swift
//  ArgumentBufferSample
//
//  Created by Caroline on 30/7/2025.
//

import Foundation

extension Attributes {
  var index: Int {
    return Int(self.rawValue)
  }
}

extension BufferIndices {
  var index: Int {
    return Int(self.rawValue)
  }
}

extension TextureIndices {
  var index: Int {
    return Int(self.rawValue)
  }
}
