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

// MARK: - Status Message

/// Status message definition
struct StatusMessage: Identifiable, Hashable {
  var id = UUID()
  var message = ""

  init(message: String) {
    self.message = message
  }
}

// MARK: - Cluster Overlay

/// Custom MKGeodesicPolyline.
class ClusterMKGeodesicPolyline: MKGeodesicPolyline {

  var band = 0

  override init() {
    super.init()
  }
}

// MARK: - Cluster Pin Annotation

/// Annotation Type for Cluster Pins.
enum ClusterPinAnnotationType: String {

  case all = "all"
  case dx = "dx"
  case spotter = "spotter"
  case undefined = "undefined"
}

enum objectStatus: String {
  case isDeleted = "isDeleted"
}

/// Custom MKPointAnnotation.
class ClusterPinAnnotation: MKPointAnnotation {
  var annotationId: UUID
  var isDeleted = false
  var isFiltered = false
  var annotationTitles: [String] = []
  var annotationStation = ""
  var band = [Int]()
  var annotationType: ClusterPinAnnotationType = .spotter
  // TODO: - Rename after spotter annotations are implemented too - was spotterReference
  var matchReference: [String] = [] {
    didSet {
      if matchReference.count == 0 {
        setAsDeleted()
      }
    }
  }

  var referenceCount: Int {
    get { matchReference.count }
  }

  let maxNumberOfAnnotationTitles = 14

  override init() {
    annotationId = UUID()
    annotationType = .undefined

    super.init()
  }

  /// Set the relevant properties for the annotation.
  /// - Parameters:
  ///   - station: String: station name (call sign)
  ///   - spotterStation: String: if this is a DX annotation, the spotterAnnotation associated with it.
  ///   - annotationType: AnnotationType: type of this annotation.
  func setProperties(station: String, matchStation: String? = nil, annotationType: ClusterPinAnnotationType) {
    self.annotationStation = station
    self.annotationType = annotationType
    self.matchReference.append(matchStation ?? "")
  }

  /// Build a single title to add to the annotationTitles array.
  /// - Parameters:
  ///   - dxStation: String: DX station name.
  ///   - spotter: String: Spotter station name.
  ///   - formattedFrequency: String: Frequency formatted for display.
  func addAnnotationTitle(dxStation: String, spotterStation: String, formattedFrequency: String) {

    var title = "unknown-unknown  0.0"

    switch annotationType {
    case .dx:
      //print("dx: \(dxStation)-\(spotterStation)")
      title = ("\(dxStation)-\(spotterStation)  \(formattedFrequency)")
      //print("dx title added: \(title)")
      matchReference.append(spotterStation)
      //print("spotter reference added: \(spotterStation) for \(dxStation)")
    case .spotter:
      //print("spotter: \(spotterStation)-\(dxStation)")
      title = ("\(spotterStation)-\(dxStation)  \(formattedFrequency)")
      //print("spotter title added: \(title)")
      matchReference.append(dxStation)
      //print("dx reference added: \(dxStation) for \(spotterStation)")
    default:
      print("missing annotation type: \(annotationType)")
    }

    annotationTitles.append(title)
    annotationTitles = annotationTitles.uniqued()
    updateDisplayTitle(titles: annotationTitles)
  }

  /// Update the annotation titles.
  /// - Parameters:
  ///   - titles: [String]: One or more titles to add.
  func updateDisplayTitle(titles: [String]) {
    var combinedTitle = ""

    for title in annotationTitles {
      combinedTitle += (title + "\r")
    }

    self.title = String(combinedTitle.dropLast())

    if annotationTitles.count > maxNumberOfAnnotationTitles {
      annotationTitles.removeLast()
    }
  }

  /// Remove a title when the station annotation is deleted.
  /// - Parameter call: String: call sign to search for.
  func removeAnnotationReference(station: String) {
    //print("\(annotationType): reference removed: \(station) from \(annotationStation)")
    matchReference.removeAll(where: {$0 == station} )
  }

  /// Add the subtitle.
  /// - Parameter subTitle: String: Subtitle to add.
  func addSubTitle(subTitle: String) {
    self.subtitle = subTitle
  }

  func setAsDeleted() {
    isDeleted = true
    title = "isDeleted"
  }
}

// MARK: - Cluster Spot

/// Definition of a ClusterSpot
/// This spot has the id of the associated overlay and annotations.
struct ClusterSpot: Identifiable, Hashable {

  enum FilterType: Int {
    case band
    case call
    case country
    case notDigi
    case grid
    case mode
    case time
    case none
    case all
  }

  var id: Int
  var overlayId: ObjectIdentifier?
  var spotterAnnotationId: UUID
  var dxAnnotationId: UUID
  var spotterStation: String
  var dxStation: String
  var frequency: String
  var formattedFrequency = "" {
    didSet {
      setDigiMode()
    }
  }
  var band: Int
  var mode = ""
  var timeUTC: String
  var comment: String
  var grid: String
  var spotterCountry: String
  var dxCountry: String
  var qrzInfoCombinedJSON = ""
  var filterReasons = [FilterType]()
  var isInvalidSpot = true
  var isDigiMode = false
  var spotterCoordinates: [String: Double] = ["": 0]
  var dxCoordinates: [String: Double] = ["": 0]
  var isHighlighted = false

  let maxNumberOfAnnotationTitles = 14

  private(set) var isFiltered: Bool

  init() {
    id = 0
    overlayId = nil
    spotterAnnotationId = UUID()
    dxAnnotationId = UUID()
    dxStation = ""
    frequency = ""
    band = 99
    spotterStation = ""
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
//  func setBand(frequency: Float) -> Int {
//    switch frequency {
//    case 1.8...2.0:
//      return 160
//    case 3.5...4.0:
//      return 80
//    case 5.0...6.0:
//      return 60
//    case 7.0...7.3:
//      return 40
//    case 10.1...10.5:
//      return 30
//    case 14.0...14.350:
//      return 20
//    case 18.068...18.168:
//      return 17
//    case 21.0...21.450:
//      return 15
//    case 24.890...24.990:
//      return 12
//    case 28.0...29.7:
//      return 10
//    case 70.0...75.0:
//      return 4
//    case 50.0...54.0:
//      return 6
//    case 144.0...148.0:
//      return 2
//    default:
//      return 0
//    }
//  }

  /// Populate the spot information from the stationInformationCombined.
  /// - Parameter stationInformationCombined: StationInformationCombined: Struct
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
  mutating func createOverlay() -> ClusterMKGeodesicPolyline {

    self.id = self.hashValue

    let locations = [
      CLLocationCoordinate2D(latitude: spotterCoordinates["latitude"] ?? 0,
                             longitude: spotterCoordinates["longitude"] ?? 0),
      CLLocationCoordinate2D(latitude: dxCoordinates["latitude"] ?? 0,
                             longitude: dxCoordinates["longitude"] ?? 0)]

    let overlay = ClusterMKGeodesicPolyline(coordinates: locations, count: locations.count)

    overlay.title = String(band)
    overlay.subtitle = mode

    overlayId = ObjectIdentifier(overlay)

    return overlay
  }

  // MARK: - Annotations

  // https://medium.com/macoclock/mapkit-map-pin-and-annotation-5c7d56439c66
    /// Create the pin for the spotter and populate it's data.
    mutating func createSpotterAnnotation() -> ClusterPinAnnotation {

      let spotterAnnotation = ClusterPinAnnotation()
      spotterAnnotation.setProperties(station: spotterStation, matchStation: dxStation, annotationType: .spotter)

      spotterAnnotation.coordinate = CLLocationCoordinate2D(latitude: spotterCoordinates["latitude"] ?? 0,
                                                     longitude: spotterCoordinates["longitude"] ?? 0)
      // common
      spotterAnnotation.addAnnotationTitle(dxStation: dxStation, spotterStation: spotterStation, formattedFrequency: formattedFrequency)
      spotterAnnotation.addSubTitle(subTitle: spotterCountry)

      spotterAnnotationId = spotterAnnotation.annotationId

      return spotterAnnotation
    }

   /// Create the pin for the DX station and populate it's data.
  mutating func createDXAnnotation() -> ClusterPinAnnotation {

    let dxAnnotation = ClusterPinAnnotation()
    dxAnnotation.setProperties(station: dxStation, matchStation: spotterStation, annotationType: .dx)

    dxAnnotation.coordinate = CLLocationCoordinate2D(latitude: dxCoordinates["latitude"] ?? 0,
                                              longitude: dxCoordinates["longitude"] ?? 0)
    // common
    dxAnnotation.addAnnotationTitle(dxStation: dxStation, spotterStation: spotterStation, formattedFrequency: formattedFrequency)
    dxAnnotation.addSubTitle(subTitle: dxCountry)

    dxAnnotationId = dxAnnotation.annotationId

    return dxAnnotation
  }

  // MARK: - Filters

  /// Add or Reset a specific filter.
  /// - Parameter filterReason: FilterReason: Type of filter to add or remove.
  mutating func manageFilters(filterType: FilterType) {
    if filterReasons.contains(filterType) {
      removeFilter(filterType: filterType)
    } else {
      filterReasons.append(filterType)
      self.isFiltered = true
    }
  }

  /// Remove a filter.
  /// - Parameter filterType: FilterType: Type of filter to remove.
  private mutating func removeFilter(filterType: FilterType) {
    if filterReasons.contains(filterType) {
      let index = filterReasons.firstIndex(of: filterType)!
      self.filterReasons.remove(at: index)
    }

    if self.filterReasons.isEmpty {
      self.isFiltered = false
    }
  }

  // MARK: - Digi Frequency Ranges

  private mutating func setDigiMode() {

    guard let frequency = Float(formattedFrequency) else { return }
    //print("input: \(frequency.roundTo(places: 3))")
    switch Float(frequency.roundTo(places: 3)) {
    case 1.840...1.845:
      isDigiMode = true
    case 1.84...1.845:
      isDigiMode = true
      //    case 3.568...3.570:
      //      return true
      //    case 3.568...3.57:
      //      return true
    case 3.573...3.578:
      isDigiMode = true
    case 5.357:
      isDigiMode = true
      //    case 7.047...7.052:
      //      return true
      //    case 7.056...7.061:
      //      return true
    case 7.074...7.078:
      isDigiMode = true
      //    case 10.130...10.135:
      //      return true
      //    case 10.13...10.135:
      //      return true
      //    case 10.136...10.138:
      //      return true
      //    case 10.140...10.145:
      //      return true
    case 10.136...10.145:
      isDigiMode = true
    case 14.074...14.078:
      isDigiMode = true
    case 14.080...14.082:
      isDigiMode = true
    case 14.08...14.082:
      isDigiMode = true
      //    case 14.090...14.095:
      //      return true
      //    case 14.09...14.095:
      //      return true
    case 18.100...18.106:
      isDigiMode = true
    case 18.10...18.106:
      isDigiMode = true
    case 18.1...18.106:
      isDigiMode = true
      //    case 18.104...18.106:
      //      return true
    case 21.074...21.078:
      isDigiMode = true
      //    case 21.091...21.094:
      //      return true
    case 21.140...21.142:
      isDigiMode = true
    case 21.14...21.142:
      isDigiMode = true
    case 24.915...24.922:
      isDigiMode = true
    case 28.074...28.078:
      isDigiMode = true
    case 28.180...28.182:
      isDigiMode = true
    case 28.18...28.182:
      isDigiMode = true
    case 50.313...50.320:
      isDigiMode = true
    case 50.323...50.328:
      isDigiMode = true
    default:
      isDigiMode = false
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

/// Actor to save spots until they are combined.
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

  /// Retr
  /// ieve and remove a ClusterSpot by id.
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
} // end spot cache

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
