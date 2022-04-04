//
//  ContentView.swift
//  xCluster
//
//  Created by Peter Bourget on 3/13/21.
//

import SwiftUI
import CallParser
import MapKit
import Combine

// MARK: - Content View

/// Main entry point
struct ContentView: View {
  @Environment(\.colorScheme) var currentMode
  @EnvironmentObject var controller: Controller

  var bands: [BandIdentifier] = bandData
  var clusters: [ClusterIdentifier] = clusterData

  // -------------------
  @State private var coordinateRegion = MKCoordinateRegion(
    center: CLLocationCoordinate2D(
      latitude: 25.7617,
      longitude: 80
    ),
    span: MKCoordinateSpan(
      latitudeDelta: 100,
      longitudeDelta: 100))

  // --------------------------------

  var body: some View {
    HStack {
      // MARK: - Main Mapping Container
      VStack {
        TopBarView(controller: controller)

        // MARK: - Mapping container.

        HStack {
          //        Map( // new SwiftUI Map
          //          coordinateRegion: $coordinateRegion,
          //          interactionModes: MapInteractionModes.all,
          //          showsUserLocation: true
          //        ).edgesIgnoringSafeArea(.all)
          // Old version -------------------------
          MapView(overlays: controller.overlays, annotations: controller.annotations)
            .edgesIgnoringSafeArea(.all)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
          // -------------------------------------
        }
        .border(Color.black)
        .padding(.top, -5)
        .padding(.bottom, -5)
        .frame(minWidth: 1024, maxWidth: .infinity, minHeight: 800, maxHeight: .infinity)
        .layoutPriority(1.0)

        // MARK: - Cluster selection and filtering.

        HStack {
          ControlBarView(controller: controller, clusters: clusterData )
        }
        .background(currentMode == .dark ? Color.blue : Color.cyan)
        .opacity(0.70)
        .frame(maxWidth: .infinity, minHeight: 30, maxHeight: 30)
        .padding(0)
      } // end containor VStack
      .frame(minWidth: 1300)
    } // end outer HStack
    //.background(currentMode == .dark ? Color.green : Color.red)
  }
} // end ContentView

// MARK: - Content Preview

/// Main content preview
struct ContentView_Previews: PreviewProvider {
  static var previews: some View {
    ContentView()
      .environmentObject(Controller())
  }
}
