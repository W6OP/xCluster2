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

  @Published var annotations = [ClusterPinAnnotation]()
  @Published var displayedSpots = [ClusterSpot]()
  @Published var statusMessages = [StatusMessage]()
  @Published var overlays = [MKGeodesicPolyline]()

  @Published var bandFilter = (id: 0, state: false) {
    didSet {
      setBandButtons(band: bandFilter.id, state: bandFilter.state)
    }
  }

  @Published var connectedCluster = ClusterIdentifier(id: 9999,
                                                      name: "Select Cluster",
                                                      address: "",
                                                      port: "",
                                                      clusterProtocol:
                                                        ClusterProtocol.none, restraint: .none) {
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
      manageTotalSpotCount()
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
  var spotHistory = SpotHistory()

  var deletedSpots = [ClusterSpot]()

  // Call Parser
  let callParser = PrefixFileParser()
  var callLookup = CallLookup()

  // QRZ.com
  var callSign = UserDefaults.standard.string(forKey: "callsign") ?? ""
  var fullName = UserDefaults.standard.string(forKey: "fullname") ?? ""
  var location = UserDefaults.standard.string(forKey: "location") ?? ""
  var grid = UserDefaults.standard.string(forKey: "grid") ?? ""
  var qrzUserName = UserDefaults.standard.string(forKey: "username") ?? ""
  var qrzPassword = UserDefaults.standard.string(forKey: "password") ?? ""

  // mapping
  var maxNumberOfSpots = 50
  let maxStatusMessages = 100
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

  var callFilter = ""
  var alertList: [String] = []
  // these is set by the Checkbox views in the ContentView
  var exactMatch = false
  var digiOnly = false {
    didSet {
      setDigiFilter(filterState: digiOnly)
    }
  }

  var formattedFrequency = "" {
    didSet {
      print("\(formattedFrequency)")
    }
  }

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

          await MainActor.run {
            overlays.removeAll()
            annotations.removeAll()
            displayedSpots.removeAll()
        }
      }
      
      if !isReconnection {
        cleanupConnection(isReconnection, cluster)
      }
      
      if updateUserInformation() {
        if cluster.clusterProtocol == ClusterProtocol.html {
          Task {
            await webManager.connectAsync(cluster: cluster)
          }
        } else {
          // don't use QRZ.com for RBNs
          if cluster.restraint == .rbn {
            callLookup.useCallParserOnly = true
          } else {
            callLookup.useCallParserOnly = false
          }
          telnetManager.connect(cluster: cluster)
        }
        activeCluster = cluster
      } else {
       notifyUser()
      }
    }
  }

  /// Notify the user to fill out the preferences dialog.
  func notifyUser() {
    insertStatusMessage(message: "You must set your call and name in the settings dialog")
  }
  
  /// Update the user information.
  func updateUserInformation() -> Bool {
    callSign = UserDefaults.standard.string(forKey: "callsign") ?? ""
    fullName = UserDefaults.standard.string(forKey: "fullname") ?? ""
    location = UserDefaults.standard.string(forKey: "location") ?? ""
    grid = UserDefaults.standard.string(forKey: "grid") ?? ""
    qrzUserName = UserDefaults.standard.string(forKey: "username") ?? ""
    qrzPassword = UserDefaults.standard.string(forKey: "password") ?? ""

    if callSign.isEmpty || fullName.isEmpty {
      return false
    }

    return true
  }

  /// Cleanup before connecting to a new cluster.
  /// - Parameters:
  ///   - isReconnection: Bool
  ///   - cluster: ClusterIdentifier
  fileprivate func cleanupConnection(_ isReconnection: Bool, _ cluster: ClusterIdentifier) {
    deleteExistingData(includeSpots: true)

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

    clearStatusMessages()
  }

  /// Delete existing overlays, annotations and cluster spots.
  /// - Parameter includeSpots: Bool
  func deleteExistingData(includeSpots: Bool) {

    Task {
      await MainActor.run {
        switch includeSpots {
        case true:
          overlays.removeAll()
          annotations.removeAll()
          displayedSpots.removeAll()
        case false:
          overlays.removeAll()
          annotations.removeAll()
        }
      }
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
        //logger.info("Duplicate spot received \(messageKey.rawValue) : \(message)")
        return
      }
    default:
      logger.info("Invalid message type \(messageKey.rawValue) : \(message)")
    }

    limitStatusMessages()
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
      appendStatusMessage(message: message)

    case .disconnected:
      reconnectCluster()

    case .error:
      self.logger.info("Error: \(message)")
      insertStatusMessage(message: message)

    case .callSignRequested:
      self.sendClusterCommand(message: "\(callSign)", commandType: CommandType.logon)

    case .nameRequested:
      self.sendClusterCommand(message: "set/name \(fullName)", commandType: CommandType.callsign)

    case .qthRequested:
      self.sendClusterCommand(message: "set/qth \(location)", commandType: CommandType.setQth)

    case .location:
      self.sendClusterCommand(message: "set/qra \(grid)", commandType: CommandType.message)

    case .clusterInformation:
      appendStatusMessage(message: message)

    default:
      appendStatusMessage(message: message)
    }

    limitStatusMessages()
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
      appendStatusMessage(message: message.condenseWhitespace())

    case .announcement:
      appendStatusMessage(message: message.condenseWhitespace())

      // TODO: do something with append
    case .clusterInformation:
      Task {
        await MainActor.run {
          let messages = limitMessageLength(message: message)
          for item in messages {
          let statusMessage = StatusMessage(message: item)
            self.statusMessages.append(statusMessage)
          }
        }
      }

    case .error:
      appendStatusMessage(message: message)

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

    limitStatusMessages()
  }

  // MARK: - Status Messages

  /// Append a new status message.
  /// - Parameter message: String
  func appendStatusMessage(message: String) {
    Task {
      await MainActor.run {
        let statusMessage = StatusMessage(message: message)
        self.statusMessages.append(statusMessage) //= [statusMessage]
      }
    }
  }


  /// Insert a status message at the beginning.
  /// - Parameter message: String
  func insertStatusMessage(message: String) {
    Task {
      await MainActor.run {
        let statusMessage = StatusMessage(message: message)
        self.statusMessages.insert(statusMessage, at: 0) //= [statusMessage]
      }
    }
  }

  /// Clear all status messages.
  func clearStatusMessages() {
    Task {
      await MainActor.run {
        self.statusMessages = [StatusMessage]()
      }
    }
  }


  /// Limit the number of status messages.
  func limitStatusMessages() {
    Task {
      await MainActor.run {
        if (self.statusMessages.count) > maxStatusMessages {
          self.statusMessages.removeFirst()
        }
      }
    }
  }

  // MARK: - Application Commands

  func sendApplicationCommand(command: CommandType) {
    switch command {
    case .clear:
      deleteExistingData(includeSpots: true)
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

    insertStatusMessage(message: message)

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

      if deletedSpots.firstIndex(where: { $0.spotter == spot.spotter &&
        $0.dxStation == spot.dxStation && $0.band == spot.band
      }) != nil {
        logger.info("Duplicate deleted spot found: \(spot.spotter)-\(spot.dxStation)")
        //throw (RequestError.duplicateSpot)
        return
      }

      let mutatingSpot = spot
      Task {
        try await lookupCompletedSpot(spot: mutatingSpot)
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
    await withTaskGroup(of: Void.self) { group in
      for index in 0..<callSigns.count {
        group.addTask { [spot] in
          self.callLookup.lookupCall(call: callSigns[index],
                                spotInformation:
                                  (spotId: spot.id, sequence: index))
        }
      }
    }
  }

  /// Callback when CallLookup finds a Hit.
  func callParserCallback() {

    callLookup.didUpdate = { [self] hitList in
      if !hitList!.isEmpty {

        let hit = hitList![0]

        Task {
          await hitsCache.addHit(hitId: hit.spotId, hit: hit)
          let hits = await hitsCache.removeHits(spotId: hit.spotId)
          
          if hits.count > 1 {
            await self.processHits(spotId: hit.spotId, hits: hits)
          }
        }
      }
    }
  }

// MARK: - Process the returned Hits and Spots

  /// Process hits returned by the CallParser.
  /// - Parameter spotId: Int
  func processHits(spotId: Int, hits: [Hit] ) async {

    // we have two matching hits
    let hitPair = HitPair()
    await hitPair.addHits(hits: hits)

    let clusterSpot = await spotCache.removeSpot(spotId: spotId)

    if clusterSpot != nil {
      await self.processStationInformation(hitPair: hitPair, clusterSpot: clusterSpot!)
    }
  }

  /// Build the station information for both calls in the spot.
  /// - Parameters:
  ///   - hitPairs2: HitPair
  ///   - spot: ClusterSpot
  func processStationInformation(hitPair: HitPair, clusterSpot: ClusterSpot) async {

    if await hitPair.hits.count < 2 {
      return
    }

    await withTaskGroup(of: StationInformation.self) { group in
      for index in 0..<2 {
        group.addTask { [self] in
          return await populateStationInformation(hit: hitPair.hits[index],
                                                    spotId: clusterSpot.id)
        }
      }

      let stationInformationPairs = StationInformationPairs()
      var callSignPairs = [StationInformation]()

      for await stationInformation in group {
        callSignPairs = await stationInformationPairs.checkCallSignPair(
          spotId: clusterSpot.id, stationInformation: stationInformation)
      }

      if callSignPairs.count == 2 {
        combineHitInformation(clusterSpot: clusterSpot, callSignPair: callSignPairs)
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

    if digiOnly {
      if !checkIsDigi(spot: spot) {
        spot.manageFilters(reason: .notDigi)
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
    callLookup.didGetSessionKey = { [self] arg0 in
      let session: (state: Bool, message: String) = arg0!

      if !session.state {
        insertStatusMessage(message: "QRZ logon failed: \(session.message)")
      } else {
        insertStatusMessage(message: "QRZ logon successful: \(session.message)")
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

    stationInformation.id = spotId
    stationInformation.call = hit.call
    stationInformation.country = hit.country
    stationInformation.province = hit.province
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
      logger.info("Longitude/Latitude error: \(stationInformation.call):\(stationInformation.country)")
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
  func combineHitInformation(clusterSpot: ClusterSpot, callSignPair: [StationInformation]) {

    // don't process duplicates
    guard !checkForDuplicateSpot(spot: clusterSpot) else {
      //print("spot is a duplicate: \(displayedSpots.count)")
      return
    }

    // need to sort here so spotter and dx is in correct order
    let callSignPair = sortCallSignPair(callSignPair: callSignPair)

    var stationInformationCombined = StationInformationCombined()

    stationInformationCombined.spotterCall = callSignPair[0].call.trimmingCharacters(in: .whitespacesAndNewlines)
    stationInformationCombined.spotterCountry = callSignPair[0].country
    stationInformationCombined.spotterProvince = callSignPair[0].province
    if stationInformationCombined.spotterCountry.contains("United States") {
      if callSignPair[0].province.count < 4 { // QRZ uses state code, callParser has multiple state codes
      stationInformationCombined.spotterCountry += (", " + callSignPair[0].province)
      }
    }
    stationInformationCombined.spotterLatitude = callSignPair[0].latitude
    stationInformationCombined.spotterLongitude = callSignPair[0].longitude
    stationInformationCombined.spotterGrid = callSignPair[0].grid
    stationInformationCombined.spotterLotw = callSignPair[0].lotw
    stationInformationCombined.error = callSignPair[0].error

    stationInformationCombined.dxCall = callSignPair[1].call.trimmingCharacters(in: .whitespacesAndNewlines)
    stationInformationCombined.dxCountry = callSignPair[1].country
    stationInformationCombined.dxProvince = callSignPair[1].province
    if stationInformationCombined.dxCountry.contains("United States") {
      if callSignPair[1].province.count < 4 {
      stationInformationCombined.dxCountry += (", " + callSignPair[1].province)
      }
    }
    stationInformationCombined.dxLatitude = callSignPair[1].latitude
    stationInformationCombined.dxLongitude = callSignPair[1].longitude
    stationInformationCombined.dxGrid = callSignPair[1].grid
    stationInformationCombined.dxLotw = callSignPair[1].lotw
    if !stationInformationCombined.error {
      stationInformationCombined.error = callSignPair[1].error
    }

    let stationInfoCombined = stationInformationCombined
    processCallSignData(stationInformationCombined:
                          stationInfoCombined, clusterSpot: clusterSpot)
  }


  /// Do not process duplicate spots.
  /// - Parameter spot: ClusterSpot
  /// - Returns: Bool
  func checkForDuplicateSpot(spot: ClusterSpot) -> Bool {

    if displayedSpots.contains( where: {
      $0.dxStation == spot.dxStation &&
      $0.spotter == spot.spotter &&
      $0.formattedFrequency == spot.formattedFrequency
    } ) {
      return true
    }

    return false
  }

  // MARK: - Create Overlays and Annotations

  /// Have the spot create the overlay associated with it.
  /// - Parameters:
  ///   - stationInfoCombined: StationInformationCombined
  ///   - spot: ClusterSpot
  func processCallSignData(
    stationInformationCombined: StationInformationCombined,
    clusterSpot: ClusterSpot) {

     // need to make spot mutable
      var spot = clusterSpot
      if alertList.contains(spot.dxStation) {
        spot.isHighlighted = true
      }

      // populate the spot and create the polyline
      spot.populateSpotInformation(stationInformationCombined: stationInformationCombined)
      let overlay = spot.createOverlay()
      addOverlay(overlay: overlay)

      // create the two annotations for the spot
      let pins  = checkForExistingAnnotations(spot: &spot)
      for pin in pins {
        addAnnotation(annotation: pin)
      }

      // add the spot to the collection
      addSpot(spot: spot, doInsert: true)
    }

  /// Create the spotter and dx annotation. If a dx annotation already exists for that spot then just
  /// update the existing dx annotation.
  /// - Parameter spot: ClusterSpot
  /// - Returns: ClusterSpot
  func checkForExistingAnnotations(spot: inout ClusterSpot) -> [ClusterPinAnnotation] {
    var pins: [ClusterPinAnnotation] = []
    //let newSpot = spot // for debugging/logging only
    let matchingSpots = displayedSpots.filter( {$0.dxStation == spot.dxStation} )

    switch matchingSpots.count {
    case 0:
      let spotterAnnotation = spot.createSpotterAnnotation()
      pins.append(spotterAnnotation)
      //logger.log("Spotter annotation created: \(spotterAnnotation.station)")
      let dxAnnotation = spot.createDXAnnotation()
      pins.append(dxAnnotation)
      //logger.log("Dx annotation created: \(dxAnnotation.station)")
    default:
      let referenceSpot = matchingSpots.first
      // find the existing annotation
      let annotation = annotations.filter( {$0.hashValue == referenceSpot?.dxPinId} ).first

      if annotations.filter( {$0.hashValue == referenceSpot?.dxPinId} ).count > 1 {
        assertionFailure("Multiple annotations for same DX found.")
      }
      annotation?.addAnnotationTitle(dxStation: spot.dxStation, spotter: spot.spotter,formattedFrequency: spot.formattedFrequency)
      //logger.log("added title: \(newSpot.dxStation)-\(newSpot.spotter)-\(newSpot.formattedFrequency)")

      let spotterAnnotation = spot.createSpotterAnnotation()
      pins.append(spotterAnnotation)
      //logger.log("Spotter annotation created: \(spotterAnnotation.station)")


      //logger.log("DX annotation exists: \(newSpot.dxStation)")
      // new spot so need to update the id
      spot.dxPinId = referenceSpot!.dxPinId
    }

    return pins
  }

  // MARK: - Add and Delete Overlays, Annotations and Spots
  /// Add an overlay or polyline to the published collection.
  /// - Parameter overlay: The polyline connecting the spotter to the dx station
  func addOverlay(overlay: MKGeodesicPolyline) {
    Task { @MainActor in
      // TODO: fix filtering
      //if spot!.isFiltered == false { // && spot!.overlayExists == false
      overlays.append(overlay)
      //}
    }
  }

  /// Add an annotation to the published collection.
  /// - Parameter annotation: The pin dropped for the spotter or dx station.
  func addAnnotation(annotation: ClusterPinAnnotation) {
    Task { @MainActor in
      // TODO: fix filtering
      //if spot!.isFiltered == false { // && spot!.overlayExists == false
      annotations.append(annotation)
      //}
    }
  }

  /// Add a cluster spot to the published collection and the deleted collection.
  /// The deleted collection is used to check for duplicate spots from queries
  /// for multiple spots, DXSummit, show 25, show 50 commands.
  /// - Parameter spot: ClusterSpot
  /// - Parameter doDelete: Bool
  func addSpot(spot: ClusterSpot?, doInsert: Bool) {

    Task { @MainActor in
      if doInsert {
        displayedSpots.insert(spot!, at: 0)
        deletedSpots.insert(spot!, at: 0)
        // TODO: - This may need fixing
        //if spot!.isFiltered == false { // && spot!.overlayExists == false
        manageTotalSpotCount()
        //          }
      }
    }
  }

  /// Delete an annotation.
  /// - Parameter annotationId: Int
  func deleteAnnotation(annotationId: Int) {
    Task { @MainActor in
      logger.log("annotations deleted: \(annotationId)")
      for annotation in annotations.filter( { $0.hashValue == annotationId }) {
        annotation.isDeleted = true
      }
      annotations.removeAll(where: { $0.hashValue == annotationId })
    }
  }

  /// Limit the number of spots to the user selected limit.
  /// Manage the associated overlays and annotations.
  func manageTotalSpotCount() {
        logger.log("manage spots: \(self.displayedSpots.count)-\(self.maxNumberOfSpots)")
        if displayedSpots.count > maxNumberOfSpots {
          while displayedSpots.count > maxNumberOfSpots {
            //get the last spot
            let spot = displayedSpots[displayedSpots.count - 1]

            // get the associated overlay
            for overlay in overlays.filter( {$0.hashValue == spot.id }) {
              //overlay.isDeleted = true
              overlay.title = "isDeleted"
            }
            overlays.removeAll(where: { $0.hashValue == spot.id })
            //logger.log("deleted overlay for: \(spot.dxStation)-\(spot.spotter)-\(spot.id)")

            // delete the spotter annotation
            // deleteAnnotation(annotationId: spot.spotterPinId)
            for annotation in annotations.filter( {$0.hashValue == spot.spotterPinId }) {
              annotation.title = "isDeleted"
            }
            annotations.removeAll(where: { $0.hashValue == spot.spotterPinId })
            //logger.log("deleted spotter annotation for: \(spot.dxStation)-\(spot.spotter)-\(spot.spotterPinId)")

            // only delete the dx annotation if there are no other spots associated
            let spots = displayedSpots.filter( { $0.dxPinId == spot.dxPinId } )
            if spots.count == 1 {
              for annotation in annotations.filter( {$0.hashValue == spot.dxPinId }) {
                annotation.title = "isDeleted"
              }
              annotations.removeAll(where: { $0.hashValue == spot.dxPinId })
              //logger.log("deleted dx annotation for: \(spot.dxStation)-\(spot.spotter)-\(spot.dxPinId)")
            }

            let spotsToDelete = displayedSpots.filter( {$0.id == spot.id} )
            deletedSpots.append(contentsOf: spotsToDelete)

            displayedSpots.removeAll(where: {$0.id == spot.id} )
            //logger.log("deleted spot for: \(spot.dxStation)-\(spot.spotter)-\(spot.id)")

            while deletedSpots.count > (maxNumberOfSpots + 50) {
              deletedSpots.removeLast()
              logger.log("deleted spot cleanup")
            }
          }
        }
  }

  // MARK: - Alerts

  /// Highlight calls in the list. If an empty string is passed in clear existing highlights.
  /// - Parameter callSign: Callsign to set alert on.
  func setAlert(callSign: String) {

    guard !callSign.isEmpty else {
      alertList.removeAll()
      clearHighlights()
      return
    }

    alertList.append(callSign.uppercased())
    for call in alertList {
      highlightSpot(callSign: call)
    }
  }

  /// Mark a spot as highlighted.
  /// - Parameter callSign: Callsign to highlight.
  func highlightSpot(callSign: String) {
    Task { @MainActor in
        for (index, spot) in displayedSpots.enumerated() {
          if spot.dxStation == callSign {
            var mutatingSpot = spot
            mutatingSpot.isHighlighted = true
            displayedSpots[index] = mutatingSpot
          }
        }
    }
  }

  /// Clear all the highlighted spots.
  func clearHighlights() {
    Task { @MainActor in
        for (index, spot) in displayedSpots.enumerated() {
          if spot.isHighlighted {
            var mutatingSpot = spot
            mutatingSpot.isHighlighted = false
            displayedSpots[index] = mutatingSpot
          }
        }
    }
  }

  // MARK: - Filter Call Signs

  /// Remove overlays where the call sign does not match the filter.
  /// - Parameter callSign: String
  func setCallFilter(callSign: String) {

    callFilter = callSign.uppercased()

    resetAllCallFilters(filterState: false)

    if !callSign.isEmpty {
      updateCallFilterState(call: callSign, filterState: false)
    }

    filterOverlays()
    updateAnnotations()
  }

  /// Update the filter state on a spot.
  /// - Parameters:
  ///   - call: String
  ///   - setFilter: Bool
  func updateCallFilterState(call: String, filterState: Bool) {
    Task { @MainActor in
        if exactMatch {
          for (index, spot) in displayedSpots.enumerated() where spot.dxStation.prefix(call.count) != call {
            var mutatingSpot = spot
            mutatingSpot.manageFilters(reason: .call)
            displayedSpots[index] = mutatingSpot
          }
        } else {
          for (index, spot) in displayedSpots.enumerated() where !spot.dxStation.starts(with: call) {
            var mutatingSpot = spot
            mutatingSpot.manageFilters(reason: .call)
            displayedSpots[index] = mutatingSpot
          }
        }
    }
  }

  /// Reset all the call filters to the same state.
  /// - Parameter setFilter: FilterState
  func resetAllCallFilters(filterState: Bool) {
    Task {
      await MainActor.run {
        for (index, spot) in displayedSpots.enumerated() {
          var mutatingSpot = spot
          mutatingSpot.removeFilter(reason: .call)
          displayedSpots[index] = mutatingSpot
        }
      }
    }
  }

  // MARK: - Filter Digi

  func setDigiFilter(filterState: Bool) {
    Task {
      await MainActor.run {
        for (index, spot) in displayedSpots.enumerated() {
          var mutatingSpot = spot
          if filterState {
            if !checkIsDigi(spot: spot) {
              mutatingSpot.manageFilters(reason: .notDigi)
              displayedSpots[index] = mutatingSpot
            }
          } else {
            mutatingSpot.removeFilter(reason: .notDigi)
            displayedSpots[index] = mutatingSpot
          }
        }
      }
    }
    filterOverlays()
    updateAnnotations()
  }

  // MARK: - Digi Frequency Ranges

  func checkIsDigi(spot: ClusterSpot) -> Bool {

    guard let frequency = Float(spot.formattedFrequency) else { return false }
    //print("input: \(frequency.roundTo(places: 3))")
    switch Float(frequency.roundTo(places: 3)) {
    case 1.840...1.845:
      return true
    case 1.84...1.845:
      return true
//    case 3.568...3.570:
//      return true
//    case 3.568...3.57:
//      return true
    case 3.573...3.578:
      return true
    case 5.357:
      return true
//    case 7.047...7.052:
//      return true
//    case 7.056...7.061:
//      return true
    case 7.074...7.078:
      return true
//    case 10.130...10.135:
//      return true
//    case 10.13...10.135:
//      return true
//    case 10.136...10.138:
//      return true
//    case 10.140...10.145:
//      return true
    case 10.136...10.145:
      return true
    case 14.074...14.078:
      return true
    case 14.080...14.082:
      return true
    case 14.08...14.082:
      return true
//    case 14.090...14.095:
//      return true
//    case 14.09...14.095:
//      return true
    case 18.100...18.106:
      return true
    case 18.10...18.106:
      return true
    case 18.1...18.106:
      return true
//    case 18.104...18.106:
//      return true
    case 21.074...21.078:
      return true
//    case 21.091...21.094:
//      return true
    case 21.140...21.142:
      return true
    case 21.14...21.142:
      return true
    case 24.915...24.922:
      return true
    case 28.074...28.078:
      return true
    case 28.180...28.182:
      return true
    case 28.18...28.182:
      return true
    case 50.313...50.320:
      return true
    case 50.323...50.328:
      return true
    default:
      //print("output: \(spot.formattedFrequency)")
      return false
    }
  }

  // MARK: - Filter Bands

  /// Manage the band button state. If the button is in the "on" position then no spots from that
  /// band will show on the map.
  /// - Parameters:
  ///   - band: Int
  ///   - state: Bool
  func setBandButtons( band: Int, state: Bool) {

    switch state {
    case true:
      if band != 0 {
        bandFilters[Int(band)] = .isOn
      } else {
        // turn off all bands
        bandFilters.keys.forEach { bandFilters[$0] = .isOn }
        resetAllBandSpotFilters(filterState: state)
        deleteExistingData(includeSpots: false)
        return
      }
    case false:
      if band != 0 {
        bandFilters[Int(band)] = .isOff
      } else {
        // turn on all bands
        bandFilters.keys.forEach { bandFilters[$0] = .isOff }
        resetAllBandSpotFilters(filterState: state)
        filterOverlays()
        updateAnnotations()
        return
      }
    }

    updateBandFilterState(band: band, filterState: state)
    filterOverlays()
    updateAnnotations()
  }

  /// Update the filter state on a spot.
  /// - Parameters:
  ///   - band: Int
  ///   - setFilter: Bool
  func updateBandFilterState(band: Int, filterState: Bool) {
    Task {
      await MainActor.run {
        for (index, spot) in displayedSpots.enumerated() where spot.band == band {
          var mutatingSpot = spot
          mutatingSpot.manageFilters(reason: .band)
          displayedSpots[index] = mutatingSpot
        }
      }
    }
  }

  /// Set all the band filters to the same state on all spots.
  /// - Parameter setFilter: FilterState
  func resetAllBandSpotFilters(filterState: Bool) {
    Task {
      await MainActor.run {
        for (index, spot) in displayedSpots.enumerated() {
          var mutatingSpot = spot
          mutatingSpot.manageFilters(reason: .band)
          displayedSpots[index] = mutatingSpot
        }
      }
    }
  }

  // MARK: - Filter Overlays

  /// Filter overlays.
  func filterOverlays() {
    Task {
      await MainActor.run {

//        let unfilteredSpots = displayedSpots.filter({$0.isFiltered == false})
//        for spot in unfilteredSpots {
          // TODO: - This needs fixing
//          if overlays.first(where: {$0.hashValue == spot.id}) == nil {
//            overlays.append(spot.overlay!)
//          }
//        }

        let filteredSpots = displayedSpots.filter({$0.isFiltered == true})
        for spot in filteredSpots {
            overlays.removeAll(where: { $0.hashValue == spot.id })
        }
      }
    }
  }

  /// Delete a duplicate annotation
  /// - Parameter annotationId: Int
//  func deleteOverlay(spotId: Int) {
//    Task {
//      await MainActor.run {
//        for (index, overlay) in overlays.enumerated() where overlay.hashValue == spotId {
//          overlays[index].subtitle = "isDeleted"
//          overlays.remove(at: index)
//        }
//      }
//    }
//  }


  /// Filter the annotations or flags at each end of an overlay.
  func updateAnnotations() {
    Task {
      await MainActor.run {
        for spot in displayedSpots {
          if spot.isFiltered == false {
            // TODO: - Fix this
            if annotations.first(where: {$0.hashValue == spot.spotterPinId}) == nil {
//              annotations.append(spot.spotterPin)
//              if spot.hasDxPin {
//                annotations.append(spot.dxPin)
//              }
            }
          } else {
            var annotation = annotations.filter( { $0.hashValue == spot.spotterPinId } ).first
            annotation?.subtitle = "expired"
            annotation = annotations.filter( { $0.hashValue == spot.dxPinId } ).first
            annotation?.subtitle = "expired"
            deleteAnnotation(annotationId: spot.spotterPinId)
            // TODO: ???
//            if spot.hasDxPin {
//              deleteAnnotation(annotationId: spot.dxPinId)
//            }
          }
        }
      }
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
