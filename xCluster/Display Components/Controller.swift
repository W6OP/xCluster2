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

  private(set) var isFiltered: Bool

  /// Build the line (overlay) to display on the map.
  /// - Parameter qrzInfoCombined: combined data of a pair of call signs - QRZ information.
  mutating func createOverlay(stationInfoCombined: StationInformationCombined) {
    let locations = [
      CLLocationCoordinate2D(latitude: stationInfoCombined.spotterLatitude,
                             longitude: stationInfoCombined.spotterLongitude),
      CLLocationCoordinate2D(latitude: stationInfoCombined.dxLatitude,
                             longitude: stationInfoCombined.dxLongitude)]

    let polyline = MKGeodesicPolyline(coordinates: locations, count: locations.count)
    polyline.title = String(stationInfoCombined.band)
    polyline.subtitle = stationInfoCombined.mode
    //polyline.subtitle = id.uuidString
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

actor StationInfoCache {
  var cache = [String: StationInformation]()

  func updateCache(call: String, stationInfo: StationInformation) {
    // check if already there?
    cache[call] = stationInfo
  }

  /// Check to see if we already have all the information needed.
  /// - Parameter call: call sign to lookup.
  /// - Returns: StationInformation
  func checkCache(call: String) -> StationInformation? {
     if cache[call] != nil { return cache[call] }
     return nil
   }
} // end actor


/// Array of Station Information
actor StationInformationPairs {
  var callSignPairs = [Int: [StationInformation]]()

  private func add(spotId: Int, stationInformation: StationInformation) {

    var callSignPair = [StationInformation]()
    callSignPair.append(stationInformation)
    callSignPairs[spotId] = callSignPair
  }

  func checkCallSignPair(spotId: Int, stationInformation: StationInformation) -> [StationInformation] {
    var callSignPair = [StationInformation]()

    if callSignPairs[spotId] != nil {
      callSignPair = updateCallSignPair(spotId: spotId, stationInformation: stationInformation)
    } else {
      add(spotId: spotId, stationInformation: stationInformation)
    }
    return callSignPair
  }

  private func updateCallSignPair(spotId: Int, stationInformation: StationInformation) -> [StationInformation] {

    var callSignPair = [StationInformation]()

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

// MARK: - Controller Class

// Good read on clusters
// https://www.hamradiodeluxe.com/blog/Ham-Radio-Deluxe-Newsletter-April-19-2018--Understanding-DX-Clusters.html

/// Stub between view and all other classes
public class  Controller: ObservableObject, TelnetManagerDelegate, WebManagerDelegate {

  let logger = Logger(subsystem: "com.w6op.xCluster", category: "Controller")

  // MARK: - Published Properties

  @Published var displayedSpots = [ClusterSpot]()
  @Published var statusMessage = [String]()
  @Published var haveSessionKey = false
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

  //var qrzManager = QRZManager()
  var telnetManager = TelnetManager()
  var spotProcessor = SpotProcessor()
  var webManager = WebManager()

  // Call Parser
  let callParser = PrefixFileParser()
  var callLookup = CallLookup()
  var callSignCache = [String: StationInformation]()
  var stationInfoCache = StationInfoCache()
  var stationInformationPairs = StationInformationPairs()

  var callSignLookup: [String: String] = ["call": "", "country": "", "lat": "", "lon": "", "grid": "", "lotw": "0", "aliases": "", "Error": ""]

  let callSign = UserDefaults.standard.string(forKey: "callsign") ?? ""
  let fullName = UserDefaults.standard.string(forKey: "fullname") ?? ""
  let location = UserDefaults.standard.string(forKey: "location") ?? ""
  let grid = UserDefaults.standard.string(forKey: "grid") ?? ""
  let qrzUserName = UserDefaults.standard.string(forKey: "username") ?? ""
  let qrzPassword = UserDefaults.standard.string(forKey: "password") ?? ""

  // mapping
  let maxNumberOfSpots = 200
  let regionRadius: CLLocationDistance = 10000000
  let centerLatitude = 28.282778
  let centerLongitude = -40.829444
  let keepAliveInterval = 300 // 5 minutes
  let dxSummitRefreshInterval = 60 // 1 minute

//  let standardStrokeColor = NSColor.blue
//  let ft8StrokeColor = NSColor.red
//  let lineWidth: Float = 5.0 //1.0

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
    //qrzManager.qrZedManagerDelegate = self
    webManager.webManagerDelegate = self

    callLookup = CallLookup(prefixFileParser: callParser)

    keepAliveTimer = Timer.scheduledTimer(timeInterval: TimeInterval(keepAliveInterval),
                     target: self, selector: #selector(tickleServer), userInfo: nil, repeats: true)

    webRefreshTimer = Timer.scheduledTimer(timeInterval: TimeInterval(dxSummitRefreshInterval),
                    target: self, selector: #selector(refreshWeb), userInfo: nil, repeats: true)

    requestQRZSessionKey()
  }

  // MARK: - Protocol Delegate Implementation

  /// Connect to a cluster.
  /// - Parameter clusterName: Name of cluster to connect to.
  func  connect(cluster: ClusterIdentifier) {

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

  /// Disconnect on cluster change or application termination.
  func disconnect() {
    telnetManager.disconnect()

    // clear the status message
    DispatchQueue.main.async { [self] in
      statusMessage = [String]()
      }
  }

  /// Reconnect when the connection drops.
  func reconnectCluster() {

    logger.info("Reconnect attempt.")
    disconnect()

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [self] in
        reconnect()
    }
  }

  // MARK: - Web Data Received

  // NEEDS CLEANUP
  func webManagerDataReceived(_ webManager: WebManager, messageKey: NetworkMessage, message: String) {

    switch messageKey {

    case.htmlSpotReceived:
      parseClusterSpot(message: message, messageType: messageKey)

    default:
      print ("Handle this message type \(messageKey) : \(message)")
    }

    DispatchQueue.main.async { [self] in
      if statusMessage.count > maxStatusMessages {
        statusMessage.removeFirst()
      }
    }
  }

  // MARK: - Telnet Status Received

   /// Telnet Manager protocol - Process a status message from the Telnet Manager.
   /// - parameters:
   /// - telnetManager: Reference to the class sending the message.
   /// - messageKey: Key associated with this message.
   /// - message: Message text.
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
   /// - messageKey: Key associated with this message.
   /// - message: Message text.
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

    case.htmlSpotReceived:
      print("ERROR ERROR")
      //parseClusterSpot(message: message, messageType: messageKey)

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

  // MARK: - QRZ Session Key Data Received

   /// QRZ Manager protocol - Retrieve the session key from QRZ.com
   /// - parameters:
   /// - qrzManager: Reference to the class sending the message.
   /// - messageKey: Key associated with this message.
   /// - message: Message text.
//  func qrzManagerDidGetSessionKey(_ qrzManager: QRZManager, messageKey: QRZManagerMessage, doHaveSessionKey: Bool) {
//    DispatchQueue.main.async { [self] in
//      haveSessionKey = doHaveSessionKey
//    }
//    logger.info("Received Session Key.")
//  }

  // MARK: - QRZ Call Data Received

  /// QRZ Manager protocol - Receive the call sign data QRZ.com.
  /// - Parameters:
  ///   - qrzManager: Reference to the class sending the message.
  ///   - messageKey: Key associated with this message.
  ///   - qrzInfoCombined: Message text.
  ///   - spot: Associated Cluster spot.
//  func qrzManagerDidGetCallSignData(_ qrzManager: QRZManager, messageKey: QRZManagerMessage, stationInfoCombined: StationInformationCombined, spot: ClusterSpot) {
//
//    // need to make spot mutable
//    var spot = spot
//    spot.createOverlay(stationInfoCombined: stationInfoCombined)
//
//    DispatchQueue.main.async { [self] in
//      displayedSpots.insert(spot, at: 0)
//      if !spot.isFiltered {
//        overlays.append(spot.overlay)
//      }
//
//      if displayedSpots.count > maxNumberOfSpots {
//        let spot = displayedSpots[displayedSpots.count - 1]
//        overlays = overlays.filter({ $0.hashValue != spot.id })
//        displayedSpots.removeLast()
//      }
//    }
//  }

  // MARK: - QRZ Request Session Key

  /// Get the session key from QRZ.com
  func requestQRZSessionKey() {
//    if !qrzUserName.isEmpty && !qrzPassword.isEmpty {
//      //qrzManager.useCallLookupOnly = false
//      qrzManager.requestSessionKey(name: qrzUserName, password: qrzPassword)
//    } else {
//      //qrzManager.useCallLookupOnly = true
//    }
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

    if commandType == .refreshWeb {
        Task {
          await webManager.connectAsync(cluster: connectedCluster)
        }
    } else {
      telnetManager.send(message, commandType: commandType)
    }
  }

  /// Send a message or command to the telnet manager.
  /// - Parameters:
  ///   - tag: The tag value from the button to identify what command needs to be sent.
  ///   - command: The type of command sent.
  func sendClusterCommand(tag: Int, command: String) {
    switch tag {
    case 20:
      if connectedCluster.clusterProtocol == ClusterProtocol.html {
        Task {
          await webManager.connectAsync(cluster: connectedCluster)
        }
      } else {
        telnetManager.send("show/fdx 20", commandType: .getDxSpots)
      }
    case 50:
      if connectedCluster.clusterProtocol == ClusterProtocol.html {
        connectedCluster.address = connectedCluster.address.replacingOccurrences(of: "25", with: "50")
        Task {
          try? await webManager.createHttpSessionAsync(host: connectedCluster)
        }
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

  /// Parse the cluster spot message. This is where all cluster spots
  /// are first created. Handles all telnet and web spots.
  /// - Parameters:
  ///   - message: "DX de W3EX:      28075.6  N9AMI   1912Z FN20\a\a"
  ///   - messageType: Type of spot received.
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

      checkFilters(&spot)

      // if spot already exists, don't add again
      if displayedSpots.firstIndex(where: { $0.spotter == spot.spotter &&
        $0.dxStation == spot.dxStation && $0.frequency == spot.frequency
      }) != nil {
        return
      }

      logger.info("Spot for: \(spot.spotter):\(spot.dxStation)")


      let spotter = spot
      Task {
        await getSpotterInformation(spot: spotter, call: spotter.spotter)
      }

      let dxSpot = spot
      Task {
        await getSpotterInformation(spot: dxSpot, call: dxSpot.dxStation)
      }

      //getSpotterInformation(spot: spot, call: spot.dxStation)
      //getDxInformation(spot: spot)

    } catch {
      print("parseClusterSpot error: \(error)")
      logger.info("Controller Error: \(error as NSObject)")
      return
    }
  }

  /// Check if the incoming spot needs to be filtered.
  /// - Parameter spot: ClusterSpot
  fileprivate func checkFilters(_ spot: inout ClusterSpot) {

    if bandFilters[Int(spot.band)] == .isOn {
      spot.setFilter(reason: .band)
    }

    if !callFilter.isEmpty {
      if spot.dxStation.prefix(callFilter.count) != callFilter {
        spot.setFilter(reason: .call)
      }
    }
  }

// MARK: - Moved From QRZ Manager

  func getSpotterInformation(spot: ClusterSpot, call: String) async {

    // check if the spotter is in the cache
    //Task {
      let spotterInfo = await stationInfoCache.checkCache(call: call)
      if  spotterInfo != nil {
        logger.info("Cache hit for spotter: \(call)")
        await buildCallSignPair(stationInfo: spotterInfo!, spot: spot)
    } else {
        //Task {
            logger.info("CallParser request for: \(call)")
            let stationInfo = requestCallParserInformation(call: call, spotId: spot.id)
            await buildCallSignPair(stationInfo: stationInfo, spot: spot)
          }
        //}
     // }
  }

  func buildCallSignPair(stationInfo: StationInformation, spot: ClusterSpot) async {
    //Task {
      let callSignPair = await stationInformationPairs.checkCallSignPair(spotId: spot.id, stationInformation: stationInfo)

      if callSignPair.count == 2 {
          logger.info("Combine for: \(callSignPair[0].call):\(callSignPair[1].call)")
           combineQRZInfo(spot: spot, callSignPair: callSignPair)
        await stationInformationPairs.clear()
        }
    //}
  }

  /// Request the information about a call sign from the Call Parser.
  /// - Parameter call: call sign to lookup
  /// - Returns: StationInformation
  func requestCallParserInformation(call: String, spotId: Int) -> StationInformation {

    var stationInfo = StationInformation()

      let hitList: [Hit] = callLookup.lookupCall(call: call)

      if !hitList.isEmpty {
        logger.info("Use callparser - success \(call)")
        stationInfo = populateStationInformation(hitList: hitList)
        stationInfo.id = spotId

        let stationInfo = stationInfo
        Task {
          await stationInfoCache.updateCache(call: stationInfo.call, stationInfo: stationInfo)
          logger.info("Cache update for: \(stationInfo.call)")
        }
      } else {
        logger.info("Use callparser - failure \(call)")
      }

    return stationInfo
  }

  /// Request the information about a call sign from the Call Parser.
  /// - Parameter call: call sign to lookup
  /// - Returns: StationInformation
  func requestCallParserInformationAsync(call: String, spotId: Int) async -> StationInformation {

    var stationInfo = StationInformation()

      let hitList: [Hit] = callLookup.lookupCall(call: call)

      if !hitList.isEmpty {
        logger.info("Use callparser - success \(call)")
        stationInfo = populateStationInformation(hitList: hitList)
        stationInfo.id = spotId

        let stationInfo = stationInfo
        Task {
          await stationInfoCache.updateCache(call: stationInfo.call, stationInfo: stationInfo)
          logger.info("Cache update for: \(stationInfo.call)")
        }
      } else {
        logger.info("Use callparser - failure \(call)")
      }

    return stationInfo
  }

  /// Populate the latitude and longitude from the hit.
  /// - Parameter hitList: collection of hits.
  /// - Returns: StationInformation
  func populateStationInformation(hitList: [Hit]) -> StationInformation {
    var stationInfo = StationInformation()

    let hit = hitList[hitList.count - 1]

    stationInfo.call = hit.call
    stationInfo.country = hit.country

    if let latitude = Double(hit.latitude) {
      stationInfo.latitude = latitude
    }

    if let longitude = Double(hit.longitude) {
      stationInfo.longitude = longitude
    }

    stationInfo.isInitialized = true

    // debugging only
    if stationInfo.longitude == 00 || stationInfo.longitude == 00 {
      logger.info("Longitude/Lattitude error: \(stationInfo.call):\(stationInfo.country)")
    }

    return stationInfo
  }

  /// Combine the QRZ information and send it to the view controller for a line to be drawn.
  /// - Parameter spot: cluster spot.
  func combineQRZInfo(spot: ClusterSpot, callSignPair: [StationInformation]) {

    var qrzInfoCombined = StationInformationCombined()

      qrzInfoCombined.setFrequency(frequency: spot.frequency)

      qrzInfoCombined.spotterCall = callSignPair[0].call
      qrzInfoCombined.spotterCountry = callSignPair[0].country
      qrzInfoCombined.spotterLatitude = callSignPair[0].latitude
      qrzInfoCombined.spotterLongitude = callSignPair[0].longitude
      qrzInfoCombined.spotterGrid = callSignPair[0].grid
      qrzInfoCombined.spotterLotw = callSignPair[0].lotw
      //qrzInfoCombined.spotId = qrzCallSignPairCopy[0].spotId
      qrzInfoCombined.error = callSignPair[0].error

      qrzInfoCombined.dxCall = callSignPair[1].call
      qrzInfoCombined.dxCountry = callSignPair[1].country
      qrzInfoCombined.dxLatitude = callSignPair[1].latitude
      qrzInfoCombined.dxLongitude = callSignPair[1].longitude
      qrzInfoCombined.dxGrid = callSignPair[1].grid
      qrzInfoCombined.dxLotw = callSignPair[1].lotw
      if !qrzInfoCombined.error {
        qrzInfoCombined.error = callSignPair[1].error
      }

      var spot = spot
      spot.country = qrzInfoCombined.dxCountry

    // DON't USE DELEGATE HERE
    processCallSignData(stationInfoCombined: qrzInfoCombined, spot: spot)
//      self.qrZedManagerDelegate?.qrzManagerDidGetCallSignData(
//        self, messageKey: .qrzInformation,
//        stationInfoCombined: qrzInfoCombined,
//        spot: spot)
  }

  func processCallSignData(stationInfoCombined: StationInformationCombined, spot: ClusterSpot) {
    // need to make spot mutable
    var spot = spot
    spot.createOverlay(stationInfoCombined: stationInfoCombined)
    logger.info("Overlay built for: \(stationInfoCombined.spotterCall):\(stationInfoCombined.dxCall)")

    DispatchQueue.main.async { [self] in
      displayedSpots.insert(spot, at: 0)
      if !spot.isFiltered {
        overlays.append(spot.overlay)
      }

      if displayedSpots.count > maxNumberOfSpots {
        let spot = displayedSpots[displayedSpots.count - 1]
        overlays = overlays.filter({ $0.hashValue != spot.id })
        displayedSpots.removeLast()
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

  /// Reset all the band filters to the same state.
  /// - Parameter setFilter: FilterState
//  func setAllModeSpotFilters(filterState: Bool) {
//    DispatchQueue.main.async { [self] in
//      for (index, spot) in spots.enumerated() {
//        var mutatingSpot = spot
//        mutatingSpot.resetFilter(reason: .mode)
//        spots[index] = mutatingSpot
//      }
//    }
//  }

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

  /// Build a QRZInfoCombined from a string.
  /// - Parameter subTitle: subtitle from overlay.
  /// - Returns: QRZInfoCombined
//  func extractJSONFromString(subTitle: String) -> StationInformationCombined {
//
//    let decoder = JSONDecoder()
//
//    let data = subTitle.data(using: .utf8)!
//    guard let qrzInfoCombined = try? decoder.decode(StationInformationCombined.self, from: data) else {
//      return StationInformationCombined()
//    }
//
//    return qrzInfoCombined
//  }

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
