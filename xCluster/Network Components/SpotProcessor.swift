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
  func processSpot(rawSpot: String) throws -> ClusterSpot {

    var spot = ClusterSpot(id: UUID().uuidString, dxStation: "", frequency: "", band: 99, spotter: "",
                           timeUTC: "", comment: "", grid: "")

    if rawSpot.count < 75 {
      print("\(rawSpot.count) -- \(rawSpot)")
      throw SpotError.spotError("processRawSpot: spot length too short")
    }

    let spotter = rawSpot.components(separatedBy: ":")
    // replacing -# for AE5E - don't know why he does that "W6OP-#" and "W6OP-2-#"
    spot.spotter =  convertStringSliceToString(spotter[0].components(separatedBy: " ")[2])
    if spot.spotter.contains("-") {
      let index = spot.spotter.firstIndex(of: "-")
      let startIndex = spot.spotter.startIndex
      spot.spotter = convertStringSliceToString(String(spot.spotter[startIndex..<index!])).condenseWhitespace()
    }

    // now just remove the first part of the string

    var startIndex = rawSpot.index(rawSpot.startIndex, offsetBy: 16)
    var endIndex = rawSpot.index(startIndex, offsetBy: 9)
    let frequency = convertStringSliceToString(String(rawSpot[startIndex..<endIndex])).condenseWhitespace()
    guard Float(frequency) != nil else {
      throw SpotError.spotError("processRawSpot: unable to parse frequency")
    }
    spot.frequency = convertFrequencyToDecimalString(frequency: frequency)

    startIndex = rawSpot.index(rawSpot.startIndex, offsetBy: 26)
    endIndex = rawSpot.index(startIndex, offsetBy: 11)
    spot.dxStation = convertStringSliceToString(String(rawSpot[startIndex..<endIndex]))

    startIndex = rawSpot.index(rawSpot.startIndex, offsetBy: 39)
    endIndex = rawSpot.index(startIndex, offsetBy: 30)
    spot.comment = convertStringSliceToString(String(rawSpot[startIndex..<endIndex]))

    startIndex = rawSpot.index(rawSpot.startIndex, offsetBy: 70)
    endIndex = rawSpot.index(startIndex, offsetBy: 4)
    // clean of junk on end so it displays correctly when no grid supplied
    spot.timeUTC = convertStringSliceToString(String(rawSpot[startIndex..<endIndex])).condenseWhitespace()

    endIndex = rawSpot.endIndex
    startIndex = rawSpot.index(rawSpot.startIndex, offsetBy: 75)

    // clean of junk on end so it displays correctly
    spot.grid = convertStringSliceToString(String(rawSpot[startIndex..<endIndex])).condenseWhitespace()
    // remove /a/a at end
    spot.grid = spot.grid.components(separatedBy: CharacterSet.alphanumerics.inverted)
      .joined()

    return spot
  }

  /// Process a telnet packet from a show/dx command.
  /// DEPRECATED:
  /// now use real or rt - Format the output the same as for real time spots.
  /// An alias of SHOW/FDX is available.
  /// - Parameter rawSpot: the string received via telnet.
  /// - Throws: spot error
  /// - Returns: ClusterSpot
//  func processShowDxSpot(rawSpot: String) throws ->  ClusterSpot {
//
//    var spot = ClusterSpot(id: 0, dxStation: "", frequency: "", band: 99, spotter: "", timeUTC: "", comment: "", grid: "")
//
//    if rawSpot.count < 65 {
//      print("\(rawSpot.count) -- \(rawSpot)")
//      throw SpotError.spotError("processRawShowDxSpot: spot length too short")
//    }
//
//    // grab the frequency off the front so we can get exact lengths
//    let beginning = rawSpot.components(separatedBy: " ").first
//    var startIndex = rawSpot.index(rawSpot.startIndex, offsetBy: beginning!.count + 1)
//    var endIndex = rawSpot.endIndex
//    let balance = convertStringSliceToString(String(rawSpot[startIndex..<endIndex])
//                                              .trimmingCharacters(in: .whitespaces))
//
//    let frequency = convertStringSliceToString(beginning!).condenseWhitespace()
//    // first see if the first chunk is numeric (frequency) otherwise it is a status message, probably all spots have arrived
//    guard Float(frequency) != nil else {
//      print(frequency)
//      throw SpotError.spotError("processRawShowDxSpot: unable to parse frequency")
//    }
//    spot.frequency = convertFrequencyToDecimalString(frequency: frequency)
//
//    startIndex = balance.startIndex
//    endIndex = balance.index(startIndex, offsetBy: 12)
//    spot.dxStation = convertStringSliceToString(String(balance[startIndex..<endIndex]))
//
//    startIndex = balance.index(balance.startIndex, offsetBy: 13)
//    endIndex = balance.index(startIndex, offsetBy: 17)
//    spot.timeUTC = String(balance[startIndex..<endIndex])
//
//    startIndex = balance.index(balance.startIndex, offsetBy: 30)
//    endIndex = balance.index(startIndex, offsetBy: 30)
//    spot.comment = convertStringSliceToString(String(balance[startIndex..<endIndex]))
//    spot.comment = spot.comment.replacingOccurrences(of: "<", with: "")
//
//    // clean of junk on end so it displays correctly when no grid supplied
//    startIndex = balance.index(rawSpot.startIndex, offsetBy: 60)
//    endIndex = balance.endIndex
//    spot.spotter = convertStringSliceToString(String(balance[startIndex..<endIndex])).condenseWhitespace()
//    spot.spotter = spot.spotter.replacingOccurrences(of: "<", with: "").replacingOccurrences(of: ">", with: "")
//    // replacing -# for AE5E - don't know why he does that "W6OP-#" and "W6OP-2-#"
//    if spot.spotter.contains("-") {
//      let index = spot.spotter.firstIndex(of: "-")
//      let startIndex = spot.spotter.startIndex
//      spot.spotter = convertStringSliceToString(String(spot.spotter[startIndex..<index!])).condenseWhitespace()
//    }
//
//    return spot
//  }

  /// Parse the spots from a html feed.
  /// LZ3YG       7165.0 YU1JW      TNX FOR qso 5/9 73 Lazare     1558 19 Mar
  /// - Parameter rawSpot: rawSpot
  /// - Throws: spot error
  /// - Returns: ClusterSpot
  func processHtmlSpot(rawSpot: String) throws -> ClusterSpot {

    var spot = ClusterSpot(id: UUID().uuidString, dxStation: "", frequency: "", band: 99, spotter: "",
                           timeUTC: "", comment: "", grid: "")

    // first strip first 6 chars (<html>)
    var balance = rawSpot.dropFirst(6)
    var endIndex = balance.endIndex

    spot.spotter = balance.components(separatedBy: " ").first!

    balance = balance.dropFirst(11)
    endIndex = balance.index(balance.startIndex, offsetBy: 8)
    let frequency = convertStringSliceToString(String(balance[balance.startIndex..<endIndex]))
    guard Float(frequency) != nil else {
      print(frequency)
      throw SpotError.spotError("processRawShowDxSpot: unable to parse frequency")
    }
    spot.frequency = convertFrequencyToDecimalString(frequency: frequency)

    balance = balance.dropFirst(8)
    endIndex = balance.index(balance.startIndex, offsetBy: 10)

    spot.dxStation = convertStringSliceToString(String(balance[balance.startIndex..<endIndex]))

    balance = balance.dropFirst(11)
    endIndex = balance.index(balance.startIndex, offsetBy: 30)

    spot.comment = convertStringSliceToString(String(balance[balance.startIndex..<endIndex]))

    balance = balance.dropFirst(30)
    endIndex = balance.index(balance.startIndex, offsetBy: 4)

    spot.timeUTC = convertStringSliceToString(String(balance[balance.startIndex..<endIndex]))

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

} // end class
