//
//  Spot Processor.swift
//  xCluster
//
//  Created by Peter Bourget on 7/8/20.
//  Copyright © 2020 Peter Bourget. All rights reserved.
//

// Take a raw spot and break it into its component parts

import Foundation

class SpotProcessor {

  init() {

  }

  //      12 chars
  // DX de LY3AB:     1887.0  LY2RJ        cq cq cq                       1743Z KO25

  /// Process a telnet packet.
  /// - Parameter rawSpot: the string received via telnet.
  /// - Throws: spot error
  /// - Returns: ClusterSpot
//  func processSpot(rawSpot: String) throws -> ClusterSpot {
//
//    var spot = ClusterSpot(id: 0, dxStation: "", frequency: "", band: 99, spotter: "",
//                           timeUTC: "", comment: "", grid: "", country: "", isFiltered: false)
//
//    if rawSpot.count < 75 {
//      print("\(rawSpot.count) -- \(rawSpot)")
//      throw SpotError.spotError("processRawSpot: spot length too short")
//    }
//
//    let component = rawSpot.components(separatedBy: ":")
//    // replacing -# for AE5E - don't know why he does that "W6OP-#" and "W6OP-2-#"
//    spot.spotter =  convertStringSliceToString(component[0].components(separatedBy: " ")[2])
//    spot.spotter = cleanCallSign(callSign: spot.spotter)
//
//    if spot.spotter.filter({ $0.isLetter }).isEmpty ||
//        spot.spotter.filter({ $0.isNumber }).isEmpty {
//      throw SpotError.spotError("processRawSpot: invalid spotter call sign: \(spot.dxStation)")
//    }
//
//    var startIndex = rawSpot.index(rawSpot.startIndex, offsetBy: 16)
//    var endIndex = rawSpot.index(startIndex, offsetBy: 9)
//    let frequency = convertStringSliceToString(String(rawSpot[startIndex..<endIndex])).condenseWhitespace()
//    guard Float(frequency) != nil else {
//      throw SpotError.spotError("processRawSpot: unable to parse frequency")
//    }
//    spot.frequency = convertFrequencyToDecimalString(frequency: frequency)
//
//    startIndex = rawSpot.index(rawSpot.startIndex, offsetBy: 26)
//    endIndex = rawSpot.index(startIndex, offsetBy: 11)
//    spot.dxStation = convertStringSliceToString(String(rawSpot[startIndex..<endIndex]))
//    spot.dxStation = cleanCallSign(callSign: spot.dxStation)
//
//    if spot.dxStation.filter({ $0.isLetter }).isEmpty ||
//        spot.dxStation.filter({ $0.isNumber }).isEmpty {
//      throw SpotError.spotError("processRawSpot: invalid dx call sign: \(spot.dxStation)")
//    }
//
//    startIndex = rawSpot.index(rawSpot.startIndex, offsetBy: 39)
//    endIndex = rawSpot.index(startIndex, offsetBy: 30)
//    spot.comment = convertStringSliceToString(String(rawSpot[startIndex..<endIndex]))
//
//    startIndex = rawSpot.index(rawSpot.startIndex, offsetBy: 70)
//    endIndex = rawSpot.index(startIndex, offsetBy: 4)
//    // clean of junk on end so it displays correctly when no grid supplied
//    spot.timeUTC = convertStringSliceToString(String(rawSpot[startIndex..<endIndex])).condenseWhitespace()
//
//    endIndex = rawSpot.endIndex
//    startIndex = rawSpot.index(rawSpot.startIndex, offsetBy: 75)
//
//    // clean of junk on end so it displays correctly
//    spot.grid = convertStringSliceToString(String(rawSpot[startIndex..<endIndex])).condenseWhitespace()
//    // remove /a/a at end
//    spot.grid = spot.grid.components(separatedBy: CharacterSet.alphanumerics.inverted)
//      .joined()
//
//    return spot
//  }

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

  /// Parse the spots from a html feed.
  /// Telnet: -- DX de LY3AB:     1887.0  LY2RJ   cq cq cq                   1743Z KO25
  /// "          DX de OH6BG-#:    3573.0  UI4P           FT8  -10 dB  LO45" too short
  /// HTML: ---- LZ3YG            7165.0  YU1JW   TNX FOR qso 5/9 73 Lazare  1558 19 Mar
  /// - Parameter rawSpot: rawSpot
  /// - Throws: spot error
  /// - Returns: ClusterSpot
  func processRawSpot(rawSpot: String, isTelnet: Bool) throws -> ClusterSpot {

    var spot = ClusterSpot(id: 0, dxStation: "", frequency: "", band: 99, spotter: "",
                           timeUTC: "", comment: "", grid: "", country: "", isFiltered: false)


    if rawSpot.count < 75 {
      print("\(rawSpot.count) -- \(rawSpot)")
      throw SpotError.spotError("processRawSpot: spot length too short")
    }
    
    // first strip first 6 chars (<html>)
    var balance = rawSpot.dropFirst(6)
    var endIndex = balance.endIndex

    spot.spotter = balance.components(separatedBy: " ").first!.condenseWhitespace()
    spot.spotter = cleanCallSign(callSign: spot.spotter)

    if spot.spotter.filter({ $0.isLetter }).isEmpty ||
        spot.spotter.filter({ $0.isNumber }).isEmpty {
      throw SpotError.spotError("processRawSpot: invalid spotter call sign: \(spot.dxStation)")
    }

    balance = balance.dropFirst(10)
    endIndex = balance.index(balance.startIndex, offsetBy: 8)
    let frequency = convertStringSliceToString(String(balance[balance.startIndex..<endIndex]))
    guard Float(frequency) != nil else {
      print(frequency)
      throw SpotError.spotError("processRawShowDxSpot: unable to parse frequency")
    }

    spot.frequency = convertFrequencyToDecimalString(frequency: frequency)
    spot.band = convertFrequencyToBand(frequency: spot.frequency)

    balance = balance.dropFirst(9)
    endIndex = balance.index(balance.startIndex, offsetBy: 10)

    spot.dxStation = convertStringSliceToString(String(balance[balance.startIndex..<endIndex])).condenseWhitespace()

    spot.dxStation = cleanCallSign(callSign: spot.dxStation)

    if spot.dxStation.filter({ $0.isLetter }).isEmpty ||
        spot.dxStation.filter({ $0.isNumber }).isEmpty {
      throw SpotError.spotError("processRawSpot: invalid dx call sign: \(spot.dxStation)")
    }

    balance = balance.dropFirst(11) // 14
    endIndex = balance.index(balance.startIndex, offsetBy: 30)

    spot.comment = convertStringSliceToString(String(balance[balance.startIndex..<endIndex]))

    var difference = 30
    if isTelnet { difference = 34 }
    balance = balance.dropFirst(difference)
    endIndex = balance.index(balance.startIndex, offsetBy: 4)

    spot.timeUTC = convertStringSliceToString(String(balance[balance.startIndex..<endIndex]))

    // clean of junk on end so it displays correctly
//    spot.grid = convertStringSliceToString(String(rawSpot[startIndex..<endIndex])).condenseWhitespace()
//    // remove /a/a at end
//    spot.grid = spot.grid.components(separatedBy: CharacterSet.alphanumerics.inverted)
//      .joined()

    return spot
  }
  /**
   Read handler.
   - parameters:
   - s: Initialize a new string instance from a slice of a string.
   Otherwise the reference to the string will never go away.
   */
  func convertStringSliceToString(_ slice: String) -> String {
    return slice.trimmingCharacters(in: .whitespaces)
  }

  /**
   Convert the frequency (10136000) to a string with a decimal place (10136.000)
   Use an extension to String to format frequency correctly. This is used to
   display the frequency formatted in the tableview.
   */
  func convertFrequencyToDecimalString (frequency: String) -> String {

    var converted: String

    var components = frequency.trimmingCharacters(in: .whitespaces).components(separatedBy: ".")
    let frequencyString = components[0]

    if components.count == 1 {
      components.append("0")
    }

    if components[1] == "" {
      components[1] = "0"
    }

    var startIndex = frequencyString.startIndex
    var endIndex = frequencyString.endIndex

    switch frequencyString.count {
    case 8: // 24048940.0 - 2404.894.00
      startIndex = frequencyString.startIndex
      endIndex = frequencyString.index(startIndex, offsetBy: 4)
      let start = frequencyString[startIndex..<endIndex]
      startIndex = frequencyString.index(frequencyString.startIndex, offsetBy: 4)
      endIndex = frequencyString.index(startIndex, offsetBy: 3)
      let end = frequencyString[startIndex..<endIndex]
      converted = ("\(start).\(end)")
    case 7: // 1296.789.000 - "2320905."
      startIndex = frequencyString.startIndex
      endIndex = frequencyString.index(startIndex, offsetBy: 4)
      let start = frequencyString[startIndex..<endIndex]
      startIndex = frequencyString.index(frequencyString.startIndex, offsetBy: 4)
      endIndex = frequencyString.endIndex
      let end = frequencyString[startIndex..<endIndex]
      converted = ("\(start).\(end)")
    case 6: //144.234.0 432174.0
      startIndex = frequencyString.startIndex
      endIndex = frequencyString.index(startIndex, offsetBy: 3)
      let start = frequencyString[startIndex..<endIndex]
      startIndex = frequencyString.index(frequencyString.startIndex, offsetBy: 3)
      endIndex = frequencyString.endIndex
      let end = frequencyString[startIndex..<endIndex]
      converted = ("\(start).\(end)")
    case 5: // 10.113
      startIndex = frequencyString.startIndex
      endIndex = frequencyString.index(startIndex, offsetBy: 2)
      let start = frequencyString[startIndex..<endIndex]
      startIndex = frequencyString.index(frequencyString.startIndex, offsetBy: 2)
      endIndex = frequencyString.endIndex
      let end = frequencyString[startIndex..<endIndex]
      converted = ("\(start).\(end)")
    case 4: // 3.563.0
      startIndex = frequencyString.startIndex
      endIndex = frequencyString.index(startIndex, offsetBy: 1)
      let start = frequencyString[startIndex..<endIndex]
      startIndex = frequencyString.index(frequencyString.startIndex, offsetBy: 1)
      endIndex = frequencyString.endIndex
      let end = frequencyString[startIndex..<endIndex]
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
  /// - Parameter frequency: string describing a frequency
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
