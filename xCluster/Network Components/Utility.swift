//
//  Utility.swift
//  xCluster
//
//  Created by Peter Bourget on 7/8/20.
//  Copyright © 2020 Peter Bourget. All rights reserved.
//

import Cocoa
import os

// https://www.hackingwithswift.com/example-code/strings/how-to-remove-a-prefix-from-a-string
extension String {
  func condenseWhitespace() -> String {
    let components = self.components(separatedBy: .whitespacesAndNewlines)
    return components.filter { !$0.isEmpty }.joined(separator: " ")
  }

  func deletingPrefix(_ prefix: String) -> String {
    guard self.hasPrefix(prefix) else { return self }
    return String(self.dropFirst(prefix.count))
  }

  func deletingSuffix(_ suffix: String) -> String {
    guard self.hasSuffix(suffix) else { return self }
    return String(self.dropLast(suffix.count))
  }

  func stringBefore(_ delimiter: Character) -> String {
    if let index = firstIndex(of: delimiter) {
      return String(prefix(upTo: index))
    } else {
      return ""
    }
  }

  func stringAfter(_ delimiter: Character) -> String {
    if let index = firstIndex(of: delimiter) {
      return String(suffix(from: index).dropFirst())
    } else {
      return ""
    }
  }

  func isAlphanumeric() -> Bool {
    return self.rangeOfCharacter(from: CharacterSet.alphanumerics.inverted) == nil && self.isEmpty
  }

  func isNumeric() -> Bool {
    return self.rangeOfCharacter(from: CharacterSet.decimalDigits) == nil && self.isEmpty
  }
}

extension String {
  func components(withMaxLength length: Int) -> [String] {
    return stride(from: 0, to: self.count, by: length).map {
      let start = self.index(self.startIndex, offsetBy: $0)
      let end = self.index(start, offsetBy: length, limitedBy: self.endIndex) ?? self.endIndex
      return String(self[start..<end])
    }
  }
}

// https://stackoverflow.com/questions/32305891/index-of-a-substring-in-a-string-with-swift
extension StringProtocol {

  // test if double, float, int
  // example: guard (callSignDictionary["lat"]!.double != nil) else {
  var double: Double? { Double(self) }
  var float: Float? { Float(self) }
  var integer: Int? { Int(self) }
  // ----------------------------

  func index<S: StringProtocol>(of string: S, options: String.CompareOptions = []) -> Index? {
    range(of: string, options: options)?.lowerBound
  }
  func endIndex<S: StringProtocol>(of string: S, options: String.CompareOptions = []) -> Index? {
    range(of: string, options: options)?.upperBound
  }
  func indices<S: StringProtocol>(of string: S, options: String.CompareOptions = []) -> [Index] {
    ranges(of: string, options: options).map(\.lowerBound)
  }
  func ranges<S: StringProtocol>(of string: S, options: String.CompareOptions = []) -> [Range<Index>] {
    var result: [Range<Index>] = []
    var startIndex = self.startIndex
    while startIndex < endIndex,
          let range = self[startIndex...]
            .range(of: string, options: options) {
      result.append(range)
      startIndex = range.lowerBound < range.upperBound ? range.upperBound :
      index(range.lowerBound, offsetBy: 1, limitedBy: endIndex) ?? endIndex
    }
    return result
  }
}

// find all items in an array that match a given predicate
// https://learnappmaking.com/find-item-in-array-swift/#finding-all-items-in-an-array-with-allwhere
//extension Array where Element: Equatable {
//    func all(where predicate: (Element) -> Bool) -> [Element]  {
//        return self.compactMap { predicate($0) ? $0 : nil }
//    }
//}

// round a Float to a number of digits
// let x = Float(0.123456789).roundTo(places: 4)
// https://www.uraimo.com/swiftbites/rounding-doubles-to-specific-decimal-places/
extension Float {
  func roundTo(places: Int) -> Float {
    let divisor = pow(10.0, Float(places))
    return (self * divisor).rounded() / divisor
  }
}

// https://stackoverflow.com/questions/25738817/removing-duplicate-elements-from-an-array-in-swift
// [1,2,4,2,1].uniqued()  // => [1,2,4]
extension Sequence where Element: Hashable {
    func uniqued() -> [Element] {
        var set = Set<Element>()
        return filter { set.insert($0).inserted }
    }
}

/// Type of command sent to the cluster server.
enum CommandType: String {
  case announce = "Announcement"
  case callsign = "Callsign"
  case connect = "Connect"
  case error = "Error"
  case ignore = "A reset so unsolicited messages don't get processed incorrectly"
  case logon = "Logon"
  case getDxSpots = "Show Spots"
  case yes = "Yes"
  case message = "Message to send"
  case keepAlive = "Keep alive"
  case refreshWeb = "Web Refresh"
  case setQth = "Your QTH"

  case none = ""
  case show20 = "show/fdx 20"
  case show50 = "show/fdx 50"
  case clear = "Clear"
}

/// Unify message nouns going to the view controller
enum NetworkMessage: String {
  case announcement = "Announcement"
  case cancelled = "Cancelled"
  case clusterType = "Cluster Type"
  case connected = "Connected"
  case disconnected = "Disconnected"
  case error = "Error"
  case clusterInformation = "Cluster information received"
  case invalid = "Invalid command"
  case loginRequested = "Logon message received"
  case loginCompleted = "Logon complete"
  case showDxSpots = "Show DX received"
  case spotReceived = "Spot received"
  case htmlSpotReceived = "HTML Spot received"
  case waiting = "Waiting"
  case callSignRequested = "Your call"
  case qthRequested = "Your QTH"
  case nameRequested = "Your name"
  case location = "Your grid"
}

//enum QRZManagerMessage: String {
//  case session = "Session key available"
//  case qrzInformation = "Call sign information"
//}

enum ClusterType: String {
  case arCluster = "AR-Cluster"
  case ccCluster = "CC-Cluster"
  case dxSpider = "DXSpider"
  case ve7cc = "VE7CC"
  case html = "HTML"
  case unknown = "Unknown"
}

enum SpotError: Error {
  case spotError(String)
}

// move to utility ??
enum BandFilterState: Int {
  case isOn = 1
  case isOff = 0
}

enum ModeFilterState: Int {
  case isOn = 1
  case isOff = 0
}

enum RequestError: Error {
  case invalidCallSign
  case invalidLatitude
  case invalidLongitude
  case invalidParameter
  case lookupIsEmpty
  case duplicateSpot
}

// MARK: - QRZ Structs ----------------------------------------------------------------------------

/**
 Structure to return information from QRZ.com.
 - parameters:
 */
/// Structure to return information from a call lookup.
struct StationInformation: Identifiable {
  var id = 0 //UUID()
  var call = ""
  var aliases = ""
  var country = ""
  var latitude: Double = 00
  var longitude: Double = 00
  var grid = ""
  var lotw = false
  var error = false
  var isInitialized = false
  var position = 0
}

/// StationInformation combined for the spotter and dx call.
struct StationInformationCombined: Codable {
  var spotterCall = ""
  var spotterCountry = ""
  var spotterLatitude: Double = 00
  var spotterLongitude: Double = 00
  var spotterGrid = ""
  var spotterLotw = false

  var dxCall = ""
  var dxCountry = ""
  var dxLatitude: Double = 00
  var dxLongitude: Double = 00
  var dxGrid = ""
  var dxLotw = false

  var error = false
  var identifier = "0"
  var expired = false

  var mode = ""

  var spotId = UUID()

  var dateTime = "" // make this UTC

  init() {
    setDateTimeUTC()
  }

  /// Set the UTC time the object was created "2021-04-10T22:03:59Z"
  mutating func setDateTimeUTC() {
    // The default timeZone for ISO8601DateFormatter is UTC
    let utcISODateFormatter = ISO8601DateFormatter()

    let date = Date()
    dateTime = utcISODateFormatter.string(from: date)
  }

} // end
