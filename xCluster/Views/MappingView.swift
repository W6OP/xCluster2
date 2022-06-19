//
//  MappingView.swift
//  xCluster
//
//  Created by Peter Bourget on 4/3/22.
//

import SwiftUI
import MapKit
import Foundation

// MARK: - Map View
struct MapView: NSViewRepresentable {
  typealias MapViewType = NSViewType
  var overlays: [ClusterMKGeodesicPolyline]
  var annotations: [ClusterPinAnnotation]

  func makeNSView(context: Context) -> MKMapView {
    let mapView = MKMapView()
    mapView.delegate = context.coordinator

    return mapView
  }

  func updateNSView(_ uiView: MKMapView, context: Context) {
    updateOverlays(from: uiView)
    updateAnnotations(from: uiView)
    //print("MapView Updated")
  }

  // https://medium.com/@mauvazquez/decoding-a-polyline-and-drawing-it-with-swiftui-mapkit-611952bd0ecb
  public func updateOverlays(from mapView: MKMapView) {

    mapView.addOverlays(overlays)

    //if !overlays.isEmpty {
      for overlay in mapView.overlays {
        //print("overlay title: \(overlay.title)")
        if overlay.title == "isDeleted" {
          //print("deleted mapview overlay")
          mapView.removeOverlay(overlay)
        }
      //}
    }
    //print("overlay count: \(overlays.count)")
  }

  public func updateAnnotations(from mapView: MKMapView) {

    mapView.addAnnotations(annotations)

    //if !annotations.isEmpty {
      for annotation in mapView.annotations {
        //print("annotation title: \(annotation.title)-\(annotation.subtitle)")
        if annotation.title == "isDeleted" {
          //print("deleted mapview annotation")
          mapView.removeAnnotation(annotation)
        }
      }
    //}
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

    let identifier = "spot"
    //let spotFoundIdentifier = "spotFound"
    let annotationView = mapView.dequeueReusableAnnotationView(withIdentifier:
                                                                identifier) ?? MKAnnotationView(annotation: annotation,
                                                                                                reuseIdentifier: identifier)

    annotationView.canShowCallout = true

    if annotation is MKUserLocation {
      return nil
    } else if annotation is ClusterPinAnnotation {
      annotationView.image =  NSImage(imageLiteralResourceName: identifier)
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

//struct MappingView_Previews: PreviewProvider {
//    static var previews: some View {
//        MappingView()
//    }
//}
