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
import CallParser

// MARK: - ClusterSpots

// move to utility ??
enum BandFilterState: Int {
  case isOn = 0
  case isOff = 1
}

enum ModeFilterState: Int {
  case isOn = 0
  case isOff = 1
}

enum RequestError: Error {
  case invalidCallSign
  case invalidLatitude
  case invalidLongitude
  case invalidParameter
  case lookupIsEmpty
}

//enum ClusterCommand: String {
//  case showNone = ""
//  case show20 = "show/fdx 20"
//  case show50 = "show/fdx 50"
//}

//enum ApplicationCommand {
//  case none
//  case clear
//}

/// Definition of a ClusterSpot
struct ClusterSpot: Identifiable, Hashable {

  enum FilterReason: Int {
    case band
    case call
    case country
    case grid
    case mode
    case time
    case none
  }

  var id: Int //UUID
  //var secondaryId: Int
  var dxStation: String
  var frequency: String
  var band: Int
  var spotter: String
  var timeUTC: String
  var comment: String
  var grid: String
  var country: String
  var overlay: MKPolyline!
  var qrzInfoCombinedJSON = ""
  var filterReasons = [FilterReason]()
  var isInvalidSpot = false
  var overlayExists = false

  private(set) var isFiltered: Bool

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
    polyline.title = String(stationInfoCombined.band)
    polyline.subtitle = stationInfoCombined.mode
    //polyline.subtitle = String(id)

    // THIS IS WHY IT DOESN'T WORK - I NEED ID BEFORE THIS HAPPENS
    id = polyline.hashValue

    self.overlay = polyline
  }

  /// Set a specific filter.
  /// - Parameter filterReason: FilterReason
  mutating func setFilter(reason: FilterReason) {
    self.filterReasons.append(reason)
    self.isFiltered = true
  }

  /// Reset a specific filter.
  /// - Parameter filterReason: FilterReason
  mutating func resetFilter(reason: FilterReason) {

    if filterReasons.contains(reason) {
      let index = filterReasons.firstIndex(of: reason)!
      self.filterReasons.remove(at: index)
    }

    if self.filterReasons.isEmpty {
      self.isFiltered = false
    }
  }

  /// Reset the filter state of all of a certain type
  /// - Parameter filterReason: FilterReason
  mutating func resetAllFiltersOfType(reason: FilterReason) {
    self.filterReasons.removeAll { value in
      return value == reason
    }

    if self.filterReasons.isEmpty {
      self.isFiltered = false
    }
  }
}

/// Metadata of the currently connected host
struct ConnectedCluster: Identifiable, Hashable {
  var id: Int
  var clusterAddress: String
  var clusterType: ClusterType
}

// MARK: - Actors

/// Array of Station Information
actor StationInformationPairs {
  var callSignPairs = [Int: [StationInformation]]()

  private func add(spotId: Int, stationInformation: StationInformation) -> [StationInformation] {

    var callSignPair: [StationInformation] = []
    callSignPair.append(stationInformation)
    callSignPairs[spotId] = callSignPair

    return callSignPair
  }

  func checkCallSignPair(spotId: Int, stationInformation: StationInformation) -> [StationInformation] {
    var callSignPair: [StationInformation] = []

    if callSignPairs[spotId] != nil {
      callSignPair = updateCallSignPair(spotId: spotId, stationInformation: stationInformation)
    } else {
      callSignPair = add(spotId: spotId, stationInformation: stationInformation)
    }
    return callSignPair
  }

  private func updateCallSignPair(spotId: Int, stationInformation: StationInformation) -> [StationInformation] {

    var callSignPair: [StationInformation] = []

    if callSignPairs[spotId] != nil {
      callSignPair = callSignPairs[spotId]!
      callSignPair.append(stationInformation)
      return callSignPair
    }

    return callSignPair
  }

  func clear() {
    callSignPairs.removeAll()
  }
} // end actor

actor HitPair {
  var hits: [Hit] = []

  func clear() {
    hits.removeAll()
  }

  func addHit(hit: Hit) {
    hits.append(hit)
  }
}

// MARK: - Controller Class

// Good read on clusters
// https://www.hamradiodeluxe.com/blog/Ham-Radio-Deluxe-Newsletter-April-19-2018--Understanding-DX-Clusters.html

/// Stub between view and all other classes
public class  Controller: ObservableObject, TelnetManagerDelegate, WebManagerDelegate {

  let logger = Logger(subsystem: "com.w6op.xCluster", category: "Controller")

  // MARK: - Published Properties

  @Published var displayedSpots = [ClusterSpot]()
  @Published var statusMessage = [String]()
  @Published var overlays = [MKPolyline]()

  @Published var bandFilter = (id: 0, state: false) {
    didSet {
      setBandButtons(band: bandFilter.id, state: bandFilter.state)
    }
  }

  @Published var modeFilter = (id: 0, state: false) {
    didSet {
      setModeButtons(mode: modeFilter.id, state: modeFilter.state)
    }
  }

  @Published var connectedCluster = ClusterIdentifier(id: 9999,
                                                      name: "Select DX Spider Node",
                                                      address: "",
                                                      port: "",
                                                      clusterProtocol:
                                                        ClusterProtocol.none) {
    didSet {
      print("controller id: \(connectedCluster.id), name: \(connectedCluster.name)")
      if !connectedCluster.address.isEmpty {
        connect(cluster: connectedCluster)
      }
    }
  }

  @Published var selectedNumberOfSpots = SpotsIdentifier(id: 25,
                                                         maxLines: 25,
                                                         displayedLines: "25") {
    didSet {
      print("selectedNumberOfLines id: \(selectedNumberOfSpots.id), name: \(selectedNumberOfSpots.displayedLines)")
      maxNumberOfSpots = selectedNumberOfSpots.maxLines
      Task {
        await manageSpots(spot: nil, doInsert: false)
      }
    }
  }

  @Published var clusterMessage = CommandType.none {
    didSet {
      sendClusterCommand(command: clusterMessage)
    }
  }

  @Published var applicationMessage = CommandType.none {
    didSet {
      sendApplicationCommand(command: applicationMessage)
    }
  }

  // MARK: - Private Properties

  var telnetManager = TelnetManager()
  var spotProcessor = SpotProcessor()
  var webManager = WebManager()

  // Call Parser
  let callParser = PrefixFileParser()
  var callLookup = CallLookup()

  var callSignLookup: [String: String] = ["call": "", "country": "", "lat": "", "lon": "", "grid": "", "lotw": "0", "aliases": "", "Error": ""]

  let callSign = UserDefaults.standard.string(forKey: "callsign") ?? ""
  let fullName = UserDefaults.standard.string(forKey: "fullname") ?? ""
  let location = UserDefaults.standard.string(forKey: "location") ?? ""
  let grid = UserDefaults.standard.string(forKey: "grid") ?? ""
  let qrzUserName = UserDefaults.standard.string(forKey: "username") ?? ""
  let qrzPassword = UserDefaults.standard.string(forKey: "password") ?? ""

  // mapping
  var maxNumberOfSpots = 100
  let regionRadius: CLLocationDistance = 10000000
  let centerLatitude = 28.282778
  let centerLongitude = -40.829444
  let keepAliveInterval = 300 // 5 minutes
  let dxSummitRefreshInterval = 60 // 1 minute

  weak var keepAliveTimer: Timer!
  weak var webRefreshTimer: Timer!

  var bandFilters = [0: BandFilterState.isOff, 160: BandFilterState.isOff,
                     80: BandFilterState.isOff, 60: BandFilterState.isOff, 40: BandFilterState.isOff,
                     30: BandFilterState.isOff, 20: BandFilterState.isOff, 17: BandFilterState.isOff,
                     15: BandFilterState.isOff, 12: BandFilterState.isOff, 10: BandFilterState.isOff,
                     6: BandFilterState.isOff]

  var modeFilters = [ 1: ModeFilterState.isOff, 2: ModeFilterState.isOff, 3: ModeFilterState.isOff]

  var callFilter = ""

  var lastSpotReceivedTime = Date()

  // MARK: - Initialization

  init () {

    telnetManager.telnetManagerDelegate = self
    webManager.webManagerDelegate = self

    // initialize the Call Parser
    callLookup = CallLookup(prefixFileParser: callParser)

    keepAliveTimer = Timer.scheduledTimer(timeInterval: TimeInterval(keepAliveInterval),
                                          target: self, selector: #selector(tickleServer), userInfo: nil, repeats: true)

    webRefreshTimer = Timer.scheduledTimer(timeInterval: TimeInterval(dxSummitRefreshInterval),
                                           target: self, selector: #selector(refreshWeb), userInfo: nil, repeats: true)
  }

  // MARK: - Connect and Disconnect

  /// Connect to a specified cluster. If already connected then
  /// disconnect from the connected cluster first.
  /// - Parameter clusterName: String
  func  connect(cluster: ClusterIdentifier) {

    if connectedCluster.id != 9999 {
      disconnect()

      overlays.removeAll()
      displayedSpots.removeAll()
      bandFilters.keys.forEach { bandFilters[$0] = .isOff }

      logger.info("Connecting to: \(cluster.name)")

      if cluster.clusterProtocol == ClusterProtocol.html {
        Task {
          await webManager.connectAsync(cluster: connectedCluster)
        }
      } else {
        telnetManager.connect(cluster: cluster)
      }
    }
  }

  /// Disconnect on cluster change or application termination.
  /// Send a signal to clear the existing status message.
  func disconnect() {
    if connectedCluster.clusterProtocol == ClusterProtocol.telnet {
      telnetManager.disconnect()
    }

    // clear the status message
    DispatchQueue.main.async { [self] in
      statusMessage = [String]()
    }
  }

  /// Reconnect when the connection drops.
  func reconnectCluster() {

    logger.info("Reconnection attempt.")

    disconnect()

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [self] in
      reconnect()
    }
  }

  // MARK: - Web Data Received

  /// The WebManager has received data.
  func webManagerDataReceived(_ webManager: WebManager, messageKey: NetworkMessage, message: String) {

    switch messageKey {
    case.htmlSpotReceived:
      parseClusterSpot(message: message, messageType: messageKey)
    default:
      logger.info("Invalid message type \(messageKey.rawValue) : \(message)")
    }

    DispatchQueue.main.async { [self] in
      if statusMessage.count > maxStatusMessages {
        statusMessage.removeFirst()
      }
    }
  }

  // MARK: - Telnet Status Received

  /// Process a status message from the Telnet Manager.
  /// - parameters:
  /// - telnetManager: Reference to the class sending the message.
  /// - messageKey: Network Message
  /// - message: String
  func telnetManagerStatusMessageReceived(_ telnetManager: TelnetManager, messageKey: NetworkMessage, message: String) {

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
      if self.statusMessage.count > maxStatusMessages {
       self.statusMessage.removeFirst()
      }
    }
  }

  // MARK: - Telnet Data Received

  /// Telnet Manager protocol - Process information messages from the Telnet Manager
  /// - parameters:
  /// - telnetManager: Reference to the class sending the message.
  /// - messageKey: Network Message
  /// - message: String
  func telnetManagerDataReceived(_ telnetManager: TelnetManager, messageKey: NetworkMessage, message: String) {

    switch messageKey {
    case .clusterType:
      DispatchQueue.main.async { [self] in
        statusMessage.append(message.condenseWhitespace())
      }

    case .announcement:
      DispatchQueue.main.async { [self] in
        statusMessage.append(message.condenseWhitespace() )
      }

    case .clusterInformation:
      DispatchQueue.main.async { [self] in
        let messages = limitMessageLength(message: message)

        for item in messages {
          statusMessage.append(item)
        }
      }

    case .error:
      DispatchQueue.main.async { [self] in
        statusMessage.append(message)
      }

    case .spotReceived:
      parseClusterSpot(message: message, messageType: messageKey)

    case .showDxSpots:
      parseClusterSpot(message: message, messageType: messageKey)

    default:
      break
    }

    DispatchQueue.main.async { [self] in
      if statusMessage.count > 200 {
        statusMessage.removeFirst()
      }
    }
  }

  // MARK: - Application Commands

  func sendApplicationCommand(command: CommandType) {
    switch command {
    case .clear:
      Task {
        await MainActor.run {
        overlays.removeAll()
        displayedSpots.removeAll()
        }
      }
    default:
      break
    }
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

  /// Send a message or command to the telnet or web manager.
  /// - Parameters:
  ///   - message: String
  ///   - commandType: CommandType
  func sendClusterCommand (message: String, commandType: CommandType) {

    if commandType == .refreshWeb {
      Task {
        await webManager.connectAsync(cluster: connectedCluster)
      }
    } else {
      telnetManager.send(message, commandType: commandType)
    }
  }

  /// Send a message or command to the telnet manager.
  /// The tag value from the button identifies which command needs to be sent.
  /// - Parameters:
  ///   - tag: Int
  ///   - command: CommandType
  func sendClusterCommand(command: CommandType) {
    switch command {
    case .show20:
      if connectedCluster.clusterProtocol == ClusterProtocol.html {
        Task {
          await webManager.connectAsync(cluster: connectedCluster)
        }
      } else {
        telnetManager.send(command.rawValue, commandType: .getDxSpots)
      }
    case .show50:
      if connectedCluster.clusterProtocol == ClusterProtocol.html {
        connectedCluster.address = connectedCluster.address.replacingOccurrences(of: "25", with: "50")
        Task {
          try? await webManager.createHttpSessionAsync(host: connectedCluster)
        }
      } else {
        telnetManager.send(command.rawValue, commandType: .getDxSpots)
      }
    default:
      break
      //telnetManager.send(command, commandType: .ignore)
    }
  }

  /// Limit the length of the received message to 80 characters.
  /// - Parameter message: String
  /// - Returns: [String]
  func limitMessageLength(message: String) -> [String] {
    var messages = [String]()

    if message.count > 80 {
      messages = message.components(withMaxLength: 80)
    } else {
      messages.append(message)
    }

    return messages
  }

  // MARK: - Process Spots

  /// Parse the cluster spot message. This is where all cluster spots
  /// are first created. Handles all telnet and web spots.
  /// - Parameters:
  ///   - message: String
  ///   - messageType: NetworkMessage
  func parseClusterSpot(message: String, messageType: NetworkMessage) {

    lastSpotReceivedTime = Date()

    do {
      var spot = ClusterSpot(id: 0, dxStation: "", frequency: "", band: 99, spotter: "",
                             timeUTC: "", comment: "", grid: "", country: "", isFiltered: false)
      switch messageType {
      case .spotReceived:
        spot = try self.spotProcessor.processRawSpot(rawSpot: message, isTelnet: true)
      case .htmlSpotReceived:
        spot = try self.spotProcessor.processRawSpot(rawSpot: message, isTelnet: false)
      default:
        return
      }

      let asyncSpot = spot
      Task {
        try await processCompletedSpotEx(spot: asyncSpot)
      }

    } catch {
      print("parseClusterSpot error: \(error)")
      logger.info("Controller Error: \(error as NSObject)")
      return
    }
  }

  /// Process the completed cluster spot.
  /// - Parameter spot: ClusterSpot
  func processCompletedSpotEx(spot: ClusterSpot) async throws {
    var spot = spot

    applyFilters(&spot)

    let spots = [spot.spotter, spot.dxStation]
    try await withThrowingTaskGroup(of: Hit.self) { [unowned self] group in
      let hitPairs = HitPair()
      for index in 0..<2 {
        group.addTask {
          do {
          return try await lookupCallSign(call: spots[index])
          } catch {
            print("Controller Error: \(error as NSObject)")
            throw (RequestError.invalidCallSign)
          }
        }
      }

      for try await hit in group {
        await hitPairs.addHit(hit: hit)
      }

      if await hitPairs.hits.count == 2 {
        await processStationInformation(hitPairs: hitPairs, spot: spot)
      } else {
        print("Failed: \(spot.spotter):\(spot.dxStation)")
        throw (RequestError.invalidCallSign)
      }
    }
  }


  /// Build the station information for both calls in the spot.
  /// - Parameters:
  ///   - hitPairs2: HitPair
  ///   - spot: ClusterSpot
  func processStationInformation(hitPairs: HitPair, spot: ClusterSpot) async {

    await withTaskGroup(of: StationInformation.self) { [unowned self] group in
      for index in 0..<2 {
        group.addTask {
          return await populateStationInformationEx(hit: hitPairs.hits[index],
                                                    spotId: spot.id)
        }
      }

      let stationInformationPairs = StationInformationPairs()
      var callSignPairs = [StationInformation]()
      for await stationInformation in group {
        callSignPairs = await stationInformationPairs.checkCallSignPair(
          spotId: spot.id, stationInformation: stationInformation)
      }

      if callSignPairs.count == 2 {
        combineHitInformation(spot: spot, callSignPair: callSignPairs)
      } else {
        // throw
      }
    }
  }

  /// Check if the incoming spot needs to be filtered.
  /// - Parameter spot: ClusterSpot
  func applyFilters(_ spot: inout ClusterSpot) {

    if bandFilters[Int(spot.band)] == .isOn {
      spot.setFilter(reason: .band)
    }

    if !callFilter.isEmpty {
      if spot.dxStation.prefix(callFilter.count) != callFilter {
        spot.setFilter(reason: .call)
      }
    }
  }

  // MARK: - Call Parser Operations


  /// Use the CallParser to get the information about the call sign.
  /// - Parameter call: String
  /// - Returns: Hit
  func lookupCallSign(call: String) async throws -> Hit {

    let hitList: [Hit] = await callLookup.lookupCall(call: call)
    if !hitList.isEmpty {
      // why just the last one?
      // should have CallParser go to QRZ if multiples
      let hit = hitList[hitList.count - 1]
      return hit
    }

    throw (RequestError.invalidCallSign)
  }

  // MARK: - Populate Station Info and Create Overlays

  /// Populate a StationInformation object with the data from the hit.
  /// - Parameters:
  ///   - hit: Hit
  ///   - spotId: Int
  /// - Returns: StationInformation
  func populateStationInformationEx(hit: Hit, spotId: Int) -> StationInformation {

    var stationInformation = StationInformation()

    logger.info("Processing stationInformation for: \(hit.call) - 2a")

    stationInformation.id = spotId
    stationInformation.call = hit.call
    stationInformation.country = hit.country

    if let latitude = Double(hit.latitude) {
      stationInformation.latitude = latitude
    }

    if let longitude = Double(hit.longitude) {
      stationInformation.longitude = longitude
    }

    stationInformation.isInitialized = true

    // debugging only
    if stationInformation.longitude == 00 || stationInformation.longitude == 00 {
      logger.info("Longitude/Lattitude error: \(stationInformation.call):\(stationInformation.country)")
    }

    return stationInformation
  }

  /// Combine the CallParser information.
  /// - Parameters:
  ///   - spot: ClusterSpot
  ///   - callSignPair: [StationInformation]
  func combineHitInformation(spot: ClusterSpot, callSignPair: [StationInformation]) {

    logger.info("combineHitInformation: \(callSignPair[0].call): \(callSignPair[1].call) - 4")

    var stationInformationCombined = StationInformationCombined()

    stationInformationCombined.setFrequency(frequency: spot.frequency)

    stationInformationCombined.spotterCall = callSignPair[0].call
    stationInformationCombined.spotterCountry = callSignPair[0].country
    stationInformationCombined.spotterLatitude = callSignPair[0].latitude
    stationInformationCombined.spotterLongitude = callSignPair[0].longitude
    stationInformationCombined.spotterGrid = callSignPair[0].grid
    stationInformationCombined.spotterLotw = callSignPair[0].lotw
    stationInformationCombined.error = callSignPair[0].error

    stationInformationCombined.dxCall = callSignPair[1].call
    stationInformationCombined.dxCountry = callSignPair[1].country
    stationInformationCombined.dxLatitude = callSignPair[1].latitude
    stationInformationCombined.dxLongitude = callSignPair[1].longitude
    stationInformationCombined.dxGrid = callSignPair[1].grid
    stationInformationCombined.dxLotw = callSignPair[1].lotw
    if !stationInformationCombined.error {
      stationInformationCombined.error = callSignPair[1].error
    }

    // used in the ListView for display
    var spot = spot
    spot.country = stationInformationCombined.dxCountry

    processCallSignData(stationInformationCombined: stationInformationCombined, spot: spot)
  }

  /// Have the spot create the overlay associated with it.
  /// - Parameters:
  ///   - stationInfoCombined: StationInformationCombined
  ///   - spot: ClusterSpot
  func processCallSignData(stationInformationCombined: StationInformationCombined, spot: ClusterSpot) {
    // need to make spot mutable
    var spot = spot

    logger.info("Create Overlay: \(stationInformationCombined.spotterCall): \(stationInformationCombined.dxCall) - 5")

    spot.createOverlay(stationInfoCombined: stationInformationCombined)

    let spot2 = spot
    Task {
      await manageSpots(spot: spot2, doInsert: true)
    }
  }

  /// Insert and delete spots and overlays.
  /// - Parameter spot: ClusterSpot
  /// - Parameter doDelete: Bool
  func manageSpots(spot: ClusterSpot?, doInsert: Bool) async {

    Task {
        await MainActor.run {
          if doInsert {
            displayedSpots.insert(spot!, at: 0)
            if spot!.isFiltered == false && spot!.overlayExists == false {
              overlays.append(spot!.overlay)
              print("Overlay added: \(spot!.spotter):\(spot!.dxStation) - 6")
            }
          }

          if displayedSpots.count > maxNumberOfSpots {
            print("Overlays before: \(overlays.count):\(displayedSpots.count)")
            while displayedSpots.count > maxNumberOfSpots {
              let spot = displayedSpots[displayedSpots.count - 1]
              overlays = overlays.filter({ $0.hashValue != spot.id })
              displayedSpots.removeLast()
            }

            print("Overlays after: \(overlays.count):\(displayedSpots.count)")
          }
        }
    }
  }

  // MARK: - Filter by Time

  /// Remove spots older than 30 minutes
  /// - Parameter filterState: filter/don't filter
  func setTimeFilter(filterState: Bool) {

    //let localDateTime = Date()

    //let iso8601DateFormatter = ISO8601DateFormatter()
    //iso8601DateFormatter.formatOptions = [.withFullTime]
    //let string = iso8601DateFormatter.string(from: localDateTime)
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
    //let dateString = "hmm"
    //let utcDate = utcDateFormatter.date(from: dateString)

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

  /// Remove overlays where the call sign does not match the filter.
  /// - Parameter callSign: String
  func setCallFilter(callSign: String) {

    callFilter = callSign

    if callSign.isEmpty {
      setAllCallSpotFilters(filterState: false)
    } else {
      updateSpotCallFilterState(call: callSign, filterState: false)
    }

    filterOverlays()
  }

  /// Update the filter state on a spot.
  /// - Parameters:
  ///   - call: String
  ///   - setFilter: Bool
  func updateSpotCallFilterState(call: String, filterState: Bool) {
    DispatchQueue.main.async { [self] in
      for (index, spot) in displayedSpots.enumerated() where spot.dxStation.prefix(call.count) != call {
        var mutatingSpot = spot
        mutatingSpot.setFilter(reason: .call)
        displayedSpots[index] = mutatingSpot
        //print("Filtered: \(spot.dxStation):\(index)")
      }
    }
  }

  /// Reset all the call filters to the same state.
  /// - Parameter setFilter: FilterState
  func setAllCallSpotFilters(filterState: Bool) {
    DispatchQueue.main.async { [self] in
      for (index, spot) in displayedSpots.enumerated() {
        var mutatingSpot = spot
        mutatingSpot.resetFilter(reason: .call)
        displayedSpots[index] = mutatingSpot
      }
    }
  }

  // MARK: - Filter Bands

  /// Manage the band button state.
  /// - Parameters:
  ///   - band: Int
  ///   - state: Bool
  func setBandButtons( band: Int, state: Bool) {

    if band == 9999 {return}

    switch state {
    case true:
      if band != 0 {
        bandFilters[Int(band)] = .isOn
      } else {
        // turn off all bands
        bandFilters.keys.forEach { bandFilters[$0] = .isOn }
        setAllBandSpotFilters(filterState: state)
        DispatchQueue.main.async { [self] in
          overlays.removeAll()
        }
        return
      }
    case false:
      if band != 0 {
        bandFilters[Int(band)] = .isOff
      } else {
        // turn on all bands
        bandFilters.keys.forEach { bandFilters[$0] = .isOff }
        setAllBandSpotFilters(filterState: state)
        filterOverlays()
        return
      }
    }

    updateSpotBandFilterState(band: band, filterState: state)
    filterOverlays()
  }

  /// Update the filter state on a spot.
  /// - Parameters:
  ///   - band: Int
  ///   - setFilter: Bool
  func updateSpotBandFilterState(band: Int, filterState: Bool) {
    DispatchQueue.main.async { [self] in
      for (index, spot) in displayedSpots.enumerated() where spot.band == band {
        var mutatingSpot = spot
        if filterState {
          mutatingSpot.setFilter(reason: .band)
        } else {
          mutatingSpot.resetFilter(reason: .band)
        }
        displayedSpots[index] = mutatingSpot
      }
    }
  }

  /// Reset all the band filters to the same state.
  /// - Parameter setFilter: FilterState
  func setAllBandSpotFilters(filterState: Bool) {
    DispatchQueue.main.async { [self] in
      for (index, spot) in displayedSpots.enumerated() {
        var mutatingSpot = spot
        mutatingSpot.resetFilter(reason: .band)
        displayedSpots[index] = mutatingSpot
      }
    }
  }

  // MARK: - Filter Modes

  func setModeButtons(mode: Int, state: Bool) {

    switch state {
    case true:
      modeFilters[Int(mode)] = .isOn
    default:
      modeFilters[Int(mode)] = .isOff
      break;
    }

    //updateSpotModeFilterState(mode: mode, filterState: state)
    filterOverlays()

  }

  // MARK: - Filter Overlays

  /// Only allow overlays where isFiltered == false
  func filterOverlays() {
    DispatchQueue.main.async { [self] in
      for spot in displayedSpots {
        if spot.isFiltered == false {
          // if overlays.first(where: {$0.subtitle == spot.id.uuidString}) == nil {
          if overlays.first(where: {$0.hashValue == spot.id}) == nil {
            overlays.append(spot.overlay!)
          }
        } else {
          overlays = overlays.filter({ $0.hashValue != spot.id })
        }
      }
    }
  }

  /// Remove and recreate the overlays to match the current spots.
  func regenerateOverlays() {
    DispatchQueue.main.async { [self] in
      overlays.removeAll()
    }
  }

  // MARK: - Keep Alive Timer

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
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [self] in
        reconnect()
      }
    }
  }

  /// Connect to the previously connected cluster after
  /// an unplanned disconnect.
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
    //          latitudinalMeters: REGION_RADIUS, longitudinalMeters: REGION_RADIUS)
    //clustermapView.setRegion(coordinateRegion, animated: true)
  }

  // MARK: - JSON Decode/Encode

  /*
   {"dxLatitude":32.604489999999998,"band":20,"spotterLatitude":-34.526000000000003,
   "spotterLongitude":-58.472700000000003,"dxGrid":"EM72go","dxLongitude":-85.482693999999995,
   "dxCountry":"United States","dxLotw":false,"spotterGrid":"GF05sl","spotterCall":"LU4DCW","dateTime":"2021-04-10T22:03:59Z",
   "spotterLotw":false,"expired":false,"identifier":"0","dxCall":"W4E","error":false,"formattedFrequency":
   14.079999923706055,"spotterCountry":"Argentina","frequency":"14.080","mode":""}
   */

  /// Build a string to hold information from the associated spot.
  /// - Parameter info: QRZInfoCombined that built overlay.
  /// - Returns: string representation of QRZInfoCombined.
  func buildJSONString(qrzInfoCombined: StationInformationCombined) -> String {

    let encoder = JSONEncoder()
    guard let data = try? encoder.encode(qrzInfoCombined) else { return "" }

    //print(String(data: data, encoding: .utf8) ?? "")

    return  String(data: data, encoding: .utf8) ?? ""
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
