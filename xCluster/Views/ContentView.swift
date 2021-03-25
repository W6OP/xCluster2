//
//  ContentView.swift
//  xCluster
//
//  Created by Peter Bourget on 3/13/21.
//

import SwiftUI
import CallParser
import MapKit

// MARK: - Map View
//struct MapView: NSViewRepresentable {
//  typealias MapViewType = NSViewType
//  var overlays: [MKPolyline]
//
//  func makeNSView(context: Context) -> MKMapView {
//    let mapView = MKMapView()
//    mapView.delegate = context.coordinator
//
//    return mapView
//  }
//
//  func updateNSView(_ uiView: MKMapView, context: Context) {
//    updateOverlays(from: uiView)
//  }
//
//  // https://medium.com/@mauvazquez/decoding-a-polyline-and-drawing-it-with-swiftui-mapkit-611952bd0ecb
//  public func updateOverlays(from mapView: MKMapView) {
//    mapView.removeOverlays(mapView.overlays)
//
//    for polyline in overlays {
//      mapView.addOverlay(polyline)
//    }
//
//    //    setMapZoomArea(map: mapView, polyline: polyline, edgeInsets: mapZoomEdgeInsets, animated: true)
//  }
//
//  func makeCoordinator() -> Coordinator {
//    Coordinator(self)
//  }
//} // end struct

//https://www.hackingwithswift.com/books/ios-swiftui/communicating-with-a-mapkit-coordinator
//class Coordinator: NSObject, MKMapViewDelegate {
//  var parent: MapView
//
//  init(_ parent: MapView) {
//    self.parent = parent
//  }
//
//  func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
//    //print(mapView.centerCoordinate)
//
//  }
//
//  func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
//    let renderer = MKPolylineRenderer(overlay: overlay)
//    renderer.strokeColor = .blue
//    renderer.lineWidth = 1.0
//    return renderer
//  }
//} // end class

// Extension to add overlay on Map()
extension Map {
  func mapStyle(_ mapType: MKMapType, showScale: Bool = true, showTraffic: Bool = false) -> some View {
    //      let map = MKMapView.appearance()
    //        map.mapType = mapType
    //        map.showsScale = showScale
    //        map.showsTraffic = showTraffic
    return self
  }

  func addAnnotations(_ annotations: [MKAnnotation]) -> some View {
    //MKMapView.appearance().addAnnotations(annotations)
    return self
  }

  func addOverlay(_ overlay: MKOverlay) -> some View {
    //MKMapView.appearance().addOverlay(overlay)

    return self
  }
}

// MARK: - Content View ------------------------------------------------------------.

/// Main entry point
struct ContentView: View {
  @Environment(\.openURL) var openURL
  @EnvironmentObject var controller: Controller
  @ObservedObject var userSettings = UserSettings()
  @State private var showPreferences = false
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
    VStack {
      // MARK: - band buttons.

      HStack {
        // show preferences
        Button(action: {self.showPreferences.toggle()}) {
          Text("Settings")
        }
        .padding(.top, 4)
        .padding(.leading, 4)
        .sheet(isPresented: $showPreferences) {

          return PreferencesView()
        }

        Divider()
        ClusterPickerView(controller: controller, clusters: clusters)
        Divider()
        BandViewToggle(controller: controller, bands: bands)
      }
      .padding(.top, -2).padding(.bottom, 2)
      .frame(maxWidth: .infinity, minHeight: 30, maxHeight: 30)
      .background(Color.blue)
      .opacity(0.70)

      // MARK: - mapping container.

      HStack {
        Map(
          coordinateRegion: $coordinateRegion,
          interactionModes: MapInteractionModes.all,
          showsUserLocation: true
        ).edgesIgnoringSafeArea(.all)
        // Old version -------------------------
        //        MapView(overlays: controller.overlays)
        //          .edgesIgnoringSafeArea(.all)
        //          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // -------------------------------------
      }
      .border(Color.black)
      .padding(.top, 0)
      .frame(minWidth: 1024, maxWidth: .infinity, minHeight: 800, maxHeight: .infinity)
      .layoutPriority(1.0)

      // MARK: - Cluster selection and filtering.
      HStack {
        ClusterControlView(controller: controller) //, clusters: clusters
      }
      .background(Color.blue)
      .opacity(0.70)
      .frame(maxWidth: .infinity, minHeight: 30, maxHeight: 30)
      .padding(0)

      // MARK: - Cluster display and status messages.

      //ClusterDisplayView(controller: controller)

    } // end outer VStack
    .frame(minWidth: 1300)

    .onAppear { // comment out for debugging and designing
      #if !DEBUG
      if let url = URL(string: "xClusterApp://spots") {
        openURL(url)
      }
      #endif
    }
  }
} // end ContentView

// MARK: - List of band toggles

// https://stackoverflow.com/questions/60994255/swiftui-get-toggle-state-from-items-inside-a-list

/// Band filter buttons at top of display
struct BandViewToggle: View {
  @ObservedObject var controller: Controller
  @State var bands: [BandIdentifier]

  var body: some View {
    HStack {
      Spacer()
      ForEach(bands.indices) { item in
        Toggle(self.bands[item].band, isOn: self.$bands[item].isSelected.didSet { (state) in
          self.controller.bandFilter = (self.bands[item].id, state )
        })
        .tag(self.bands[item].id)
        .padding(.top, 5)
        .toggleStyle(SwitchToggleStyle(tint: Color.red))
        Divider()
      }
      Spacer()
    }
  }
}

// MARK: - Cluster Picker

struct ClusterPickerView: View {
  var controller: Controller

  @State private var selectedCluster = clusterData[0]
  var clusters: [ClusterIdentifier]
  let characterLimit = 10

  var body: some View {
    HStack {
      Picker(selection: $selectedCluster.id, label: Text("")) {
        ForEach(clusters) { cluster in
          Text("\(cluster.name)")
        }
      }.frame(minWidth: 200, maxWidth: 200)
      .onReceive([selectedCluster].publisher.first()) { value in
        if value.id != 9999 {
          if self.controller.connectedCluster.id != value.id {
            controller.spots = [ClusterSpot]()
            self.controller.connectedCluster = clusterData.first {$0.id == value.id}!
          }
        }
      }
    }
    .padding(.trailing)
  }
}

// MARK: - Control Bar

/// Cluster name picker
struct ClusterControlView: View {
  var controller: Controller
  let characterLimit = 10

  @Environment(\.openURL) var openURL
  @State private var callSignFilter = ""
  @State private var showSpots = true

  var body: some View {
    HStack {

      Spacer()
      HStack {

        Button("Open Spots") {
          if let url = URL(string: "xClusterApp://spots") {
            openURL(url)
          }
        }
        Divider()
        TextField("Call Filter", text: $callSignFilter, onEditingChanged: { _ in // (changed)
          // onEditingChanged
          callSignFilter = callSignFilter.uppercased()
          if callSignFilter.count > characterLimit {
            callSignFilter = String(callSignFilter.prefix(characterLimit))
          }
        }) {
          // onCommit"
          self.controller.setCallFilter(callSign: callSignFilter.uppercased())
        }
        .textFieldStyle(RoundedBorderTextFieldStyle())
        .frame(maxWidth: 150)

        Divider()

        Button(action: {self.controller.clusterCommand = (20, "show dx/20")}) {
          Text("show dx/20")
        }

        Divider()

        Button(action: {self.controller.clusterCommand = (50, "show dx/50")}) {
          Text("show dx/50")
        }
      }
      .frame(minWidth: 500)
      .padding(.leading)
      .padding(.vertical, 2)
      //      .onAppear {
      //        if let url = URL(string: "xClusterApp://spots") {
      //             openURL(url)
      //        }
      //      }
      /// https://developer.apple.com/forums/thread/650419
      Spacer()
    }
  }

}

// MARK: - Content Preview

/// Main content preview
struct ContentView_Previews: PreviewProvider {
  static var previews: some View {
    ContentView()
      .environmentObject(Controller())
  }
}
