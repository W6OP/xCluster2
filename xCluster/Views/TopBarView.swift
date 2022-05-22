//
//  TopBarView.swift
//  xCluster
//
//  Created by Peter Bourget on 4/3/22.
//

import SwiftUI

struct TopBarView: View {
  @Environment(\.openURL) var openURL
  @State private var showPreferences = false

  var controller: Controller
  var bands: [BandIdentifier] = bandData
  var clusters: [ClusterIdentifier] = clusterData

  var body: some View {
    HStack {
      HStack {
        Button("Open Viewer") {
          if let url = URL(string: "xCluster://ClusterDisplayView") {
            openURL(url)
          }
        }
        .padding(.top, 5)
        .padding(.leading, 5)

        Divider()

        Button(action: {self.showPreferences.toggle()}) {
          Text("Settings")
        }
        .padding(.top, 4)
        .padding(.leading, 4)
        .sheet(isPresented: $showPreferences) {
          return PreferencesView()
        }
      }

      Divider()

      // MARK: - Band buttons
      ButtonBarView(controller: controller, clusters: clusters, bands: bands)
    }
    .padding(.top, -2).padding(.bottom, 2)
    .frame(maxWidth: .infinity, minHeight: 30, maxHeight: 30)
    .background(Color("TopRowBackground"))
    .opacity(0.70)
  }
}

struct TopBarView_Previews: PreviewProvider {
    static var previews: some View {
      TopBarView(controller: Controller())
    }
}
