//
//  CallFilterView.swift
//  xCluster
//
//  Created by Peter Bourget on 7/21/22.
//

import SwiftUI

struct CallFilterView: View {
  @State private var callSignToFilter = ""
  var controller: Controller
  let characterLimit = 10
  
    var body: some View {
      Divider()

      HStack {
      Image(systemName: "magnifyingglass")
      TextField("Call Filter", text: $callSignToFilter, onEditingChanged: { _ in
        // onEditingChanged
        callSignToFilter = callSignToFilter.uppercased()
        if callSignToFilter.count > characterLimit {
          callSignToFilter = String(callSignToFilter.prefix(characterLimit))
        }
      }) {
        // onCommit
        self.controller.callToFilter = callSignToFilter
      }
      .textFieldStyle(RoundedBorderTextFieldStyle())
      .modifier(ClearButton(boundText: $callSignToFilter))
      .frame(maxWidth: 150)
      }

      Divider()

      HStack {
        CheckBoxViewExact(controller: controller)
        Divider()
        CheckBoxViewFT8(controller: controller)
      }
      
      Divider()
    }
}

struct CallFilterView_Previews: PreviewProvider {
    static var previews: some View {
        CallFilterView(controller: Controller())
    }
}
