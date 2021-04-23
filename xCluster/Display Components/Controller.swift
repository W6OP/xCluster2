//
//  Controller.swift
//  xCluster
//
//  Created by Peter Bourget on 3/13/21.
//

import Cocoa
import Foundation
import SwiftUI
import MapKit
import Combine
import os

// MARK: - ClusterSpots

struct ClusterSpot: Identifiable, Hashable {
  var id: String
  var dxStation: String
  var frequency: String
  var band: Int
  var spotter: String
  var timeUTC: String
  var comment: String
  var grid: String
  var isFiltered: Bool
  var overlay: MKPolyline!
  var qrzInfoCombinedJSON = ""

  /// Build the line (overlay) to display on the map.
  /// - Parameter qrzInfoCombined: combined data of a pair of call signs - QRZ information.
  mutating func createOverlay(qrzInfoCombined: QRZInfoCombined) {
    let locations = [
      CLLocationCoordinate2D(latitude: qrzInfoCombined.spotterLatitude, longitude: qrzInfoCombined.spotterLongitude),
      CLLocationCoordinate2D(latitude: qrzInfoCombined.dxLatitude, longitude: qrzInfoCombined.dxLongitude)]

    let polyline = MKGeodesicPolyline(coordinates: locations, count: locations.count)
    polyline.title = String(qrzInfoCombined.band)
    polyline.subtitle = ""

    self.overlay = polyline
  }
}

struct ConnectedCluster: Identifiable, Hashable {
  var id: Int
  var clusterAddress: String
  var clusterType: ClusterType
}

// MARK: - Controller Class

// Good read on clusters
// https://www.hamradiodeluxe.com/blog/Ham-Radio-Deluxe-Newsletter-April-19-2018--Understanding-DX-Clusters.html

/// Stub between view and all other classes
public class  Controller: ObservableObject, TelnetManagerDelegate, QRZManagerDelegate {

  private let concurrentSpotProcessorQueue =
    DispatchQueue(
      label: "com.w6op.virtualcluster.spotProcessorQueue",
      attributes: .concurrent)

  //static let modelLog = OSLog(subsystem: "com.w6op.Controller", category: "Model")
  let logger = Logger(subsystem: "com.w6op.xCluster", category: "Controller")

  // MARK: - Published Properties

  @Published var spots = [ClusterSpot]()
  @Published var statusMessage = [String]()
  @Published var haveSessionKey = false
  @Published var overlays = [MKPolyline]()

  @Published var bandFilter = (id: 0, state: false) {
    didSet {
      setBandButtons(band: bandFilter.id, state: bandFilter.state)
    }
  }

  @Published var connectedCluster = ClusterIdentifier(id: 9999,
                                                      name: "Select DX Spider Node",
                                                      address: "", port: "", clusterProtocol: ClusterProtocol.none) {
    didSet {
      print("controller id: \(connectedCluster.id), name: \(connectedCluster.name)")
      if !connectedCluster.address.isEmpty {
        connect(cluster: connectedCluster)
      }
    }
  }

  @Published var clusterCommand = (tag: 0, command: "") {
    didSet {
      sendClusterCommand(tag: clusterCommand.tag, command: clusterCommand.command)
    }
  }

  // MARK: - Private Properties

  var qrzManager = QRZManager()
  var telnetManager = TelnetManager()
  var spotProcessor = SpotProcessor()

  let callSign = UserDefaults.standard.string(forKey: "callsign") ?? ""
  let fullName = UserDefaults.standard.string(forKey: "fullname") ?? ""
  let location = UserDefaults.standard.string(forKey: "location") ?? ""
  let grid = UserDefaults.standard.string(forKey: "grid") ?? ""
  let qrzUserName = UserDefaults.standard.string(forKey: "username") ?? ""
  let qrzPassword = UserDefaults.standard.string(forKey: "password") ?? ""

  // mapping
  let maxNumberOfSpots = 20
  let regionRadius: CLLocationDistance = 10000000
  let centerLatitude = 28.282778
  let centerLongitude = -40.829444
  let keepAliveInterval = 300 // 5 minutes
  let dxSummitRefreshInterval = 60 // 1 minute

  let standardStrokeColor = NSColor.blue
  let ft8StrokeColor = NSColor.red
  let lineWidth: Float = 5.0 //1.0

  weak var keepAliveTimer: Timer!
  weak var webRefreshTimer: Timer!

//  var bandFilters = [99: 99, 160: 160, 80: 80, 60: 60, 40: 40, 30: 30, 20: 20, 17: 17, 15: 15, 12: 12, 10: 10, 6: 6]

  var spotFilter = ""
  var lastSpotReceivedTime = Date()

  // MARK: - Initialization

  init () {

    telnetManager.telnetManagerDelegate = self
    qrzManager.qrZedManagerDelegate = self

    keepAliveTimer = Timer.scheduledTimer(timeInterval: TimeInterval(keepAliveInterval),
                     target: self, selector: #selector(tickleServer), userInfo: nil, repeats: true)

    webRefreshTimer = Timer.scheduledTimer(timeInterval: TimeInterval(dxSummitRefreshInterval),
                    target: self, selector: #selector(refreshWeb), userInfo: nil, repeats: true)

    getQRZSessionKey()
  }

  // MARK: - Protocol Delegate Implementation

  /// Connect to a cluster.
  /// - Parameter clusterName: Name of cluster to connect to.
  func  connect(cluster: ClusterIdentifier) {

    disconnect()

    logger.info("Connecting to: \(cluster.name)")
    self.telnetManager.connect(cluster: cluster)
  }

  /// Disconnect on cluster change or application termination.
  func disconnect() {
    telnetManager.disconnect()

    // clear the status message
    DispatchQueue.main.async {
      self.statusMessage = [String]()
      }
  }

  /// Reconnect when the connection drops.
  func reconnectCluster() {

    logger.info("Reconnect attempt.")
    disconnect()

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        self.reconnect()
    }
  }

   /// Telnet Manager protocol - Process a status message from the Telnet Manager.
   /// - parameters:
   /// - telnetManager: Reference to the class sending the message.
   /// - messageKey: Key associated with this message.
   /// - message: Message text.
  func telnetManagerStatusMessageReceived(_ telnetManager: TelnetManager, messageKey: TelnetManagerMessage, message: String) {

    switch messageKey {
    case .invalid:
      return

    case .loginRequested:
      self.sendLogin()

    case .loginCompleted:
      sendPersonalData()

    case .waiting:
      DispatchQueue.main.async {
        self.statusMessage.append(message)
      }

    case .disconnected:
      reconnectCluster()

    case .error:
      DispatchQueue.main.async {
        self.logger.info("Error: \(message)")
        self.statusMessage.append(message)
      }

    case .callSignRequested:
      self.sendClusterCommand(message: "\(callSign)", commandType: CommandType.logon)

    case .nameRequested:
      self.sendClusterCommand(message: "set/name \(fullName)", commandType: CommandType.callsign)

    case .qthRequested:
      self.sendClusterCommand(message: "set/qth \(location)", commandType: CommandType.setQth)

    case .location:
      self.sendClusterCommand(message: "set/qra \(grid)", commandType: CommandType.message)

    case .clusterInformation:
      DispatchQueue.main.async {
        self.statusMessage.append(message)
      }
    default:
      DispatchQueue.main.async {
        self.statusMessage.append(message)
      }
    }

    DispatchQueue.main.async {
        if self.statusMessage.count > 200 {
        self.statusMessage.removeFirst()
      }
    }
  }

   /// Telnet Manager protocol - Process information messages from the Telnet Manager
   /// - parameters:
   /// - telnetManager: Reference to the class sending the message.
   /// - messageKey: Key associated with this message.
   /// - message: Message text.
  func telnetManagerDataReceived(_ telnetManager: TelnetManager, messageKey: TelnetManagerMessage, message: String) {

    switch messageKey {
    case .clusterType:
      DispatchQueue.main.async {
        self.statusMessage.append(message.condenseWhitespace())
      }

    case .announcement:
      DispatchQueue.main.async {
        self.statusMessage.append(message.condenseWhitespace() )
      }

    case .clusterInformation:
      DispatchQueue.main.async {
        let messages = self.limitMessageLength(message: message)

        for item in messages {
          self.statusMessage.append(item)
        }
      }

    case .error:
      DispatchQueue.main.async {
        self.statusMessage.append(message)
      }

    case .spotReceived:
      DispatchQueue.main.async {
        self.parseClusterSpot(message: message, messageType: messageKey)
      }

    case.htmlSpotReceived: // DO I WANT TO DO THIS HERE??
      self.parseClusterSpot(message: message, messageType: messageKey)

    case .showDxSpots:
      DispatchQueue.main.async {
        self.parseClusterSpot(message: message, messageType: messageKey)
      }

    default:
      break
    }

    DispatchQueue.main.async {
      if self.statusMessage.count > 200 {
        self.statusMessage.removeFirst()
      }
    }
  }

  // MARK: - QRZ Implementation ----------------------------------------------------------------------------

   /// QRZ Manager protocol - Retrieve the session key from QRZ.com
   /// - parameters:
   /// - qrzManager: Reference to the class sending the message.
   /// - messageKey: Key associated with this message.
   /// - message: Message text.
  func qrzManagerDidGetSessionKey(_ qrzManager: QRZManager, messageKey: QRZManagerMessage, haveSessionKey: Bool) {
    DispatchQueue.main.async {
      self.haveSessionKey = haveSessionKey
    }
  }

  /// QRZ Manager protocol - Receive the call sign data QRZ.com.
  /// - Parameters:
  ///   - qrzManager: Reference to the class sending the message.
  ///   - messageKey: Key associated with this message.
  ///   - qrzInfoCombined: Message text.
  ///   - spot: Associated Cluster spot.
  func qrzManagerDidGetCallSignData(_ qrzManager: QRZManager, messageKey: QRZManagerMessage, qrzInfoCombined: QRZInfoCombined, spot: ClusterSpot) {

    // need to make spot mutable
    var spot = spot
    spot.createOverlay(qrzInfoCombined: qrzInfoCombined)
    // don't know if I still need this
    //    spot.qrzInfoCombinedJSON = buildJSONString(qrzInfoCombined: qrzInfoCombined)

    DispatchQueue.main.async { [self] in
      spots.insert(spot, at: 0)
      if !spot.isFiltered {
        overlays.append(spot.overlay)
      }

      if spots.count > maxNumberOfSpots {
        spots.removeLast()
        overlays.remove(at: overlays.count - 1)
      }
    }
  }


  /// Get the session key from QRZ.com
  func getQRZSessionKey() {
    logger.info("Get session key.")
    self.qrzManager.requestSessionKey(name: self.qrzUserName, password: self.qrzPassword)
  }

  // MARK: - Cluster Login and Commands

  /// Send the operators call sign to the telnet server.
  func sendLogin() {
    sendClusterCommand(message: qrzUserName, commandType: .logon)
  }

  /// Send the users personal data to the telnet server.
  func sendPersonalData() {
    sendClusterCommand(message: "set/name \(fullName)", commandType: .ignore)
    sendClusterCommand(message: "set/qth \(location)", commandType: .ignore)
    sendClusterCommand(message: "set/qra \(grid)", commandType: .ignore)
    sendClusterCommand(message: "set/ft8", commandType: .ignore)
  }

  /// Send a message or command to the telnet manager.
  /// - Parameters:
  ///   - message: The data sent.
  ///   - commandType: The type of command sent.
  func sendClusterCommand (message: String, commandType: CommandType) {
    telnetManager.send(message, commandType: commandType)
  }

  /// Send a message or command to the telnet manager.
  /// - Parameters:
  ///   - tag: The tag value from the button to identify what command needs to be sent.
  ///   - command: The type of command sent.
  func sendClusterCommand(tag: Int, command: String) {
    switch tag {
    case 20:
      if connectedCluster.clusterProtocol == ClusterProtocol.html {
        telnetManager.createHttpSession(host: connectedCluster)
      } else {
        telnetManager.send("show/fdx 20", commandType: .getDxSpots)
      }
    case 50:
      if connectedCluster.clusterProtocol == ClusterProtocol.html {
        connectedCluster.address = connectedCluster.address.replacingOccurrences(of: "25", with: "50")
        telnetManager.createHttpSession(host: connectedCluster)
      } else {
        telnetManager.send("show/fdx 50", commandType: .getDxSpots)
      }
    default:
      telnetManager.send(command, commandType: .ignore)
    }
  }

  /// Limit the length of the received message to 80 characters.
  /// - Parameter message: Original message
  /// - Returns: Truncated message
  func limitMessageLength(message: String) -> [String] {
    var messages = [String]()

    if message.count > 80 {
      messages = message.components(withMaxLength: 80)
    } else {
      messages.append(message)
    }

    return messages
  }

  /// Parse the cluster spot message
  /// - Parameters:
  ///   - message: "DX de W3EX:      28075.6  N9AMI   1912Z FN20\a\a"
  ///   - messageType: Type of spot received.
  func parseClusterSpot(message: String, messageType: TelnetManagerMessage) {

    do {
      var spot = ClusterSpot(id: UUID().uuidString, dxStation: "", frequency: "", band: 99, spotter: "",
                             timeUTC: "", comment: "", grid: "", isFiltered: false)

      switch messageType {
      // Deprecated
      // case .showDxSpots:
      // spot = try self.spotProcessor.processShowDxSpot(rawSpot: message)
      case .spotReceived:
        spot = try self.spotProcessor.processSpot(rawSpot: message)
      case .htmlSpotReceived:
        spot = try self.spotProcessor.processHtmlSpot(rawSpot: message)
      default:
        return
      }

      lastSpotReceivedTime = Date()

      // GUARD
      spot.band = convertFrequencyToBand(frequency: spot.frequency)

      // if spot already exists, don't add again
      if spots.firstIndex(where: { $0.spotter == spot.spotter &&
        $0.dxStation == spot.dxStation && $0.frequency == spot.frequency
      }) != nil {
        return
      }

      if self.haveSessionKey {
        DispatchQueue.global(qos: .background).async { [weak self] in
          self!.qrzManager.getConsolidatedQRZInformation(spot: spot)
        }
      } else {
        getQRZSessionKey()
      }
    } catch {
      print("parseClusterSpot error: \(error)")
      logger.info("Controller Error: \(error as NSObject)")
      return
    }
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

  // MARK: - Filter by Time

  /// Remove spots older than 30 minutes
  /// - Parameter filterState: filter/don't filter
  func setTimeFilter(filterState: Bool) {

    // TODO: remove spots and overlays by time

    let localDateTime = Date()

    let iso8601DateFormatter = ISO8601DateFormatter()
    iso8601DateFormatter.formatOptions = [.withFullTime]
    let string = iso8601DateFormatter.string(from: localDateTime)
    //print("utc_date-->", string.prefix(5).replacingOccurrences(of: ":", with: "")) // 18:35:17Z

    // set the dxcall to "expired"
//    if filterState {
//      for overlay in overlays {
//
//      }
//    }
  }

  func getGMTTimeDate() -> Date {
    var comp: DateComponents = Calendar.current.dateComponents([.year, .month, .hour, .minute], from: Date())
     comp.calendar = Calendar.current
     comp.timeZone = TimeZone(abbreviation: "UTC")!
     return Calendar.current.date(from: comp)!
  }

  func getCurrentUTCTime() {

    let utcDateFormatter = DateFormatter()
    utcDateFormatter.dateStyle = .medium
    utcDateFormatter.timeStyle = .medium

    // The default timeZone on DateFormatter is the device’s
    // local time zone. Set timeZone to UTC to get UTC time.
    utcDateFormatter.timeZone = TimeZone(abbreviation: "UTC")

    // Printing a Date
    //let date = Date()
    //print(utcDateFormatter.string(from: date))

    // Parsing a string representing a date
    let dateString = "hmm"
    let utcDate = utcDateFormatter.date(from: dateString)

    //print("UTC: \(String(describing: utcDate))")

  }

  func localToUTC(dateStr: String) -> String? {
      let dateFormatter = DateFormatter()
      dateFormatter.dateFormat = "h:mm a"
      dateFormatter.calendar = Calendar.current
      dateFormatter.timeZone = TimeZone.current

      if let date = dateFormatter.date(from: dateStr) {
          dateFormatter.timeZone = TimeZone(abbreviation: "UTC")
          dateFormatter.dateFormat = "H:mm:ss"

          return dateFormatter.string(from: date)
      }
      return nil
  }

  func filterMapLinesByTime(callSign: String) {
      DispatchQueue.main.async {
        //self.overlays = self.overlays.filter {$0.subtitle == String(time)}
      }
  }

  // MARK: - Filter Call Signs

  /// Remove call signs that do not match the filter.
  /// - Parameter callSign: call sign to be filtered
  func setCallFilter(callSign: String) {

    if callSign.isEmpty {
      spotFilter = callSign
      regenerateOverlays()
      return
    }

    if spotFilter != callSign {
      spotFilter = callSign
      regenerateOverlays()
    } else {
      return
    }

    filterMapLinesByCall()
  }

  /// Remove overlays where the call sign does not match.
  func filterMapLinesByCall() {

    var indexes = [Int]()

    for (index, overlay) in overlays.enumerated() {
      let qrzInfoCombined = extractJSONFromString(subTitle: overlay.subtitle!)
      if qrzInfoCombined.dxCall != spotFilter {
        print("No Match: \(qrzInfoCombined.dxCall)")
        indexes.append(index)
      } else {
        print("Match: \(qrzInfoCombined.dxCall)")
      }
    }

    indexes = indexes.sorted().reversed()
    for index in indexes {
      DispatchQueue.main.async {
        self.overlays.remove(at: index)
      }
    }
  }

  /// Remove and recreate the overlays to match the current spots.
  func regenerateOverlays() {

    overlays.removeAll()

//    for spot in spots {
//      qrzManager.getConsolidatedQRZInformation(spotterCall: spot.spotter,
//                                               dxCall: spot.dxStation, frequency:
//                                                spot.frequency, spotId: spot.id)
//    }
  }

  // MARK: - Filter Bands

  /**
   Manage the band button state.
   - parameters:
   - buttonTag: the tag that identifies the button (0 == All).
   - state: the state of the button .on or .off.
   */
  func setBandButtons( band: Int, state: Bool) {

    if band == 9999 {return}

    switch state {
    case true:
      if band == 0 {
        // turn on all bands
        resetAllSpotFilters(setFilter: state)
        // add missing overlays
        filterMapLinesByBand()
        return
      }

    case false:
      if band == 0 {
        // turn off all bands
        resetAllSpotFilters(setFilter: state)
        overlays.removeAll()
        return
      }
    }

    updateSpotFilterState(band: band, setFilter: state)
    filterMapLinesByBand()
  }

  /// Update the filter state on a spot.
  /// - Parameters:
  ///   - band: band to update
  ///   - setFilter: state to set filter toggled()
  func updateSpotFilterState(band: Int, setFilter: Bool) {
    DispatchQueue.main.async { [self] in
      for (index, spot) in spots.enumerated() where spot.band == band {
            var newSpot = spot
            newSpot.isFiltered = !setFilter
            spots[index] = newSpot
      }
    }
  }

  /// Reset all the band filters to the same state.
  /// - Parameter setFilter: state to set
  func resetAllSpotFilters(setFilter: Bool) {
    DispatchQueue.main.async { [self] in
      for (index, spot) in spots.enumerated() {
            var newSpot = spot
            newSpot.isFiltered = !setFilter
            spots[index] = newSpot
      }
    }
  }

  func filterMapLinesByBand() {
    DispatchQueue.main.async { [self] in
      for spot in spots {
        if spot.isFiltered == false {
          let overlay = spot.overlay
          if !overlays.contains(overlay!) {
            overlays.append(overlay!)
          }
        } else {
          let overlay = spot.overlay
          if overlays.contains(overlay!) {
            overlays = overlays.filter { $0 != overlay }
          }
        }
      }
    }
  }

  /// Filter the spots by band
  /// - Parameter band: band
//  func filterSpotsByBand(band: Int) {
//    DispatchQueue.main.async {
//      self.spots = self.spots.filter {$0.frequency != String(band)}
//    }
//  }

  /// Remove lines that don't match a selected band.
  /// - Parameter band: band number
//  func filterMapLinesByBand(selection: Int) {
//    DispatchQueue.main.async { [self] in
//      for (_, element) in bandFilters.enumerated() {
//        if element.value == 0 {
//          overlays = overlays.filter {$0.title != String(element.key)}
//        }
//      }
//    }
//  }

//  func resetBandButtons(state: Bool) {
//    if state {
//      for band in bandData where band.id != 0 {
//          bandFilters[band.id] = band.id
//      }
//    } else {
//      self.bandFilters.removeAll()
//    }
//  }

  // MARK: - Keep Alive Timer ----------------------------------------------------------------------------

  @objc func refreshWeb() {
    sendClusterCommand(message: "", commandType: .refreshWeb)
  }

  @objc func tickleServer() {
    // if its been 5 minutes since last spot send keep alive
    if minutesBetweenDates(lastSpotReceivedTime, Date()) > 5 {
      _ = printDateTime(message: "Last spot received: \(lastSpotReceivedTime) - Time now: ")

      let backSpace = "show/time" //" " + String(UnicodeScalar(8)) //"(space)BACKSPACE"
      sendClusterCommand(message: backSpace, commandType: CommandType.keepAlive)
    }

    // if over 15 minutes, disconnect and reconnect
    if minutesBetweenDates(lastSpotReceivedTime, Date()) > 15 {
      _ = printDateTime(message: "Reconnecting - Last spot received: \(lastSpotReceivedTime) - Time now: ")

      disconnect()
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
          self.reconnect()
      }
    }
  }

  //Your function here
  func reconnect() {
    connect(cluster: connectedCluster)
  }

  /**
   Calculate the number of minutes between two dates
   https://stackoverflow.com/questions/28016578/how-can-i-parse-create-a-date-time-stamp-formatted-with-fractional-seconds-utc/28016692#28016692
   */
  func minutesBetweenDates(_ oldDate: Date, _ newDate: Date) -> CGFloat {

      //get both times since referenced date and divide by 60 to get minutes
      let newDateMinutes = newDate.timeIntervalSinceReferenceDate/60
      let oldDateMinutes = oldDate.timeIntervalSinceReferenceDate/60

      //then return the difference
      return CGFloat(newDateMinutes - oldDateMinutes)
  }

  func printDateTime(message: String) -> String {
    // *** Create date ***
    let date = Date()

    // *** create calendar object ***
    var calendar = Calendar.current

    // *** define calendar components to use as well Timezone to UTC ***
    calendar.timeZone = TimeZone(identifier: "UTC")!

    // *** Get All components from date ***
    //let components = calendar.dateComponents([.hour, .year, .minute], from: date)

    // *** Get Individual components from date ***
    let hour = calendar.component(.hour, from: date)
    let minutes = calendar.component(.minute, from: date)
    let seconds = calendar.component(.second, from: date)
    print("\(message) \(hour):\(minutes):\(seconds)")
    return "\(message) \(hour):\(minutes):\(seconds)"
  }

  // CORRECT WAY TO DO COMMENTS
  /// Returns the numeric value of the given digit represented as a Unicode scalar.
  ///
  /// - Parameters:
  ///   - digit: The Unicode scalar whose numeric value should be returned.
  ///   - radix: The radix, between 2 and 36, used to compute the numeric value.
  /// - Returns: The numeric value of the scalar.
  func numericValue(of digit: UnicodeScalar, radix: Int = 10) -> Int {
    // ...
    return 1
  }

  // MARK: - Overlays

  func centerMapOnLocation(location: CLLocation) {
    //          let coordinateRegion = MKCoordinateRegion(center: location.coordinate,
    //                                                    latitudinalMeters: REGION_RADIUS, longitudinalMeters: REGION_RADIUS)
    //clustermapView.setRegion(coordinateRegion, animated: true)
  }

  // MARK: - JSON Decode/Encode

  /*
   {"dxLatitude":32.604489999999998,"band":20,"spotterLatitude":-34.526000000000003,"spotterLongitude":-58.472700000000003,"dxGrid":"EM72go","dxLongitude":-85.482693999999995,"dxCountry":"United States","dxLotw":false,"spotterGrid":"GF05sl","spotterCall":"LU4DCW","dateTime":"2021-04-10T22:03:59Z","spotterLotw":false,"expired":false,"identifier":"0","dxCall":"W4E","error":false,"formattedFrequency":14.079999923706055,"spotterCountry":"Argentina","frequency":"14.080","mode":""}
   */

  /// Build a string to hold information from the associated spot.
  /// - Parameter info: QRZInfoCombined that built overlay.
  /// - Returns: string representation of QRZInfoCombined.
  func buildJSONString(qrzInfoCombined: QRZInfoCombined) -> String {

    let encoder = JSONEncoder()
    guard let data = try? encoder.encode(qrzInfoCombined) else { return "" }

    //print(String(data: data, encoding: .utf8) ?? "")

    return  String(data: data, encoding: .utf8) ?? ""
  }

  /// Build a QRZInfoCombined from a string.
  /// - Parameter subTitle: subtitle from overlay.
  /// - Returns: QRZInfoCombined
  func extractJSONFromString(subTitle: String) -> QRZInfoCombined {

    let decoder = JSONDecoder()

    let data = subTitle.data(using: .utf8)!
    guard let qrzInfoCombined = try? decoder.decode(QRZInfoCombined.self, from: data) else {
      return QRZInfoCombined()
    }

    return qrzInfoCombined
  }

} // end class

extension String {
    func components(withMaxLength length: Int) -> [String] {
        return stride(from: 0, to: self.count, by: length).map {
            let start = self.index(self.startIndex, offsetBy: $0)
            let end = self.index(start, offsetBy: length, limitedBy: self.endIndex) ?? self.endIndex
            return String(self[start..<end])
        }
    }
}
