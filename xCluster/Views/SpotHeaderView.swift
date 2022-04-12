//
//  SpotHeaderView.swift
//  xCluster
//
//  Created by Peter Bourget on 4/11/22.
//

import SwiftUI

struct SpotHeader: View {
  var body: some View {

    VStack {
      HStack {
        Text("DX")
          .frame(minWidth: 75, maxWidth: 75, alignment: .center)
          .border(width: 1, edges: [.trailing], color: .gray)
        Text("Frequency")
        //.padding(.leading, 5)
          .frame(minWidth: 90, maxWidth: 90, alignment: .center)
          .border(width: 1, edges: [.trailing], color: .gray)
        Text("Spotter")
          .frame(minWidth: 75, maxWidth: 75, alignment: .center)
          .border(width: 1, edges: [.trailing], color: .gray)
        Text("Time")
          .frame(minWidth: 60, maxWidth: 60, alignment: .center)
          .border(width: 1, edges: [.trailing], color: .gray)
        Text("Comment")
        //.padding(.leading, 5)
          .frame(minWidth: 200, maxWidth: 220, alignment: .leading)
          .border(width: 1, edges: [.trailing], color: .gray)
        Text("Country")
          .frame(minWidth: 140, alignment: .center)
      }
      .border(Color.gray)
      .foregroundColor(Color.red)
      .font(.system(size: 14))
    }
    .frame(width: 700, height: 22)
  }
}

struct SpotHeaderView_Previews: PreviewProvider {
  static var previews: some View {
    SpotHeader()
  }
}
