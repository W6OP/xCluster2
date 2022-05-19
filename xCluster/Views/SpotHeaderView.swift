//
//  SpotHeaderView.swift
//  xCluster
//
//  Created by Peter Bourget on 4/11/22.
//

import SwiftUI

struct SpotHeaderView: View {
  @Environment(\.colorScheme) var currentMode
  
  var body: some View {
      HStack {
        SpotHeaderDX()
        SpotHeaderFrequency()
        SpotHeaderSpotter()
        SpotHeaderTime()
        SpotHeaderComment()
        SpotHeaderCountry()
      }
      .foregroundColor(Color("SpotRowHeaderForeground"))
    Divider()
  }
}

struct SpotHeaderView_Previews: PreviewProvider {
  static var previews: some View {
    SpotHeaderView()
  }
}

/// Have to break out individual rows because you can't
/// have more than 10 child views in a parent view.
struct SpotHeaderDX: View {
  var body: some View {
    HStack {
    Text("DX")
      .frame(width: 90, alignment: .center)
    Divider()
    }
  }
}

struct SpotHeaderFrequency: View {
  var body: some View {
    HStack {
    Text("Freq")
      .frame(width: 60, alignment: .center)
    Divider()
    }
  }
}
struct SpotHeaderSpotter: View {
  var body: some View {
    HStack {
    Text("Spotter")
      .frame(width: 90, alignment: .center)
    Divider()
    }
  }
}

struct SpotHeaderTime: View {
  var body: some View {
    HStack {
    Text("Time")
      .frame(width: 40, alignment: .center)
    Divider()
    }
  }
}

struct SpotHeaderComment: View {
  var body: some View {
    HStack {
    Text("Comment")
      .frame(width: 200, alignment: .leading)
    Divider()
    }
  }
}

struct SpotHeaderCountry: View {
  var body: some View {
    HStack {
    Text("Country")
        .frame(minWidth:140, maxWidth: .infinity, alignment: .leading)
    }
  }
}
