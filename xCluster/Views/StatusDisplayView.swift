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
    //HStack {
      ScrollView {
        VStack {
          ForEach(controller.statusMessage, id: \.self) { message in
            HStack {
              Text(message)
                .padding(.leading, 2)
                .foregroundColor(Color.black)
              Spacer()
            }
            .frame(maxHeight: 15)
            .multilineTextAlignment(.leading)
          }
        }
        //.background(Color(red: 209 / 255, green: 215 / 255, blue: 226 / 255))
      }
//    }
//    .frame(minHeight: 50, maxHeight: .infinity, alignment: .topLeading)
//    .border(Color.gray)
  }
}

struct StatusDisplayView_Previews: PreviewProvider {
    static var previews: some View {
        StatusDisplayView(controller: Controller())
    }
}
