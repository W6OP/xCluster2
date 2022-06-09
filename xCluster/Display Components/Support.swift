//
//  Support.swift
//  xCluster
//
//  Created by Peter Bourget on 3/19/22.
//

import Cocoa
import Foundation
import SwiftUI
import MapKit
import Combine
import os
import CallParser

/// Status message definition
struct StatusMessage: Identifiable, Hashable {
  var id = UUID()
  var message = ""

  init(message: String) {
    self.message = message
  }
}

// MARK: - Cluster Overlay

class ClusterMKGeodesicPolyline: MKGeodesicPolyline {

  var clusterOverlayId: UUID
  var associatedSpotterPinId = 0
  var associatedDxPinId = 0

  override init() {
    clusterOverlayId = UUID()

    super.init()
  }

}



// MARK: - Cluster Pin Annotation

enum ClusterPinAnnotationType {
  case dx
  case spotter
  case undefined
}

enum CreateDxPin {
  case createAll
  case ignoreDx
}


class ClusterPinAnnotation: MKPointAnnotation {
  var clusterPinId: UUID
  var clusterPinType: ClusterPinAnnotationType
  var clusterPinSequence = 0
  var isDeleted = false
  var isFiltered = false
  var annotationTitles: [String] = []
  var station = ""

  let maxNumberOfAnnotationTitles = 14

  override init() {
    clusterPinId = UUID()
    clusterPinType = .undefined

    super.init()
  }

  /// Add a single title to the annotationTitles array.
  /// - Parameters:
  ///   - titles: String
  ///   - annotationType: AnnotationType
  func addAnnotationTitle(title: String) {
    annotationTitles.append(title)
    annotationTitles = annotationTitles.uniqued()
    updateAnnotationTitle(titles: annotationTitles)
  }

  /// Add a single title to the annotationTitles array.
  /// - Parameters:
  ///   - dxStation: String
  ///   - spotter: String
  ///   - formattedFrequency: String
  func addAnnotationTitle(dxStation: String, spotter: String, formattedFrequency: String) {

    let title = ("\(dxStation)-\(spotter)  \(formattedFrequency)")
    //print("addAnnotationTitle: \(dxStation)-\(spotter)-\(formattedFrequency)")

      annotationTitles.append(title)
      annotationTitles = annotationTitles.uniqued()
      updateAnnotationTitle(titles: annotationTitles)
  }

  /// Update the annotation titles.
  /// - Parameters:
  ///   - titles: [String]
  ///   - annotationType: AnnotationType
  func updateAnnotationTitle(titles: [String]) {
    var combinedTitle = ""

    for title in annotationTitles {
      combinedTitle += (title + "\r")
    }

    self.title = String(combinedTitle.dropLast())
    //print("updateAnnotationTitle: \(self.title ?? "")")

    if annotationTitles.count > maxNumberOfAnnotationTitles {
      annotationTitles.removeLast()
    }
  }


  /// Add the subtitle
  /// - Parameter subTitle: String
  func addSubTitle(subTitle: String) {
    self.subtitle = subTitle
  }

  /// Set the annotation as expired and marked for deletion.
    func setExpired() {
      self.subtitle = "isDeleted"
    }
  
}

// MARK: - Cluster Spot

/// Definition of a ClusterSpot
struct ClusterSpot: Identifiable, Hashable {

  enum FilterReason: Int {
    case band
    case call
    case country
    case notDigi
    case grid
    case mode
    case time
    case none
  }

  var id: Int // the spots own hash value initially
  var spotterPinId: Int // spotterPin.hashValue
  var dxPinId: Int // dxPin.hashValue
  var dxStation: String
  var frequency: String
  var formattedFrequency = ""
  var band: Int
  var mode = ""
  var spotter: String
  var timeUTC: String
  var comment: String
  var grid: String
  var spotterCountry: String
  var dxCountry: String
  var qrzInfoCombinedJSON = ""
  var filterReasons = [FilterReason]()
  var isInvalidSpot = true
  var isDigiMode = false
  var spotterCoordinates: [String: Double] = ["": 0]
  var dxCoordinates: [String: Double] = ["": 0]
  var isHighlighted = false

  let maxNumberOfAnnotationTitles = 14

  private(set) var isFiltered: Bool

  init() {
    id = 0
    spotterPinId = 0
    dxPinId = 0
    dxStation = ""
    frequency = ""
    band = 99
    spotter = ""
    timeUTC = ""
    comment = ""
    grid = ""
    spotterCountry = ""
    dxCountry = ""
    isFiltered = false
  }

  // need to convert 3.593.4 to 3.5934
  mutating func setFrequency(frequency: String) {
    self.frequency = frequency
    let format = formatFrequency(frequency: frequency)
    formattedFrequency = String(format: "%.3f", format)
    band = convertFrequencyToBand(frequency: frequency)
  }

  func formatFrequency(frequency: String) -> Float {
    let components = frequency.trimmingCharacters(in: .whitespaces).components(separatedBy: ".")
    var suffix = ""

    // truncate if more than 3 components ie. 14.074.1
    let prefix = components[0]
    suffix += components[1]

    let result = Float(("\(prefix).\(suffix)"))?.roundTo(places: 4)

    return result ?? 0.0
  }

  func isInDigiLimit() -> Bool {
    return false
  }

//70154.7 shows as 70.154 correct
  // 144174.0 shows as 44.174
  
  // swiftlint:disable cyclomatic_complexity
  /// Convert a frequency to a band.
  /// - Parameter frequency: String
  /// - Returns: Int
  func convertFrequencyToBand(frequency: String) -> Int {
    var band: Int
    let frequencyMajor = frequency.prefix(while: {$0 != "."})

    switch frequencyMajor {
    case "1":
      band = 160
    case "3", "4":
      band = 80
    case "5":
      band = 60
    case "7":
      band = 40
    case "10":
      band = 30
    case "14":
      band = 20
    case "18":
      band = 17
    case "21":
      band = 15
    case "24":
      band = 12
    case "28":
      band = 10
    case "50", "51", "52", "53", "54":
      band = 6
    default:
      band = 99
    }

    return band
  }

  /// Not currently used
  /// - Parameter frequency: Float
  /// - Returns: Int
  func setBand(frequency: Float) -> Int {
    switch frequency {
    case 1.8...2.0:
      return 160
    case 3.5...4.0:
      return 80
    case 5.0...6.0:
      return 60
    case 7.0...7.3:
      return 40
    case 10.1...10.5:
      return 30
    case 14.0...14.350:
      return 20
    case 18.068...18.168:
      return 17
    case 21.0...21.450:
      return 15
    case 24.890...24.990:
      return 12
    case 28.0...29.7:
      return 10
    case 70.0...75.0:
      return 4
    case 50.0...54.0:
      return 6
    case 144.0...148.0:
      return 2
    default:
      return 0
    }
  }

  /// Populate the spot information from the stationInformationCombined.
  mutating func populateSpotInformation(stationInformationCombined: StationInformationCombined) {

    spotterCountry = stationInformationCombined.spotterCountry
    dxCountry = stationInformationCombined.dxCountry
    mode = stationInformationCombined.mode

    spotterCoordinates["latitude"] = stationInformationCombined.spotterLatitude
    spotterCoordinates["longitude"] = stationInformationCombined.spotterLongitude

    dxCoordinates["latitude"] = stationInformationCombined.dxLatitude
    dxCoordinates["longitude"] = stationInformationCombined.dxLongitude
  }

  // MARK: - Overlays

  /// Build the line (overlay) to display on the map.
  /// - Parameter qrzInfoCombined: combined data of a pair of call signs - QRZ information.
  mutating func createOverlay() -> ClusterMKGeodesicPolyline {

    let locations = [
      CLLocationCoordinate2D(latitude: spotterCoordinates["latitude"] ?? 0,
                             longitude: spotterCoordinates["longitude"] ?? 0),
      CLLocationCoordinate2D(latitude: dxCoordinates["latitude"] ?? 0,
                             longitude: dxCoordinates["longitude"] ?? 0)]

    let overlay = ClusterMKGeodesicPolyline(coordinates: locations, count: locations.count)
    overlay.title = String(band)
    overlay.subtitle = mode

    id = overlay.hashValue

    return overlay
  }

  // MARK: - Annotations

  // https://medium.com/macoclock/mapkit-map-pin-and-annotation-5c7d56439c66
    /// Create the pin for the spotter and populate it's data.
    /// - Parameter stationInfoCombined: StationInformationCombined
    mutating func createSpotterAnnotation() -> ClusterPinAnnotation {

      let spotterPin = ClusterPinAnnotation()
      let title = ("\(spotter)-\(dxStation)  \(formattedFrequency)")

      spotterPin.coordinate = CLLocationCoordinate2D(latitude: spotterCoordinates["latitude"] ?? 0,
                                                     longitude: spotterCoordinates["longitude"] ?? 0)

      // common
      spotterPin.addAnnotationTitle(title: title)
      spotterPin.addSubTitle(subTitle: spotterCountry)
      spotterPin.station = spotter

      spotterPin.clusterPinType = .spotter
      spotterPinId = spotterPin.hashValue

      return spotterPin
    }

   /// Create the pin for the DX station and populate it's data.
   /// - Parameter stationInfoCombined: StationInformationCombined
  mutating func createDXAnnotation() -> ClusterPinAnnotation {

    let dxPin = ClusterPinAnnotation()
    let title = ("\(dxStation)-\(spotter)  \(formattedFrequency)")

    // common
    dxPin.addAnnotationTitle(title: title)
    dxPin.addSubTitle(subTitle: dxCountry)
    dxPin.station = dxStation

    dxPin.coordinate = CLLocationCoordinate2D(latitude: dxCoordinates["latitude"] ?? 0,
                                              longitude: dxCoordinates["longitude"] ?? 0)
    dxPin.clusterPinType = .dx
    dxPinId = dxPin.hashValue

    return dxPin
  }

  // MARK: - Filters

  /// Add or Reset a specific filter.
  /// - Parameter filterReason: FilterReason
  mutating func manageFilters(reason: FilterReason) {

    if filterReasons.contains(reason) {
      removeFilter(reason: reason)
      //print("filter removed: \(self.formattedFrequency)")
    } else {
      filterReasons.append(reason)
      self.isFiltered = true
      //print("filter added: \(self.formattedFrequency)")
    }
    //print("filter count: \(filterReasons.count)")
  }

  mutating func removeFilter(reason: FilterReason) {
    if filterReasons.contains(reason) {
      let index = filterReasons.firstIndex(of: reason)!
      self.filterReasons.remove(at: index)
    }

    if self.filterReasons.isEmpty {
      self.isFiltered = false
    }
  }
} // end ClusterSpot

/// Metadata of the currently connected host.
struct ConnectedCluster: Identifiable, Hashable {
  var id: Int
  var clusterAddress: String
  var clusterType: ClusterType
}

// MARK: - Actors

actor SpotHistory {
  var spots = [Int: (dxStation: String, spotter: String, frequency: String) ]()

  func addToHistory(spotId: Int, description: (dxStation: String, spotter: String, frequency: String)) {
    spots[spotId] = description
  }

  func searchHistory(description: (dxStation: String, spotter: String, frequency: String)) -> Bool {

    let item = spots.first { key, value in
      value.dxStation == description.dxStation &&
      value.spotter == description.spotter &&
      value.frequency == description.frequency
      }

      if item != nil {
        return true
      }

    return false
  }

  func truncateHistory(amount: Int, fullDelete: Bool) {
    switch fullDelete {
    case true:
      spots.removeAll()
    default:
      //spots.removeFirst(amount)
      break
    }
  }
}

/// Array of Station Information
actor StationInformationPairs {
  var callSignPairs = [Int: [StationInformation]]()

  /// Add a spot to a StationInformationPair.
  /// - Parameters:
  ///   - spotId: Int
  ///   - stationInformation: StationInformation
  /// - Returns:  [StationInformation]
  private func add(spotId: Int, stationInformation: StationInformation) -> [StationInformation] {

    var callSignPair: [StationInformation] = []
    callSignPair.append(stationInformation)
    callSignPairs[spotId] = callSignPair

    return callSignPair
  }

  /// Check if a pair exists and either add or update as necessary.
  /// - Parameters:
  ///   - spotId: Int
  ///   - stationInformation: StationInformation
  /// - Returns: [StationInformation]
  func checkCallSignPair(spotId: Int, stationInformation: StationInformation) ->
    [StationInformation] {
    var callSignPair: [StationInformation] = []

    if callSignPairs[spotId] != nil {
      callSignPair = updateCallSignPair(spotId: spotId, stationInformation: stationInformation)
    } else {
      callSignPair = add(spotId: spotId, stationInformation: stationInformation)
    }

    return callSignPair
  }

  /// Update a pair.
  /// - Parameters:
  ///   - spotId: Int
  ///   - stationInformation: StationInformation
  /// - Returns: [StationInformation]
  private func updateCallSignPair(spotId: Int, stationInformation: StationInformation) -> [StationInformation] {

    var callSignPair: [StationInformation] = []

    if callSignPairs[spotId] != nil {
      callSignPair = callSignPairs[spotId]!
      callSignPair.append(stationInformation)
      return callSignPair
    }

    return callSignPair
  }

  /// Remove all pairs.
  func clear() {
    callSignPairs.removeAll()
  }

  func getCount() -> Int {
    return callSignPairs.count
  }
} // end actor

/// Structure to hold a matching pair of Hits
actor HitPair {
  var hits: [Hit] = []

  /// Add an array of HIT.
  /// - Parameter hits: [Hit]
  func addHits(hits: [Hit]) {
    self.hits.append(contentsOf: hits)
  }

  /// Remove all hits form the pair
  func clear() {
    hits.removeAll()
  }

  // return the number of Hits.
  func getCount() -> Int {
    return hits.count
  }
}

/// Temporary storage of Hits to match up with temporarily
/// stored ClusterSpots.
actor HitCache {
  var hits: [Int: [Hit]] = [:]

  /// Add a Hit to the cache.
  /// - Parameters:
  ///   - hitId: Int
  ///   - hit: Hit
  func addHit(hitId: Int, hit: Hit) {
    if hits[hitId] != nil {
        hits[hitId]?.append(hit)
    } else {
      var newHits: [Hit] = []
      newHits.append(hit)
      hits.updateValue(newHits, forKey: hitId)
    }
  }

  /// Remove 2 Hits.
  /// - Parameter spotId: Int
  func removeHits(spotId: Int) -> [Hit] {
    if hits[spotId] != nil && hits[spotId]!.count > 1 {
      return hits.removeValue(forKey: spotId) ?? []
    }
    return []
  }

  /// Remove all Hits.
  func clear() {
    hits.removeAll()
  }

  /// Return the number of Hits.
  /// - Returns: Int
  func getCount() -> Int {
    return hits.count
  }

  /// Return the number of Hits.
  /// - Returns: Int
  func getCount(spotId: Int) -> Int {
    return hits[spotId]?.count ?? 0
  }
}

/// Temporary storage of ClusterSpots to match with returned.
/// hits from the Call Parser
actor SpotCache {
  var spots: [Int: ClusterSpot] = [:]

  /// Add a ClusterSpot to the cache.
  /// - Parameter spot: ClusterSpot
  func addSpot(spot: ClusterSpot) {
    spots[spot.id] = spot
  }

  /// Retieve and remove a ClusterSpot by id.
  /// - Parameter spotId: Int
  func removeSpot(spotId: Int) -> ClusterSpot? {
    if spots[spotId] != nil {
      return spots.removeValue(forKey: spotId) ?? nil
    }
    return nil
  }

  /// Remove all ClusterSpots from the cache.
  func clear() {
    spots.removeAll()
  }

  /// Get a count of ClusterSpots in the cache.
  /// - Returns: Int
  func getSpotCount() -> Int {
    return spots.count
  }
}

// MARK: - Extensions

/// Keep a collection with unique values only
extension Array {
    func unique<T:Hashable>(by: ((Element) -> (T)))  -> [Element] {
        var set = Set<T>() //the unique list kept in a Set for fast retrieval
        var arrayOrdered = [Element]() //keeping the unique list of elements but ordered
        for value in self {
            if !set.contains(by(value)) {
                set.insert(by(value))
                arrayOrdered.append(value)
            }
        }

        return arrayOrdered
    }
}

/// Remove first element that meets condition.
extension RangeReplaceableCollection {
    @discardableResult
    mutating func removeFirst(where predicate: (Element) throws -> Bool) rethrows -> Element? {
        guard let index = try firstIndex(where: predicate) else { return nil }
        return remove(at: index)
    }
}

// Remove last element that meets condition.
extension RangeReplaceableCollection where Self: BidirectionalCollection {
    @discardableResult
    mutating func removeLast(where predicate: (Element) throws -> Bool) rethrows -> Element? {
        guard let index = try lastIndex(where: predicate) else { return nil }
        return remove(at: index)
    }
}
