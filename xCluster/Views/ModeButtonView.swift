//
//  ModeButtonView.swift
//  xCluster
//
//  Created by Peter Bourget on 4/3/22.
//

import SwiftUI

// Mode filter buttons at top of display
//struct ModeViewToggle: View {
//  @ObservedObject var controller: Controller
//  @State var modes: [ModeIdentifier]
//
//  var body: some View {
//    HStack {
//      Spacer()
//      ForEach(modes.indices) { item in
//        Toggle(self.modes[item].mode.rawValue, isOn: self.$modes[item].isSelected.didSet { (state) in
//          if self.modes[item].id != 0 {
//            // Invert the state to reduce confusion. A button as false means isFiltered = true.
//            self.controller.modeFilter = (self.modes[item].id, !state)
//          } else {
//            for (index, mode) in modes.enumerated() where mode.id != 0 {
//              self.modes[index].isSelected = self.modes[0].isSelected
//            }
//            // Invert the state to reduce confusion. A button as false means isFiltered = true.
//            self.controller.modeFilter = (0, !state)
//          }
//        })
//        .tag(self.modes[item].id)
//        .padding(.top, 5)
//        .toggleStyle(SwitchToggleStyle(tint: .red))
//        Divider()
//      }
//      Spacer()
//    }
//    .frame(width: 300, alignment: .leading)
//    .border(.red)
//  }
//}

//struct ModeButtonView: View {
//    var body: some View {
//        Text(/*@START_MENU_TOKEN@*/"Hello, World!"/*@END_MENU_TOKEN@*/)
//    }
//}
//
//struct ModeButtonView_Previews: PreviewProvider {
//    static var previews: some View {
//        ModeButtonView()
//    }
//}
