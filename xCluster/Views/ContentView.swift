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

// MARK: - Map View
struct MapView: NSViewRepresentable {
  typealias MapViewType = NSViewType
  var overlays: [MKPolyline]
  var annotations: [MKPointAnnotation]

  func makeNSView(context: Context) -> MKMapView {
    let mapView = MKMapView()
    mapView.delegate = context.coordinator

    return mapView
  }

  func updateNSView(_ uiView: MKMapView, context: Context) {
    updateOverlays(from: uiView)
    updateAnnotations(from: uiView)
  }

  // https://medium.com/@mauvazquez/decoding-a-polyline-and-drawing-it-with-swiftui-mapkit-611952bd0ecb
  public func updateOverlays(from mapView: MKMapView) {

    mapView.removeOverlays(mapView.overlays)

    for overlay in overlays {
      if overlay.subtitle != "expired" {
        // NEED TO LOOK AT JSON
        mapView.addOverlay(overlay)
      } else {
        mapView.removeOverlay(overlay)
      }
    }
  }

  public func updateAnnotations(from mapView: MKMapView) {

    mapView.removeAnnotations(mapView.annotations)

    for annotation in annotations {
      if annotation.subtitle != "expired" {
        mapView.addAnnotation(annotation)
      } else {
        mapView.removeAnnotation(annotation)
      }
    }
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(self)
  }
} // end struct

//https://www.hackingwithswift.com/books/ios-swiftui/communicating-with-a-mapkit-coordinator
class Coordinator: NSObject, MKMapViewDelegate {
  var parent: MapView

  init(_ parent: MapView) {
    self.parent = parent
  }

  func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
    //print(mapView.centerCoordinate)
  }

  // displays custom pin and callout
  func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {

     let Identifier = "2m"
     let annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: Identifier) ?? MKAnnotationView(annotation: annotation, reuseIdentifier: Identifier)

     annotationView.canShowCallout = true
     if annotation is MKUserLocation {
        return nil
     } else if annotation is MKPointAnnotation {
        annotationView.image =  NSImage(imageLiteralResourceName: "2m")
        return annotationView
     } else {
        return nil
     }
  }

  func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {

    let renderer = MKPolylineRenderer(overlay: overlay)
    let lineWidth: CGFloat = 1.75
    let alpha: CGFloat = 0.5

    switch overlay.title {
    case "80":
      renderer.strokeColor = .blue
    case "40":
      renderer.strokeColor = .magenta
    case "30":
      renderer.strokeColor = .black
    case "20":
      renderer.strokeColor = .red
    case "15":
      renderer.strokeColor = .purple
    case "17":
      renderer.strokeColor = .darkGray
    case "6":
      renderer.strokeColor = .orange
    default:
      renderer.strokeColor = .brown
    }
    renderer.alpha = alpha
    renderer.lineWidth = lineWidth

    return renderer
  }
} // end class

// MARK: - Content View

/// Main entry point
struct ContentView: View {
  @Environment(\.openURL) var openURL
  @EnvironmentObject var controller: Controller
  @ObservedObject var userSettings = UserSettings()
  @State private var showPreferences = false

  var bands: [BandIdentifier] = bandData
  var modes: [ModeIdentifier] = modeData
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
        // MARK: - Band buttons.
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
          ButtonBarView(controller: controller, clusters: clusters, modes: modes, bands: bands)
        }
        .padding(.top, -2).padding(.bottom, 2)
        .frame(maxWidth: .infinity, minHeight: 30, maxHeight: 30)
        .background(Color.blue)
        .opacity(0.70)

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
        .padding(.top, 0)
        .frame(minWidth: 1024, maxWidth: .infinity, minHeight: 800, maxHeight: .infinity)
        .layoutPriority(1.0)

        // MARK: - Cluster selection and filtering.

        HStack {
          ControlBarView(controller: controller)
        }
        .background(Color.blue)
        .opacity(0.70)
        .frame(maxWidth: .infinity, minHeight: 30, maxHeight: 30)
        .padding(0)
      } // end map VStack
      .frame(minWidth: 1300)
    } // end outer HStack
  }
} // end ContentView

// MARK: - Button Bar

struct ButtonBarView: View {
  var controller: Controller
  var clusters: [ClusterIdentifier]
  var modes: [ModeIdentifier]
  var bands: [BandIdentifier]

  var body: some View {
    HStack {
      Divider()
      ClusterPickerView(controller: controller, clusters: clusters)
      //Divider()
      //ModeViewToggle(controller: controller, modes: modes)
      Divider()
      BandViewToggle(controller: controller, bands: bands)
    }
  }
}

/// Mode filter buttons at top of display
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
          if self.bands[item].id != 0 {
            self.controller.bandFilter = (self.bands[item].id, state)
          } else {
            for (index, band) in bands.enumerated() where band.id != 0 {
              self.bands[index].isSelected = self.bands[0].isSelected
            }
            self.controller.bandFilter = (0, state)
          }
        })
        .tag(self.bands[item].id)
        .padding(.top, 5)
        .toggleStyle(SwitchToggleStyle(tint: .mint))
        Divider()
      }
      Spacer()
    }
  }
}

// MARK: - Cluster Picker

struct ClusterPickerView: View {
  @State private var selectedCluster = clusterData[0]
  var controller: Controller
  var clusters: [ClusterIdentifier]
  let characterLimit = 10

  var body: some View {
    HStack {
      Picker(selection: $selectedCluster.id, label: Text("")) {
        ForEach(clusters) { cluster in
          Text("\(cluster.name)")
        }
      }
      .padding(.top, 5)
      .frame(minWidth: 200, maxWidth: 200)
      .onReceive([selectedCluster].publisher.first()) { value in
        if value.id != 9999 {
          if self.controller.connectedCluster.id != value.id {
            controller.displayedSpots = [ClusterSpot]()
            self.controller.connectedCluster = clusterData.first {$0.id == value.id}!
          }
        }
      }
    }
    .border(.green)
  }
}

// MARK: - Number of Lines Picker

struct NumberOfSpotsPickerView: View {
  var controller: Controller
  let numberOfSpots: [SpotsIdentifier] = spotsData

  @State private var selectedNumberOfSpots = spotsData[1]

  var body: some View {
    HStack {
      Picker(selection: $selectedNumberOfSpots.id, label: Text("")) {
        ForEach(numberOfSpots) { spot in
          Text("\(spot.displayedLines)")
        }
      }
      .padding(.top, 5)
      .frame(minWidth: 75, maxWidth: 75)
      .onReceive([selectedNumberOfSpots].publisher.first()) { value in
        if value.id != 999 {
          if self.controller.selectedNumberOfSpots.id != value.id {
            self.controller.selectedNumberOfSpots = spotsData.first {$0.id == value.id}!
          }
        }
      }
    }
    .border(.green)
  }
}

// MARK: - Control Bar

/// Cluster name picker
struct ControlBarView: View {
  var controller: Controller
  let characterLimit = 10

  @Environment(\.openURL) var openURL
  @State private var callSignFilter = ""
  @State private var showSpots = true
  @State private var filterByTime = false

  var body: some View {
    HStack {
      Spacer()
      HStack {

        NumberOfSpotsPickerView(controller: controller)

        Divider()

        Toggle("Last 30 minutes", isOn: $filterByTime.didSet { (filterByTime) in
          controller.setTimeFilter(filterState: filterByTime)
        })
        .toggleStyle(SwitchToggleStyle(tint: Color.green))

        Divider()

        TextField("Call Filter", text: $callSignFilter, onEditingChanged: { _ in
          // onEditingChanged
          callSignFilter = callSignFilter.uppercased()
          print("editing changed \(callSignFilter)")
          if callSignFilter.count > characterLimit {
            callSignFilter = String(callSignFilter.prefix(characterLimit))
          }
        }) {
          // onCommit
          self.controller.setCallFilter(callSign: callSignFilter.uppercased())
        }
        .textFieldStyle(RoundedBorderTextFieldStyle())
        .modifier(ClearButton(boundText: $callSignFilter))
        .frame(maxWidth: 150)

        CommandButtonsView(controller: controller)
      }
      .frame(minWidth: 500)
      .padding(.leading)
      .padding(.vertical, 2)

      Spacer()
    }
  }
}

struct CommandButtonsView: View {
  var controller: Controller

  var body: some View {
    HStack {
      Divider()

      Button(action: {self.controller.clusterMessage = CommandType.show20}) {
        Text("show dx/20")
      }

      Divider()

      Button(action: {self.controller.clusterMessage = CommandType.show50}) {
        Text("show dx/50")
      }

      Divider()

      Button(action: {self.controller.applicationMessage = CommandType.clear}) {
        Text("Clear")
      }

    }
  }
}

public struct ClearButton: ViewModifier {
    var text: Binding<String>
    var trailing: Bool

    public init(boundText: Binding<String>, trailing: Bool = true) {
        self.text = boundText
        self.trailing = trailing
    }

    public func body(content: Content) -> some View {
        ZStack(alignment: trailing ? .trailing : .leading) {
            content

            if !text.wrappedValue.isEmpty {
                Image(systemName: "x.circle")
                    .resizable()
                    .frame(width: 17, height: 17)
                    .onTapGesture {
                        text.wrappedValue = ""
                    }
            }
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
