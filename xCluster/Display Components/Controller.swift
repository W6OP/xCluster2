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

// MARK: - Controller Class

// Good read on clusters
// https://www.hamradiodeluxe.com/blog/Ham-Radio-Deluxe-Newsletter-April-19-2018--Understanding-DX-Clusters.html

// swiftlint:disable file_length
// swiftlint:disable type_body_length
// swiftlint:disable cyclomatic_complexity
/// Stub between view and all other classes
public class  Controller: ObservableObject, TelnetManagerDelegate, WebManagerDelegate {

  let logger = Logger(subsystem: "com.w6op.xCluster", category: "Controller")

  // MARK: - Published Properties

  @Published var displayedSpots = [ClusterSpot]()
  @Published var statusMessage = [String]()
  @Published var overlays = [MKPolyline]()
  @Published var annotations = [MKPointAnnotation]()

  @Published var bandFilter = (id: 0, state: false) {
    didSet {
      setBandButtons(band: bandFilter.id, state: bandFilter.state)
    }
  }

  @Published var modeFilter = (id: 0, state: false) {
    didSet {
      //setModeButtons(mode: modeFilter.id, state: modeFilter.state)
    }
  }

  @Published var connectedCluster = ClusterIdentifier(id: 9999,
                                                      name: "Select Cluster",
                                                      address: "",
                                                      port: "",
                                                      clusterProtocol:
                                                        ClusterProtocol.none, retraint: .none) {
    didSet {
      if !connectedCluster.address.isEmpty {
        connect(cluster: connectedCluster, isReconnection: false)
      }
    }
  }

  @Published var selectedNumberOfSpots = SpotsIdentifier(id: 25,
                                                         maxLines: 25,
                                                         displayedLines: "25") {
    didSet {
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

  var hitsCache = HitCache()
  var spotCache = SpotCache()

  // Call Parser
  let callParser = PrefixFileParser()
  var callLookup = CallLookup()

  // QRZ.com
  let callSign = UserDefaults.standard.string(forKey: "callsign") ?? ""
  let fullName = UserDefaults.standard.string(forKey: "fullname") ?? ""
  let location = UserDefaults.standard.string(forKey: "location") ?? ""
  let grid = UserDefaults.standard.string(forKey: "grid") ?? ""
  let qrzUserName = UserDefaults.standard.string(forKey: "username") ?? ""
  let qrzPassword = UserDefaults.standard.string(forKey: "password") ?? ""

  // mapping
  var maxNumberOfSpots = 100
  let maxStatusMessages = 200
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
  // this is set by the Checkbox view in the ContentView
  var exactMatch = false
  var activeCluster: ClusterIdentifier!

  var lastSpotReceivedTime = Date()

  // MARK: - Initialization

  init () {
    telnetManager.telnetManagerDelegate = self
    webManager.webManagerDelegate = self

    // initialize the Call Parser
    callLookup = CallLookup(prefixFileParser: callParser) // , qrzUserName, qrzPassword

    keepAliveTimer = Timer.scheduledTimer(timeInterval: TimeInterval(keepAliveInterval),
                                          target: self, selector: #selector(tickleServer), userInfo: nil, repeats: true)

    webRefreshTimer = Timer.scheduledTimer(timeInterval: TimeInterval(dxSummitRefreshInterval),
                                           target: self, selector: #selector(refreshWeb), userInfo: nil, repeats: true)

    callParserCallback()
    setupSessionCallback()
  }

  // MARK: - Connect and Disconnect

  /// Connect to a specified cluster. If already connected then
  /// disconnect from the connected cluster first.
  /// - Parameter clusterName: String
  func connect(cluster: ClusterIdentifier, isReconnection: Bool) {

    if connectedCluster.id != 9999 {

      if activeCluster != nil {
        disconnect(activeCluster: activeCluster)
      }

      Task {
        await spotCache.clear()
        await hitsCache.clear()
      }

      if !isReconnection {
        cleanupConnection(isReconnection, cluster)
      }

      if cluster.clusterProtocol == ClusterProtocol.html {
        Task {
          await webManager.connectAsync(cluster: cluster)
        }
      } else {
        // don't use QRZ.com for RBNs
        if cluster.retraint == .rbn {
          callLookup.useCallParserOnly = true
        } else {
          callLookup.useCallParserOnly = false
        }
        telnetManager.connect(cluster: cluster)
      }
      activeCluster = cluster
    }
  }

  /// Cleanup before connectiong to a new cluster.
  /// - Parameters:
  ///   - isReconnection: Bool
  ///   - cluster: ClusterIdentifier
  fileprivate func cleanupConnection(_ isReconnection: Bool, _ cluster: ClusterIdentifier) {
      overlays.removeAll()
      annotations.removeAll()
      displayedSpots.removeAll()
      bandFilters.keys.forEach { bandFilters[$0] = .isOff }
      logger.info("Connecting to: \(cluster.name)")
  }

  /// Disconnect on cluster change or application termination.
  /// Send a signal to clear the existing status message.
  func disconnect(activeCluster: ClusterIdentifier) {

    guard activeCluster.id != 9999 else { return }

    if activeCluster.clusterProtocol == ClusterProtocol.telnet {
      telnetManager.disconnect()
    }

    // clear the status message
    DispatchQueue.main.async { [weak self] in
      self?.statusMessage = [String]()
    }
  }

  /// Reconnect when the connection drops.
  func reconnectCluster() {

    logger.info("Reconnection attempt.")

    disconnect(activeCluster: activeCluster)

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
      self?.reconnect()
    }
  }

  // MARK: - Web Data Received

  /// The WebManager has received data.
  func webManagerDataReceived(_ webManager: WebManager, messageKey: NetworkMessage, message: String) {

    switch messageKey {
    case.htmlSpotReceived:
      do {
      try parseClusterSpot(message: message, messageType: messageKey)
      } catch {
        logger.info("Duplicate spot received \(messageKey.rawValue) : \(message)")
      }
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
      if self.statusMessage.count > self.maxStatusMessages {
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
      DispatchQueue.main.async { [weak self] in
        self?.statusMessage.append(message.condenseWhitespace())
      }

    case .announcement:
      DispatchQueue.main.async { [weak self] in
        self?.statusMessage.append(message.condenseWhitespace() )
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
      do {
      try parseClusterSpot(message: message, messageType: messageKey)
      } catch {
        logger.info("Duplicate spot received \(messageKey.rawValue) : \(message)")
      }

    case .showDxSpots:
      do {
      try parseClusterSpot(message: message, messageType: messageKey)
      } catch {
        logger.info("Duplicate spot received \(messageKey.rawValue) : \(message)")
      }
    default:
      break
    }

    DispatchQueue.main.async { [weak self] in
      if (self?.statusMessage.count)! > 200 {
        self?.statusMessage.removeFirst()
      }
    }
  }

  // MARK: - Application Commands

  func sendApplicationCommand(command: CommandType) {
    switch command {
    case .clear:
      Task {
        await MainActor.run {
        annotations.removeAll()
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
  func parseClusterSpot(message: String, messageType: NetworkMessage) throws {

    lastSpotReceivedTime = Date()

    do {
      var spot: ClusterSpot

      switch messageType {
      case .spotReceived:
        spot = try self.spotProcessor.processRawSpot(rawSpot: message, isTelnet: true)
      case .htmlSpotReceived:
        spot = try self.spotProcessor.processRawSpot(rawSpot: message, isTelnet: false)
      default:
        return
      }

      // if spot already exists, don't add again
      if displayedSpots.firstIndex(where: { $0.spotter == spot.spotter &&
        $0.dxStation == spot.dxStation && $0.band == spot.band
      }) != nil {
        logger.info("Duplicate Spot: \(spot.spotter):\(spot.dxStation)")
        throw (RequestError.duplicateSpot)
      }

      let asyncSpot = spot
      Task {
        try await lookupCompletedSpot(spot: asyncSpot)
      }

    } catch {
      logger.info("Controller Error: \(error as NSObject)")
      return
    }
  }

  // MARK: - Lookup call with CallParser - Callback

  /// Lookup a spot using the CallParser component.
  /// - Parameter spot: ClusterSpot
  func lookupCompletedSpot(spot: ClusterSpot) async throws {
    var spot = spot

    applyFilters(&spot)

    await spotCache.addSpot(spot: spot)

    let callSigns = [spot.spotter, spot.dxStation]
    let asyncSpot = spot
    await withTaskGroup(of: Void.self) { group in
      for index in 0..<callSigns.count {
        group.addTask { [self] in
          callLookup.lookupCall(call: callSigns[index],
                                spotInformation:
                                  (spotId: asyncSpot.id, sequence: index))
        }
      }
    }
  }

  /// Callback when CallLookup finds a Hit.
   func callParserCallback() {

     callLookup.didUpdate = { hitList in
       if !hitList!.isEmpty {
         // TODO: - find out why this happens - should never be this many hits
         if hitList!.count > 10 {
           print("Call: \(hitList![0].call)")
           for index in 0..<hitList!.count {
             print("country: \(hitList![index].country)")
            }
          }

         let hit = hitList![0]

         Task {
           await self.hitsCache.addHit(hitId: hit.spotId, hit: hit)
           if await self.hitsCache.getCount(spotId: hit.spotId) > 1 {
             await self.processHits(spotId: hit.spotId)
           }
         }
       }
     }
   }

// MARK: - Process the returned Hits and Spots

  /// Process hits returned by the CallParser.
  /// - Parameter spotId: Int
  func processHits(spotId: Int ) async {

    // see if we have two matching hits
    let hits = await hitsCache.retrieveHits(spotId: spotId)
      async let hitPair = HitPair()
      await hitPair.addHits(hits: hits)

      // TODO: - need to clear hit and spot cache on cluster switch
      let spot = await spotCache.retrieveSpot(spotId: spotId)

    if !spot.isInvalidSpot {
      await processSpot(hitPair: hitPair, spot: spot)
      await hitsCache.removeHits(spotId: spotId)
    }
  }

  /// Process a spot and the associated HitPair.
  /// - Parameters:
  ///   - hitPair: HitPair
  ///   - spot: ClusterSpot
  func processSpot(hitPair: HitPair, spot: ClusterSpot) async {
    await self.processStationInformation(hitPairs: hitPair, spot: spot)
    await spotCache.removeSpot(spotId: spot.id)
  }

  /// Build the station information for both calls in the spot.
  /// - Parameters:
  ///   - hitPairs2: HitPair
  ///   - spot: ClusterSpot
  func processStationInformation(hitPairs: HitPair, spot: ClusterSpot) async {

    await withTaskGroup(of: StationInformation.self) { group in
      for index in 0..<2 {
        group.addTask { [self] in
          return await populateStationInformation(hit: hitPairs.hits[index],
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
      spot.manageFilters(reason: .band)
    }

    if !callFilter.isEmpty {
      if spot.dxStation.prefix(callFilter.count) != callFilter {
        spot.manageFilters(reason: .call)
      }
    }
  }

  // MARK: - QRZ Logon

  // TODO: feedback to user logon was successful
  /// Logon to QRZ.com
  /// - Parameters:
  ///   - userId: String
  ///   - password: String
  func qrzLogon(userId: String, password: String) {
    callLookup.logonToQrz(userId: userId, password: password)
  }

  /// Callback from the Call Parser for QRZ logon success/failure.
  func setupSessionCallback() {

    callLookup.didGetSessionKey = { arg0 in
      let session: (state: Bool, message: String) = arg0!
      if !session.state {
        self.statusMessage.append("QRZ logon failed: \(session.message)")
      } else {
        self.statusMessage.append("QRZ logon successful")
      }
    }
  }

  // MARK: - Populate Station Info

  /// Populate a StationInformation object with the data from the hit.
  /// - Parameters:
  ///   - hit: Hit
  ///   - spotId: Int
  /// - Returns: StationInformation
  func populateStationInformation(hit: Hit, spotId: Int) -> StationInformation {

    var stationInformation = StationInformation()

    logger.info("Processing stationInformation for: \(hit.call) - 2a")

    stationInformation.id = spotId
    stationInformation.call = hit.call
    stationInformation.country = hit.country
    stationInformation.position = hit.sequence

    if let latitude = Double(hit.latitude) {
      stationInformation.latitude = latitude
    } else {
      print("Lat: \(hit.latitude)")
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

  /// Sort routine so spotter and dx is in correct order
  /// - Parameter callSignPair: [StationInformation]
  /// - Returns: [StationInformation]
  func sortCallSignPair(callSignPair: [StationInformation]) -> [StationInformation] {
    let callSignPair = callSignPair.sorted {
      $0.position < $1.position
    }
    return callSignPair
  }

  /// Combine the CallParser information.
  /// - Parameters:
  ///   - spot: ClusterSpot
  ///   - callSignPair: [StationInformation]
  func combineHitInformation(spot: ClusterSpot, callSignPair: [StationInformation]) {

    logger.info("combineHitInformation: \(callSignPair[0].call): \(callSignPair[1].call) - 4")

    // need to sort here so spotter and dx is in correct order
    let callSignPair = sortCallSignPair(callSignPair: callSignPair)

    var stationInformationCombined = StationInformationCombined()

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

    processCallSignData(stationInformationCombined:
                          stationInformationCombined, spot: spot)
  }

  // MARK: - Create Overlays and Annotations

  /// Have the spot create the overlay associated with it.
  /// - Parameters:
  ///   - stationInfoCombined: StationInformationCombined
  ///   - spot: ClusterSpot
  func processCallSignData(stationInformationCombined:
                           StationInformationCombined,
                           spot: ClusterSpot) {

    logger.info("Create Overlay: \(stationInformationCombined.spotterCall): \(stationInformationCombined.dxCall) - 5")

    // need to make spot mutable
    var spot = spot
    spot.createOverlay(stationInfoCombined: stationInformationCombined)
    spot.createAnnotation(stationInfoCombined: stationInformationCombined)

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
              annotations.append(spot!.spotterPin)
              annotations.append(spot!.dxPin)
            } else {
              print("____________________ DUPLICATE _____________________")
            }
          }

          if displayedSpots.count > maxNumberOfSpots {
            while displayedSpots.count > maxNumberOfSpots {
              let spot = displayedSpots[displayedSpots.count - 1]
              overlays = overlays.filter({ $0.hashValue != spot.id })
              annotations = annotations.filter({ $0.hashValue != spot.spotterPinId })
              annotations = annotations.filter({ $0.hashValue != spot.dxPinId })
              displayedSpots.removeLast()
            }
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

    setAllCallFilters(filterState: false)

    if !callSign.isEmpty {
      updateCallFilterState(call: callSign, filterState: false)
    }

    filterOverlays()
  }

  /// Update the filter state on a spot.
  /// - Parameters:
  ///   - call: String
  ///   - setFilter: Bool
  func updateCallFilterState(call: String, filterState: Bool) {
    DispatchQueue.main.async { [self] in
      if exactMatch {
        print("exact")
        for (index, spot) in displayedSpots.enumerated() where spot.dxStation.prefix(call.count) != call {
          var mutatingSpot = spot
          mutatingSpot.manageFilters(reason: .call)
          displayedSpots[index] = mutatingSpot
        }
      } else {
        print("almost")
        for (index, spot) in displayedSpots.enumerated() where !spot.dxStation.contains(call) {
          var mutatingSpot = spot
          mutatingSpot.manageFilters(reason: .call)
          displayedSpots[index] = mutatingSpot
        }
      }
    }
  }

  /// Reset all the call filters to the same state.
  /// - Parameter setFilter: FilterState
  func setAllCallFilters(filterState: Bool) {
    DispatchQueue.main.async { [self] in
      for (index, spot) in displayedSpots.enumerated() {
        var mutatingSpot = spot
        mutatingSpot.manageFilters(reason: .call)
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
        bandFilters[Int(band)] = .isOff
      } else {
        // turn off all bands
        bandFilters.keys.forEach { bandFilters[$0] = .isOff }
        resetAllBandSpotFilters(filterState: state)
        DispatchQueue.main.async { [self] in
          overlays.removeAll()
          annotations.removeAll()
        }
        return
      }
    case false:
      if band != 0 {
        bandFilters[Int(band)] = .isOn
      } else {
        // turn on all bands
        bandFilters.keys.forEach { bandFilters[$0] = .isOn }
        resetAllBandSpotFilters(filterState: state)
        filterOverlays()
        return
      }
    }

    updateBandFilterState(band: band, filterState: state)
    filterOverlays()
  }

  /// Update the filter state on a spot.
  /// - Parameters:
  ///   - band: Int
  ///   - setFilter: Bool
  func updateBandFilterState(band: Int, filterState: Bool) {
    DispatchQueue.main.async { [self] in
      for (index, spot) in displayedSpots.enumerated() where spot.band == band {
        var mutatingSpot = spot
        mutatingSpot.manageFilters(reason: .band)
        displayedSpots[index] = mutatingSpot
      }
    }
  }

  /// Set all the band filters to the same state.
  /// - Parameter setFilter: FilterState
  func resetAllBandSpotFilters(filterState: Bool) {
    DispatchQueue.main.async { [self] in
      for (index, spot) in displayedSpots.enumerated() {
        var mutatingSpot = spot
        mutatingSpot.manageFilters(reason: .band)
        displayedSpots[index] = mutatingSpot
      }
    }
  }

  // MARK: - Filter Modes

//  func setModeButtons(mode: Int, state: Bool) {
//
//    switch state {
//    case true:
//      modeFilters[Int(mode)] = .isOn
//    default:
//      modeFilters[Int(mode)] = .isOff
//      break;
//    }
//
//    //updateSpotModeFilterState(mode: mode, filterState: state)
//    filterOverlays()
//  }

  // MARK: - Filter Overlays

  /// Only allow overlays where isFiltered == false
  func filterOverlays() {
    DispatchQueue.main.async { [self] in
      for spot in displayedSpots {
        if spot.isFiltered == false {
          // spot.id = polyline(overlay) hash value
          if overlays.first(where: {$0.hashValue == spot.id}) == nil {
            overlays.append(spot.overlay!)
          }
        } else {
          overlays = overlays.filter({ $0.hashValue != spot.id })
        }
      }
    }
    filterAnnotations()
  }

  /// Filter the annotations or flags at each end of an overlay.
  func filterAnnotations() {
    DispatchQueue.main.async { [self] in
      for spot in displayedSpots {
        if spot.isFiltered == false {
          if annotations.first(where: {$0.hashValue == spot.spotterPinId}) == nil {
            annotations.append(spot.spotterPin)
            annotations.append(spot.dxPin)
          }
        } else {
          annotations = annotations.filter({ $0.hashValue != spot.spotterPinId })
          annotations = annotations.filter({ $0.hashValue != spot.dxPinId })
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

      disconnect(activeCluster: activeCluster)
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [self] in
        reconnect()
      }
    }
  }

  /// Connect to the previously connected cluster after
  /// an unplanned disconnect.
  func reconnect() {
    logger.info("Reconnecting to: \(self.connectedCluster.name)")
    connect(cluster: connectedCluster, isReconnection: true)
  }

  /**
   Calculate the number of minutes between two dates
   https://stackoverflow.com/questions/28016578/how-can-i-parse-create-a-
   date-time-stamp-formatted-
   with-fractional-seconds-utc/28016692#28016692
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
} // end class
