//
//  Utility.swift
//  xCluster
//
//  Created by Peter Bourget on 7/8/20.
//  Copyright © 2020 Peter Bourget. All rights reserved.
//

import Cocoa
import os

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
}
// https://www.hackingwithswift.com/example-code/strings/how-to-remove-a-prefix-from-a-string
//extension String {
//    func deletingPrefix(_ prefix: String) -> String {
//        guard self.hasPrefix(prefix) else { return self }
//        return String(self.dropFirst(prefix.count))
//    }
//}
//
//extension String {
//    func deletingSuffix(_ suffix: String) -> String {
//        guard self.hasSuffix(suffix) else { return self }
//        return String(self.dropLast(suffix.count))
//    }
//}

// https://stackoverflow.com/questions/32305891/index-of-a-substring-in-a-string-with-swift
extension StringProtocol {
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

// https://stackoverflow.com/questions/31083348/parsing-xml-from-url-in-swift/31084545#31084545
extension QRZManager: XMLParserDelegate {

  //let logger = Logger(subsystem: "com.w6op.xCluster", category: "Controller")
  // initialize results structure
  func parserDidStartDocument(_ parser: XMLParser) {
    //logger.info("Parsing started.")
    results = []
  }

  // start element
  //
  // - If we're starting a "Session" create the dictionary that will hold the results
  // - If we're starting one of our dictionary keys, initialize `currentValue` (otherwise leave `nil`)
  func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String]) {

    switch elementName {
    case KeyName.sessionKeyName.rawValue:
      if sessionKey == nil {
        sessionDictionary = [:]
      } else {
        //print("didStartElement: \(elementName)")
      }
    case KeyName.recordKeyName.rawValue:
      callSignDictionary = [:]
    case KeyName.errorKeyName.rawValue:
      //logger.info("Parser error: \(elementName):\(self.currentValue)")
    break
    default:
      if callSignDictionaryKeys.contains(elementName) {
        currentValue = ""
      }
    }
  }

  // found characters
  //
  // - If this is an element we care about, append those characters.
  // - If `currentValue` still `nil`, then do nothing.
  func parser(_ parser: XMLParser, foundCharacters string: String) {
    currentValue += string
  }

  // end element
  //
  // - If we're at the end of the whole dictionary, then save that dictionary in our array
  // - If we're at the end of an element that belongs in the dictionary, then save that value in the dictionary
  func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {

    switch elementName {
    case KeyName.sessionKeyName.rawValue:
      // don't seem to need this
      //print("Here 2s - was this an error? \(elementName)")
      break
    case KeyName.recordKeyName.rawValue:
      results!.append(callSignDictionary!)
    case KeyName.errorKeyName.rawValue:
        //logger.info("didEndElement Error: \(self.currentValue)")
        callSignDictionary = [:]
        callSignDictionary[elementName] = currentValue.trimmingCharacters(in: .whitespacesAndNewlines)
      if currentValue.contains("Session Timeout") {
        // abort this and request a session key
        logger.info("Session Timed Out - abort processing")
        isSessionKeyValid = false
        parser.abortParsing()
      }
    default:
      if callSignDictionaryKeys.contains(elementName) {
          callSignDictionary[elementName] = currentValue.trimmingCharacters(in: .whitespacesAndNewlines)
      } else if sessionDictionaryKeys.contains(elementName) {
        sessionDictionary[elementName] = currentValue.trimmingCharacters(in: .whitespacesAndNewlines)
      }
      currentValue = ""
    }
  }

  func parserDidEndDocument(_ parser: XMLParser) {
      //logger.info("Parsing completed.")
  }

  // Just in case, if there's an error, report it. (We don't want to fly blind here.)
  func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
    logger.info("parser failed: \(parseError as NSObject)")
    currentValue = ""

    if !isSessionKeyValid {
      logger.info("Request a new Session Key")
      requestSessionKey(name: qrzUserName, password: qrzPassword)
    }
  }
}

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
}

/**
 Unify message nouns going to the view controller
 */
enum TelnetManagerMessage: String {
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

enum QRZManagerMessage: String {
  case session = "Session key available"
  case qrzInformation = "Call sign information"

}

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

// MARK: - QRZ Structs ----------------------------------------------------------------------------

/**
 Structure to return information from QRZ.com.
 - parameters:
 */
struct StationInformation {
  var call = ""
  var aliases = ""
  var country = ""
  var latitude: Double = 00
  var longitude: Double = 00
  var grid = ""
  var lotw = false
  var error = false
  var isInitialized = false
}

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

  var frequency = "0.0"
  var formattedFrequency: Float = 0.0
  var band = 0
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

  // need to convert 3.593.4 to 3.5934
  mutating func setFrequency(frequency: String) {
    self.frequency = frequency
    self.formattedFrequency = StationInformationCombined.formatFrequency(frequency: frequency)
    self.band = StationInformationCombined.setBand(frequency: self.formattedFrequency)
  }

  static func formatFrequency(frequency: String) -> Float {
    let components = frequency.trimmingCharacters(in: .whitespaces).components(separatedBy: ".")
    var suffix = ""

    // TRY THIS
    // frequency.trimmingCharacters(in: .whitespaces).components(separatedBy: ".")[1]
    let prefix = components[0]

    for index in 1..<components.count {
      suffix += components[index]
    }

    let result = Float(("\(prefix).\(suffix)"))?.roundTo(places: 4)

    return result ?? 0.0
  }

  static func setBand(frequency: Float) -> Int {
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
} // end
