//
//  Spot Processor.swift
//  xCluster
//
//  Created by Peter Bourget on 7/8/20.
//  Copyright © 2020 Peter Bourget. All rights reserved.
//

import Foundation

/// Take a raw spot and break it into its component parts
// swiftlint:disable cyclomatic_complexity
class SpotProcessor {

  init() {}

  /// Parse the spots from a html feed.
  /// Telnet: -- DX de LY3AB:     1887.0  LY2RJ   cq cq cq                   1743Z KO25
  /// "          DX de OH6BG-#:    3573.0  UI4P           FT8  -10 dB  LO45" too short
  /// HTML: ---- LZ3YG            7165.0  YU1JW   TNX FOR qso 5/9 73 Lazare  1558 19 Mar
  /// - Parameter rawSpot: String
  /// - Throws: SpotError
  /// - Returns: ClusterSpot
  func processRawSpot(rawSpot: String, isTelnet: Bool) throws -> ClusterSpot {
    var spot = ClusterSpot()
    spot.isInvalidSpot = false

    //  missing date
    // DX de OH6BG-#:   14074.0  DH2UN          FT8  -15 dB  JN49    CQ      1453
    if rawSpot.count < 75 {
      print("\(rawSpot.count) -- \(rawSpot)")
      throw SpotError.spotError("processRawSpot: spot length too short")
    }

    // first strip first 6 chars ("<html>" or "DX de  ")
    var balance = rawSpot.dropFirst(6)
    var endIndex = balance.endIndex

    spot.spotter = balance.components(separatedBy: " ").first!.condenseWhitespace()
    spot.spotter = cleanCallSign(callSign: spot.spotter)

    if spot.spotter.filter({ $0.isLetter }).isEmpty ||
        spot.spotter.filter({ $0.isNumber }).isEmpty {
      throw SpotError.spotError("processRawSpot: invalid spotter call sign: \(spot.dxStation)")
    }

    // "DX de HS/F8UKP-#:  18100.0  JG1JPE         FT8  -18 dB  PM96    CQ      1446Z"
    balance = balance.dropFirst(11)
    endIndex = balance.index(balance.startIndex, offsetBy: 8)
    let frequency = convertStringSliceToString(String(balance[balance.startIndex..<endIndex]))
    guard Float(frequency) != nil else {
      print("processRawSpot: \(frequency)")
      throw SpotError.spotError("processRawSpot: unable to parse \(frequency)")
    }

    spot.setFrequency(frequency: convertFrequencyToDecimalString(frequency: frequency))

    balance = balance.dropFirst(9)
    endIndex = balance.index(balance.startIndex, offsetBy: 10)

    spot.dxStation = convertStringSliceToString(String(balance[balance.startIndex..<endIndex])).condenseWhitespace()

    spot.dxStation = cleanCallSign(callSign: spot.dxStation)

    if spot.dxStation.filter({ $0.isLetter }).isEmpty ||
        spot.dxStation.filter({ $0.isNumber }).isEmpty {
      throw SpotError.spotError("processRawSpot: invalid dx call sign: \(spot.dxStation)")
    }

    balance = balance.dropFirst(11)
    endIndex = balance.index(balance.startIndex, offsetBy: 30)

    spot.comment = convertStringSliceToString(String(balance[balance.startIndex..<endIndex]))

    var difference = 30
    if isTelnet { difference = 34 }
    balance = balance.dropFirst(difference)
    endIndex = balance.index(balance.startIndex, offsetBy: 4)

    spot.timeUTC = convertStringSliceToString(String(balance[balance.startIndex..<endIndex]))

    // create the id number for the spot - this will later
    // change to the polyline hash value but need a temp id now
    // to link ClusterSpot to StationInformation
    spot.id = spot.hashValue

    return spot
  }

  /// Clean any junk out of the call sign.
  /// - Parameter callSign: String
  /// - Returns: String
  func cleanCallSign(callSign: String) -> String {
    var cleanedCall = ""

    // if there are spaces in the call don't process it
    cleanedCall = callSign.replacingOccurrences(of: " ", with: "")

    if callSign.contains(":") { // EB5KB//P
      cleanedCall = callSign.replacingOccurrences(of: ":", with: "")
    }

    // strip leading or trailing "/"  /W6OP/
    if callSign.prefix(1) == "/" {
      cleanedCall = String(callSign.suffix(callSign.count - 1))
    }

    if callSign.suffix(1) == "/" {
      cleanedCall = String(cleanedCall.prefix(cleanedCall.count - 1))
    }

    if callSign.contains("//") { // EB5KB//P
      cleanedCall = callSign.replacingOccurrences(of: "//", with: "/")
    }

    if callSign.contains("///") { // BU1H8///D
      cleanedCall = callSign.replacingOccurrences(of: "///", with: "/")
    }

    if callSign.contains("-") {
      let index = callSign.firstIndex(of: "-")
      let startIndex = callSign.startIndex
      cleanedCall = convertStringSliceToString(String(callSign[startIndex..<index!])).condenseWhitespace()
    }

    return cleanedCall
  }

  /// Initialize a new string instance from a slice of a string.
  /// Otherwise the reference to the string will never go away.
  /// - Parameter slice: String
  /// - Returns: String
  func convertStringSliceToString(_ slice: String) -> String {
    return slice.trimmingCharacters(in: .whitespaces)
  }

  /// Convert the frequency (10136000) to a string with a decimal place (10136.000)
  /// Use an extension to String to format frequency correctly. This is used to
  /// display the frequency formatted in the tableview.
  /// - Parameter frequency: String
  /// - Returns: String
  // swiftlint:disable function_body_length
  func convertFrequencyToDecimalString (frequency: String) -> String {
    var converted: String
    var components = frequency.trimmingCharacters(in: .whitespaces).components(separatedBy: ".")
    let firstComponent = components[0]

    if components.count == 1 {
      components.append("0")
    }

    if components[1] == "" {
      components[1] = "000"
    }

    var startIndex = firstComponent.startIndex
    var endIndex: String.Index  // = firstComponent.endIndex

    switch firstComponent.count {
    case 8: // 24048940.0 - 2404.894.00
      endIndex = firstComponent.index(startIndex, offsetBy: 4)
      let start = firstComponent[startIndex..<endIndex]
      startIndex = firstComponent.index(startIndex, offsetBy: 4)
      endIndex = firstComponent.index(startIndex, offsetBy: 3)
      let end = firstComponent[startIndex..<endIndex]
      converted = ("\(start).\(end)")
    case 7: // 1296.789.000 - "2320905."
      endIndex = firstComponent.index(startIndex, offsetBy: 4)
      let start = firstComponent[startIndex..<endIndex]
      startIndex = endIndex
      endIndex = firstComponent.endIndex
      let end = firstComponent[startIndex..<endIndex]
      converted = ("\(start).\(end)")
    case 6: //144.234.0 432174.0
      endIndex = firstComponent.index(startIndex, offsetBy: 3)
      let start = firstComponent[startIndex..<endIndex]
      startIndex = endIndex
      endIndex = firstComponent.endIndex
      let end = firstComponent[startIndex..<endIndex]
      converted = ("\(start).\(end)")
    case 5: // 10.113
      endIndex = firstComponent.index(startIndex, offsetBy: 2)
      let start = firstComponent[startIndex..<endIndex]
      startIndex = endIndex
      endIndex = firstComponent.endIndex
      let end = firstComponent[startIndex..<endIndex]
      converted = ("\(start).\(end)")
    case 4: // 3.563.0
      endIndex = firstComponent.index(startIndex, offsetBy: 1)
      let start = firstComponent[startIndex..<endIndex]
      startIndex = endIndex
      endIndex = firstComponent.endIndex
      let end = firstComponent[startIndex..<endIndex]
      converted = ("\(start).\(end)")
    case 3: // 707
      endIndex = firstComponent.index(startIndex, offsetBy: 2)
      let start = firstComponent[startIndex..<endIndex]
      startIndex = endIndex
      endIndex = firstComponent.endIndex
      let end = firstComponent[startIndex..<endIndex]
      converted = ("\(start).\(end)")
    default:
      return frequency
    }

    if components[1] != "0" {
      converted += (".\(components[1])")
    }

    return converted
  }

  /// Convert a frequency to a band.
  /// - Parameter frequency: String
  /// - Returns: band
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

} // end class
