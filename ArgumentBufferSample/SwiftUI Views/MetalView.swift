//
//  MetalView.swift
//  ArgumentBufferSample
//
//  Created by Caroline on 30/7/2025.
//

import SwiftUI
import MetalKit

#if os(macOS)
typealias ViewRepresentable = NSViewRepresentable
#elseif os(iOS)
typealias ViewRepresentable = UIViewRepresentable
#endif

struct MetalView: ViewRepresentable {
  let view = MTKView()

  func makeCoordinator() -> Renderer {
    let renderer = Renderer(view: view)
    return renderer
  }

#if os(macOS)
  func makeNSView(context: Context) -> some NSView {
    makeMetalView()
  }
  func updateNSView(_ uiView: NSViewType, context: Context) {
    updateMetalView()
  }
#elseif os(iOS)
  func makeUIView(context: Context) -> MTKView {
    makeMetalView()
  }

  func updateUIView(_ uiView: MTKView, context: Context) {
    updateMetalView()
  }
#endif

  func makeMetalView() -> MTKView {
    view
  }

  func updateMetalView() {
  }
}

#Preview {
  VStack {
    MetalView()
      .border(.black, width: 2.0)
      .padding()
  }
}
