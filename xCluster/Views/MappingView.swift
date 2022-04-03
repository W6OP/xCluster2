//
//  MappingView.swift
//  xCluster
//
//  Created by Peter Bourget on 4/3/22.
//

import SwiftUI
import MapKit

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

     let identifier = "2m"
     let annotationView = mapView.dequeueReusableAnnotationView(withIdentifier:
          identifier) ?? MKAnnotationView(annotation: annotation,
                                          reuseIdentifier: identifier)

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

//struct MappingView_Previews: PreviewProvider {
//    static var previews: some View {
//        MappingView()
//    }
//}
