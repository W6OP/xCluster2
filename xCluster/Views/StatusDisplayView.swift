//
//  StatusDisplayView.swift
//  xCluster
//
//  Created by Peter Bourget on 5/13/22.
//

import SwiftUI

// MARK: - Status message display.
struct StatusDisplayView: View {
  @ObservedObject var controller: Controller

  var body: some View {
    ScrollView {
      VStack {
        ForEach(controller.statusMessages, id: \.self) { status in
          HStack {
            Text(status.message)
              .padding(.leading, 2)
              .foregroundColor(Color.black)
            Spacer()
          }
          .frame(maxHeight: 15)
          .multilineTextAlignment(.leading)
        }
      }
    }
  }
}

struct StatusDisplayView_Previews: PreviewProvider {
  static var previews: some View {
    StatusDisplayView(controller: Controller())
  }
}
