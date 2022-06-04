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
    //print("MapView Updated")
  }

  // https://medium.com/@mauvazquez/decoding-a-polyline-and-drawing-it-with-swiftui-mapkit-611952bd0ecb
  public func updateOverlays(from mapView: MKMapView) {

        mapView.removeOverlays(mapView.overlays)
        mapView.addOverlays(overlays)



//    for overlay in overlays {
//      if overlay.subtitle != "expired" {
//        mapView.addOverlay(overlay)
//      } else {
//        mapView.removeOverlay(overlay)
//      }
//    }

    //print("overlays: \(overlays.count)-\(mapView.overlays.count)")
  }

  public func updateAnnotations(from mapView: MKMapView) {
    var group = [String]()
    mapView.removeAnnotations(mapView.annotations)
    mapView.addAnnotations(annotations)

        for annotation in mapView.annotations {
          let title: String = annotation.title!!
          if title.count > 30 {
            group.append(title)
          }
        }
//    for annotation in annotations {
//      let result = Bool((annotation.title?.contains("-updated"))!)
//      if result {
//        let title = annotation.title?.dropLast(8)
//        mapView.removeAnnotation(annotation)
//        let newTitle: String = String(title!)
//        annotation.title = newTitle
//        //mapView.addAnnotation(annotation)
//        print("annotation updated: \(annotation.title)")
//      } else {
//        if annotation.subtitle != "expired" {
//          mapView.addAnnotation(annotation)
//        } else {
//          mapView.removeAnnotation(annotation)
//        }
//      }
//    }
    //print("titles: \(group)")
    //print("annotations: \(annotations.count)-\(mapView.annotations.count)")
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
    } else if annotation is MKPointAnnotation {
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
