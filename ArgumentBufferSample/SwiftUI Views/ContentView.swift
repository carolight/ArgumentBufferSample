//
//  ContentView.swift
//  ArgumentBufferSample
//
//  Created by Caroline on 30/7/2025.
//

import SwiftUI

struct ContentView: View {
  var body: some View {
    VStack {
      MetalView()
        .border(.black, width: 2.0)
    }
    .padding()
  }
}

#Preview {
  ContentView()
}
