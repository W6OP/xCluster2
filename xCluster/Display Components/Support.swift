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

// MARK: - ClusterSpots

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
  //var floatFrequency: Float = 0.0
  var band: Int
  var spotter: String
  var timeUTC: String
  var comment: String
  var grid: String
  var country: String
  var overlay: MKPolyline!
  var spotterPin = MKPointAnnotation()
  var dxPin = MKPointAnnotation()
  var qrzInfoCombinedJSON = ""
  var filterReasons = [FilterReason]()
  var isInvalidSpot = true
  var overlayExists = false
  var annotationExists = false
  var isDigiMode = false

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
    country = ""
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

//  func setDigiMode(band: Int, frequency: Float) {
//
//    switch band {
//    case 160:
//      break
//    default:
//      break
//    }
//
//  }

  func isInDigiLimit() -> Bool {
    return false
  }

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

  /// Build the line (overlay) to display on the map.
  /// - Parameter qrzInfoCombined: combined data of a pair of call signs - QRZ information.
  mutating func createOverlay(stationInfoCombined: StationInformationCombined) {

    if overlayExists { return }

    let locations = [
      CLLocationCoordinate2D(latitude: stationInfoCombined.spotterLatitude,
                             longitude: stationInfoCombined.spotterLongitude),
      CLLocationCoordinate2D(latitude: stationInfoCombined.dxLatitude,
                             longitude: stationInfoCombined.dxLongitude)]

    let polyline = MKGeodesicPolyline(coordinates: locations, count: locations.count)
    polyline.title = String(band)
    polyline.subtitle = stationInfoCombined.mode
    //polyline.subtitle = String(id)

    id = polyline.hashValue

    self.overlay = polyline
  }

  // https://medium.com/macoclock/mapkit-map-pin-and-annotation-5c7d56439c66
  mutating func createAnnotation(stationInfoCombined: StationInformationCombined) {

    if annotationExists { return }

    let spotterPin = MKPointAnnotation()
    spotterPin.coordinate = CLLocationCoordinate2D(latitude:
                                                    stationInfoCombined
                                                    .spotterLatitude, longitude:
                                                    stationInfoCombined
                                                    .spotterLongitude)
    spotterPin.title = ("\(stationInfoCombined.spotterCall):\(formattedFrequency)")

   let dxPin = MKPointAnnotation()
    dxPin.coordinate = CLLocationCoordinate2D(latitude:
                                                stationInfoCombined.dxLatitude,
                                              longitude:
                                                stationInfoCombined.dxLongitude)
    dxPin.title = ("\(stationInfoCombined.dxCall):\(formattedFrequency)")

    spotterPin.subtitle = stationInfoCombined.spotterCountry
    dxPin.subtitle = stationInfoCombined.dxCountry

    spotterPinId = spotterPin.hashValue
    dxPinId = dxPin.hashValue

    self.spotterPin = spotterPin
    self.dxPin = dxPin
  }

  /// Set a specific filter.
  /// - Parameter filterReason: FilterReason
//  mutating func setFilter(reason: FilterReason) {
//    self.filterReasons.append(reason)
//    self.isFiltered = true
//  }

  /// Add or Reset a specific filter.
  /// - Parameter filterReason: FilterReason
  mutating func manageFilters(reason: FilterReason) {

    if filterReasons.contains(reason) {
      removeFilter(reason: reason)
    } else {
      filterReasons.append(reason)
      self.isFiltered = true
    }
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

  /// Reset the filter state of all of a certain type.
  /// - Parameter filterReason: FilterReason
//  mutating func resetAllFiltersOfType(reason: FilterReason) {
//    self.filterReasons.removeAll { value in
//      return value == reason
//    }
//
//    if self.filterReasons.isEmpty {
//      self.isFiltered = false
//    }
//  }
}

/// Metadata of the currently connected host.
struct ConnectedCluster: Identifiable, Hashable {
  var id: Int
  var clusterAddress: String
  var clusterType: ClusterType
}

// MARK: - Actors

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

  /// Add a hit.
  /// - Parameter hit: Hit
  func addHit(hit: Hit) {
    hits.append(hit)
  }

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
  func removeHits(spotId: Int) {
    hits.removeValue(forKey: spotId)
  }

  /// Retrieve an array of Hits.
  /// - Parameter spotId: Int
  /// - Returns: [Hit]
  func retrieveHits(spotId: Int) -> [Hit] {
    if hits[spotId] != nil {
      return hits[spotId]!
    }
    return  []
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
    return hits[spotId]!.count
  }
}

/// Temporary storage of ClusterSpots to match with returned.
/// hits from the Call Parser
actor SpotCache {
  var spots: [ClusterSpot] = []

  /// Add a ClusterSpot to the cache.
  /// - Parameter spot: ClusterSpot
  func addSpot(spot: ClusterSpot) {
    spots.append(spot)
  }

  /// Remove a ClusterSpot by id.
  /// - Parameter spotId: Int
  func removeSpot(spotId: Int) {
    spots = spots.filter({$0.id != spotId})
  }

  /// Retrieve a single spot from the cache
  /// - Parameter spotId: Int
  /// - Returns: ClusterSpot
  func retrieveSpot(spotId: Int) -> ClusterSpot {
    if spots.contains(where: {$0.id == spotId}) {
      return spots.filter({$0.id == spotId}).first!
    }

    return ClusterSpot()
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
