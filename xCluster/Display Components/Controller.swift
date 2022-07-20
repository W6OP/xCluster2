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

/// Stub between view and all other classes
public class  Controller: ObservableObject, TelnetManagerDelegate, WebManagerDelegate {

  let logger = Logger(subsystem: "com.w6op.xCluster", category: "Controller")

  // MARK: - Published Properties

  @Published var annotations = [ClusterPinAnnotation]()
  @Published var displayedSpots = [ClusterSpot]()
  @Published var statusMessages = [StatusMessage]()
  @Published var overlays = [ClusterMKGeodesicPolyline]()

  @Published var bandFilter = (id: 0, state: BandFilterState.isOff) {
    didSet {
      setBandButtons(band: bandFilter.id, state: bandFilter.state)
    }
  }

  @Published var digiOnly = false {
    didSet {
      if digiOnly {
        setDigiFilter()
      } else {
        resetDigiFilter()
      }
    }
  }

  @Published var callToFilter = ""
  {
    didSet {
      if callToFilter.isEmpty {
        resetCallFilter()
      } else {
        //resetCallFilter()
        setCallFilter() // callToFilter: callToFilter.uppercased()
      }
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

  var pause = false

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
                     6: BandFilterState.isOff, 2: BandFilterState.isOff]


  var alertList: [String] = []
  // these is set by the Checkbox views in the ContentView
  var exactMatch = false
  var previousCallFilter = ""

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
  /// - Parameter clusterName: String:  name of the cluster to connect to.
  func connect(cluster: ClusterIdentifier, isReconnection: Bool) {
    
    if connectedCluster.id != 9999 {
      
      if activeCluster != nil {
        disconnect(activeCluster: activeCluster)
      }
      //print("Current thread 1: \(Thread.current.threadName)")
      
      Task {
        //print("Current thread 2: \(Thread.current.threadName)")
        await spotCache.clear()
        await hitsCache.clear()
      }

      //print("Current thread 3: \(Thread.current.threadName)")

        deleteAllAnnotations()
        deleteAllOverlays()
        displayedSpots.removeAll()
        deletedSpots.removeAll()
      
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
  /// - Returns: Bool:
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
  /// - Parameter includeSpots: Bool: remove spots in addition to overlays and annotations.
  func deleteExistingData(includeSpots: Bool) {
    //print("Current thread: \(Thread.current.threadName)")
    switch includeSpots {
    case true:
      deleteAllOverlays()
      deleteAllAnnotations()

      displayedSpots.removeAll()
      deletedSpots.removeAll()
    case false:
      deleteAllOverlays()
      deleteAllAnnotations()
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

    case .clusterInformation:
      let messages = limitMessageLength(message: message)
      for item in messages {
        appendStatusMessage(message: item.condenseWhitespace())
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
    Task { @MainActor in
        let statusMessage = StatusMessage(message: message)
        self.statusMessages.append(statusMessage) //= [statusMessage]
      }
  }


  /// Insert a status message at the beginning.
  /// - Parameter message: String
  func insertStatusMessage(message: String) {
    Task { @MainActor in
        let statusMessage = StatusMessage(message: message)
        self.statusMessages.insert(statusMessage, at: 0) //= [statusMessage]
      }
  }

  /// Clear all status messages.
  func clearStatusMessages() {
    Task { @MainActor in
      self.statusMessages.removeAll()
      }
  }


  /// Limit the number of status messages.
  func limitStatusMessages() {
    Task { @MainActor in
        if (self.statusMessages.count) > maxStatusMessages {
          self.statusMessages.removeFirst()
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

      if deletedSpots.firstIndex(where: { $0.spotterStation == spot.spotterStation &&
        $0.dxStation == spot.dxStation && $0.band == spot.band
      }) != nil {
        //logger.info("Duplicate deleted spot found: \(spot.spotter)-\(spot.dxStation)")
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

    // TODO: - WHY ARE THE BAND FILTERS OFF HERE FOR DXSUMMIT BUT OK FOR TELNET SPOTS
    applyFilters(&spot)
    //await applyAlerts()

    await spotCache.addSpot(spot: spot)

    let callSigns = [spot.spotterStation, spot.dxStation]
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

  // TODO: NEEDS WORK
  /// Check if the incoming spot needs to be filtered.
  /// - Parameter spot: ClusterSpot
  func applyFilters(_ spot: inout ClusterSpot) {
    if bandFilters[Int(spot.band)] == .isOn {
      spot.manageFilters(filterType: .band)
    }

    if !callToFilter.isEmpty {
      if spot.dxStation.prefix(callToFilter.count) != callToFilter {
        spot.manageFilters(filterType: .call)
      }
    }

    if digiOnly {
      if !spot.isDigiMode {
        spot.manageFilters(filterType: .notDigi)
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
      $0.spotterStation == spot.spotterStation &&
      $0.formattedFrequency == spot.formattedFrequency
    } ) {
      return true
    }

    return false
  }

  // TODO: - TRY TO FIND A USE FOR THE NEW CHARTS IN NEW SWIFTUI

  /// Have the spot create the overlay associated with it.
  /// - Parameters:
  ///   - stationInfoCombined: StationInformationCombined
  ///   - spot: ClusterSpot
  func processCallSignData(
    stationInformationCombined: StationInformationCombined,
    clusterSpot: ClusterSpot) {

      if pause {return}

      //print("Current thread: \(Thread.current.threadName)")
      Task { @MainActor in
        // need to make spot mutable
        var spot = clusterSpot
        // populate the spot
        spot.populateSpotInformation(stationInformationCombined: stationInformationCombined)
        if alertList.contains(spot.dxStation) {
          spot.isHighlighted = true
        }

        // TODO: - This doesn't work, should not add overlay if spot is filtered
        // TODO: - What if both stations spot each other?
        // need to check if an overlay - or both annotations already exists

        if !spot.isFiltered {
          let overlay = spot.createOverlay()
          addOverlay(overlay: overlay)
          print("add overlay: \(spot.spotterStation)-\(spot.dxStation)")

          if !checkForExistingAnnotations(station: spot.spotterStation) {
            buildAnnotation(spot: &spot, annotationType: .spotter)
          } else {
            updateAnnotation(spot: &spot, annotationType: .spotter)
          }

          if !checkForExistingAnnotations(station: spot.dxStation) {
            buildAnnotation(spot: &spot, annotationType: .dx)
          } else {
            updateAnnotation(spot: &spot, annotationType: .dx)
          }
        }

        // add the spot to the collection
        addSpot(spot: spot, doInsert: true)
      }
    }

  /// Check to see if the dx annotation already exists.
  /// - Parameter spot: ClusterSpot:
  /// - Returns: Bool: true if the dx annotation exists.
  func checkForExistingAnnotations(station: String) -> Bool {

    let matchingAnnotations = annotations.filter( {$0.annotationStation == station} )

    guard matchingAnnotations.count <= 1 else {
      assertionFailure("Multiple annotations for same station found.")
      return true
    }

    switch matchingAnnotations.count {
    case 0: // will create 2 pins
      return false
    case 1:
      return true
    default: // assume dx annotation exists
      break
    }
    return false
  }

  /// Build spotter annotation. Build dx annotation if it does not already exist.
  /// - Parameters:
  ///   - spot: ClusterSpot:
  ///   - annotationType: ClusterPinAnnotationType: create one or both annotations
  func buildAnnotation(spot: inout ClusterSpot, annotationType: ClusterPinAnnotationType) {

    switch annotationType {
    case.spotter:
      let spotterAnnotation = spot.createSpotterAnnotation()
      addAnnotation(annotation: spotterAnnotation)
    case .dx:
      let dxAnnotation = spot.createDXAnnotation()
      addAnnotation(annotation: dxAnnotation)
    default:
      break
    }
  }

  /// Update the annotation title with the new spot information.
  /// - Parameters:
  ///   - spot: ClusterSpot
  ///   - annotationType: ClusterPinAnnotationType: the type of annotation.
  func updateAnnotation(spot: inout ClusterSpot, annotationType: ClusterPinAnnotationType) {

    switch annotationType {
    case .dx:
      let matchingAnnotation = annotations.filter( {$0.annotationStation == spot.dxStation} ).first
      matchingAnnotation?.addAnnotationTitle(dxStation: spot.dxStation, spotterStation: spot.spotterStation, formattedFrequency: spot.formattedFrequency)
    case .spotter:
      let matchingAnnotation = annotations.filter( {$0.annotationStation == spot.spotterStation} ).first
      matchingAnnotation?.addAnnotationTitle(dxStation: spot.dxStation, spotterStation: spot.spotterStation, formattedFrequency: spot.formattedFrequency)
    default:
      break
    }
  }

  // MARK: - Add and Delete Overlays, Annotations and Spots
  /// Add an overlay or polyline to the published collection.
  /// - Parameter overlay: The polyline connecting the spotter to the dx station
  func addOverlay(overlay: ClusterMKGeodesicPolyline) {
      overlays.append(overlay)
  }

  /// Add an annotation to the published collection.
  /// - Parameter annotation: The pin dropped for the spotter or dx station.
  func addAnnotation(annotation: ClusterPinAnnotation) {
      annotations.append(annotation)
  }

  /// Add a cluster spot to the published collection and the deleted collection.
  /// The deleted collection is used to check for duplicate spots from queries
  /// for multiple spots, DXSummit, show 25, show 50 commands.
  /// - Parameter spot: ClusterSpot
  /// - Parameter doDelete: Bool
  @MainActor func addSpot(spot: ClusterSpot?, doInsert: Bool) {
      if doInsert {
        displayedSpots.insert(spot!, at: 0)
        deletedSpots.insert(spot!, at: 0)
        manageTotalSpotCount()
        applyAlerts()
      }
  }

  /// Delete an overlay.
  /// - Parameter overlayId: Int: hashValue of the overlay to be deleted.
  func deleteOverlayById(overlayId: ObjectIdentifier, log: String) {

    guard overlays.filter( { ObjectIdentifier($0) == overlayId }).count == 1 else {
      assertionFailure("overlay not found")
      print("overlay id not found: \(log)-\(overlayId)")
      return
    }

    let overlay = overlays.filter( { ObjectIdentifier($0) == overlayId }).first
    overlay!.title = objectStatus.isDeleted.rawValue

    //print("overlayById deleted: \(log)-\(ObjectIdentifier(overlay!))")

    //overlays.removeAll(where: { $0.title == objectStatus.isDeleted.rawValue })
  }

  /// Delete a spotter annotation.
  ///
  /// This is only used when applying filters
  /// - Parameters:
  ///   - annotationId: id of the annotation
  ///   - dxStation: String
  ///   - scope: Scope
  func deleteSpotterAnnotation(annotationId: UUID, dxStation: String, scope: Scope) {

    for annotation in annotations.filter( { $0.annotationType == .spotter && $0.annotationId == annotationId }) {
      switch scope {
      case .all:
        annotation.setAsDeleted()
      case .selective:
        updateMatchingAnnotations(station: annotation.annotationStation)
      }
    }

    annotations.removeAll(where: { $0.title == objectStatus.isDeleted.rawValue })
  }

  /// Remove a reference to a deleted annotation.
  /// - Parameter station: String: station name to remove.
  func updateMatchingAnnotations(station: String) {
    print("update matching annotation: \(station)")
    let matchingAnnotations = annotations.filter( {$0.matchReference.contains(station)})
    for annotation in matchingAnnotations {
      print("removeAnnotationReference: \(station)")
      annotation.removeAnnotationReference(station: station)
    }

    annotations.removeAll(where: { $0.title == objectStatus.isDeleted.rawValue })
  }

  func updateMatchingAnnotations(spotter: String, dx: String, flag: String) {
    print("update matching annotation: \(flag)")

    guard (annotations.filter( {$0.annotationStation == spotter}).count == 1) else {
      //assertionFailure("missing or excess annotation")
      return
    }

    let matchingAnnotation = annotations.filter( {$0.annotationStation == spotter}).first
    matchingAnnotation?.removeAnnotationReference(station: dx)

    // this can probably be moved to manageTotalSpots
    //annotations.removeAll(where: { $0.title == objectStatus.isDeleted.rawValue })
  }

  /// Delete a dx annotation only if no other spotters reference it.
  ///
  /// This is only used when applying filters
  /// - Parameters:
  ///   - annotationId: Int: annotation.hashValue
  ///   - spotterStation: String: spotter call sign.
  ///   - scope: Scope: delete anyway or only if no other references.
  func deleteDxAnnotation(annotationId: UUID, spotterStation: String, scope: Scope) {
    for annotation in annotations.filter( { $0.annotationType == .dx && $0.annotationId == annotationId }) {
      switch scope {
      case .all:
        annotation.setAsDeleted()
      case .selective:
        updateMatchingAnnotations(station: annotation.annotationStation)
      }
    }
    //annotations.removeAll(where: { $0.title == objectStatus.isDeleted.rawValue })
  }

  /// Delete all annotations.
  func deleteAllAnnotations() {
    for annotation in annotations {
      deleteAllAnnotationsById(annotationId: annotation.annotationId)
    }
    annotations.removeAll(where: { $0.title == objectStatus.isDeleted.rawValue })
  }

  /// Delete annotations by id.
  /// - Parameter annotationId: UUID:  annotation Id
  func deleteAllAnnotationsById(annotationId: UUID) {
    for annotation in annotations.filter( { $0.annotationId == annotationId }) {
      annotation.setAsDeleted()
    }
  }

  /// Mark all overlays as deleted.
  func deleteAllOverlays() {
    for overlay in overlays {
      overlay.title = objectStatus.isDeleted.rawValue
    }
    overlays.removeAll(where: { $0.title == objectStatus.isDeleted.rawValue })
  }

  // MARK: - Manage Total Spot Count

  /// Limit the number of spots to the user selected limit.
  /// Manage the associated overlays and annotations.
  func manageTotalSpotCount() {
    if displayedSpots.count > maxNumberOfSpots {
      while displayedSpots.count > maxNumberOfSpots {
        //get the last spot
        let spot = displayedSpots[displayedSpots.count - 1]
        print("find spot to delete: \(spot.spotterStation) to \(spot.dxStation)")

        deleteOverlayById(overlayId: spot.overlayId!, log: " \(spot.spotterStation) to \(spot.dxStation)")
        print("delete the associated overlay: \(spot.spotterStation) to \(spot.dxStation)")

        updateMatchingAnnotations(spotter: spot.spotterStation, dx: spot.dxStation, flag: spot.spotterStation)
        updateMatchingAnnotations(spotter: spot.dxStation, dx: spot.spotterStation, flag: spot.dxStation)

        let spotToDelete = displayedSpots.filter( {$0.id == spot.id} ).first!
        deletedSpots.append(spotToDelete)

        displayedSpots.removeAll(where: {$0.id == spot.id} )
        print("spot deleted: \(spot.spotterStation) to \(spot.dxStation)")

        // clean the deleted spots list
        while deletedSpots.count > (maxNumberOfSpots + 50) {
          deletedSpots.removeLast()
        }
      }
    }

    annotations.removeAll(where: { $0.title == objectStatus.isDeleted.rawValue })
    overlays.removeAll(where: { $0.title == objectStatus.isDeleted.rawValue })

    // hack
    //print("deleting overlays: \(overlays.filter( {$0.title == overlayStatus.isDeleted.rawValue} ).count)")
//    guard overlays.filter( {$0.title == objectStatus.isDeleted.rawValue} ).count == 0 else {
//      overlays.removeAll(where: {$0.title == objectStatus.isDeleted.rawValue} )
//      assertionFailure("why does this happen")
//      return
//    }
  }

  // MARK: - Alerts

  /// Add an entry to the alert list. If an empty string is passed in clear existing highlights.
  /// - Parameter callSign: Callsign to set alert on.
  @MainActor func setAlert(callSignOrCountry: String) {

    guard !callSignOrCountry.isEmpty else {
      alertList.removeAll()
      clearHighlights()
      return
    }

    if !alertList.contains(callSignOrCountry) {
      alertList.append(callSignOrCountry)
    }

    applyAlerts()
  }

  /// Apply the alerts in the list.
  @MainActor func applyAlerts() {
    //print("Current thread: \(Thread.current.threadName)")
    for literal in alertList {
      switch literal { // must be in this order
      case _ where literal.isLetters():
        highlightCountry(country: literal)
      case _ where literal.isAlphanumeric():
        highlightCall(call: literal.uppercased())
      case _ where literal.suffix(1) == ("*"):
        if String(literal.prefix(literal.count - 1)).isLetters() {
          highlightCountry(country: literal.uppercased())
        } else {
          highlightCall(call: literal.uppercased())
        }
      default:
        break
      }
    }
  }

  /// Mark a spot as highlighted using the call sign.
  /// - Parameter callSign: Callsign to highlight.
  func highlightCall(call: String) {
    for (index, spot) in displayedSpots.enumerated() {
      var mutatingSpot = spot
      switch call {
      case _ where call.suffix(1) == ("*"):
        let callPrefix = call.prefix(call.count - 1)
        if spot.dxStation.contains(callPrefix) {
          mutatingSpot.isHighlighted = true
          displayedSpots[index] = mutatingSpot
        }
        break
      case _ where spot.dxStation == call:
        mutatingSpot.isHighlighted = true
        displayedSpots[index] = mutatingSpot
      default:
        break
      }
    }
  }

  /// Mark a spot as highlighted using the country.
  /// - Parameter callSign: Callsign to highlight.
  func highlightCountry(country: String) {
    for (index, spot) in displayedSpots.enumerated() {
      var mutatingSpot = spot
      let dxCountry = spot.dxCountry.uppercased()
      switch country {
      case _ where country.suffix(1) == ("*"):
        let countryPrefix = country.prefix(country.count - 1).uppercased()
        if dxCountry.contains(countryPrefix) {
          mutatingSpot.isHighlighted = true
          displayedSpots[index] = mutatingSpot
        }
        break
      case _ where dxCountry == country.uppercased():
        mutatingSpot.isHighlighted = true
        displayedSpots[index] = mutatingSpot
      default:
        break
      }
    }
  }

  /// Clear all the highlighted spots.
  func clearHighlights() {
    for (index, spot) in displayedSpots.enumerated() {
      if spot.isHighlighted {
        var mutatingSpot = spot
        mutatingSpot.isHighlighted = false
        displayedSpots[index] = mutatingSpot
      }
    }
  }

  // MARK: - Filter Call Signs

  /// Set the call filter on and filter spots that do not have the DX call in them.
  /// - Parameter callToFilter: String: Call sign to filter.
  func setCallFilter() {
    if exactMatch {
      for (index, spot) in displayedSpots.enumerated() where spot.dxStation.prefix(callToFilter.count) != callToFilter {
        var mutatingSpot = spot
        mutatingSpot.manageFilters(filterType: .call)
        if mutatingSpot.isFiltered {
          deleteOverlayById(overlayId: spot.overlayId!, log: " \(spot.spotterStation) to \(spot.dxStation)")
          deleteSpotterAnnotation(annotationId: spot.spotterAnnotationId, dxStation: spot.dxStation, scope: .all)
          deleteDxAnnotation(annotationId: spot.dxAnnotationId, spotterStation: spot.spotterStation, scope: .all)
        }
        displayedSpots[index] = mutatingSpot
      }
    } else {
      for (index, spot) in displayedSpots.enumerated() where !spot.dxStation.starts(with: callToFilter) {
        var mutatingSpot = spot
        mutatingSpot.manageFilters(filterType: .call)
        if mutatingSpot.isFiltered {
          deleteOverlayById(overlayId: spot.overlayId!, log: " \(spot.spotterStation) to \(spot.dxStation)")
          deleteSpotterAnnotation(annotationId: spot.spotterAnnotationId, dxStation: spot.dxStation, scope: .all)
          deleteDxAnnotation(annotationId: spot.dxAnnotationId, spotterStation: spot.spotterStation, scope: .all)
        }
        displayedSpots[index] = mutatingSpot
      }
    }
  }

  /// Remove the existing call filter.
  func resetCallFilter() {
    for (index, spot) in displayedSpots.enumerated() {
      var mutatingSpot = spot
      mutatingSpot.manageFilters(filterType: .call)
      if !mutatingSpot.isFiltered {
        regenerateOverlayAndAnnotations(spot: &mutatingSpot)
      }
      displayedSpots[index] = mutatingSpot
    }
  }

  // MARK: - Filter Digi QSOs

  /// Set the filter on non digital spots.
  func setDigiFilter() {
    for (index, spot) in displayedSpots.enumerated() {
      var mutatingSpot = spot
      if !spot.isDigiMode {
        if mutatingSpot.isFiltered == false { // could be band filtered
          deleteOverlayById(overlayId: spot.overlayId!, log: " \(spot.spotterStation) to \(spot.dxStation)")
          deleteSpotterAnnotation(annotationId: spot.spotterAnnotationId, dxStation: spot.dxStation, scope: .all)
          // TODO: - Check this, what if DX is multi mode
          deleteDxAnnotation(annotationId: mutatingSpot.dxAnnotationId, spotterStation: mutatingSpot.spotterStation, scope: .all)
        }
        mutatingSpot.manageFilters(filterType: .notDigi)
        displayedSpots[index] = mutatingSpot
      }
    }
  }

  /// Reset the filter on non digital spots.
  func resetDigiFilter() {
    for (index, spot) in displayedSpots.enumerated() where spot.isFiltered {
      var mutatingSpot = spot
      mutatingSpot.manageFilters(filterType: .notDigi)
      if mutatingSpot.isFiltered == false {
        regenerateOverlayAndAnnotations(spot: &mutatingSpot)
      }
      displayedSpots[index] = mutatingSpot
    }
  }

  // MARK: - Filter Bands

  /// Manage the band button state. If the button is in the "on" position then no spots from that
  /// band will show on the map.
  /// A band value of 0 means the setting applies to all bands
  /// - Parameters:
  ///   - band: The band to change the filter state on. A zero indicates all bands
  ///   - state: State to set the filter for the band(s).
  func setBandButtons( band: Int, state: BandFilterState) {
    switch state {
    case .isOn: // filter spots
      if band != 0 {
        bandFilters[Int(band)] = .isOn
      } else {
        // turn off all bands
        bandFilters.keys.forEach { bandFilters[$0] = .isOn }
        setAllBandFiltersOn()
        return
      }
    case .isOff: // unfilter spots
      if band != 0 {
        bandFilters[Int(band)] = .isOff
      } else {
        // turn on all bands
        bandFilters.keys.forEach { bandFilters[$0] = .isOff }
        resetAllBandFilters()
        return
      }
    }

    updateBandFilterState(band: band)
  }

  /// Update the filter state on a spot.
  /// - Parameters:
  ///   - band: Int
  ///   - setFilter: Bool
  func updateBandFilterState(band: Int) {
    for (index, spot) in displayedSpots.enumerated() where spot.band == band {

      var mutatingSpot = spot
      mutatingSpot.manageFilters(filterType: .band)

      if mutatingSpot.isFiltered {
        updateMatchingAnnotations(station: spot.dxStation)
        updateMatchingAnnotations(station: spot.spotterStation)
        deleteOverlayById(overlayId: spot.overlayId!, log: " \(spot.spotterStation) to \(spot.dxStation)")
      } else {
        regenerateOverlayAndAnnotations(spot: &mutatingSpot)
      }
      // this must be last or changes are not updated
      displayedSpots[index] = mutatingSpot
    }
  }

  /// Recreate the overlays and annotations that were deleted by a filter.
  /// - Parameter spot: ClusterSpot to be returned.
  func regenerateOverlayAndAnnotations( spot: inout ClusterSpot) {
    let overlay = spot.createOverlay()
    addOverlay(overlay: overlay)

    if !checkForExistingAnnotations(station: spot.spotterStation) {
      buildAnnotation(spot: &spot, annotationType: .spotter)
    }

    if !checkForExistingAnnotations(station: spot.dxStation) {
      buildAnnotation(spot: &spot, annotationType: .dx)
    }
  }

  /// Set all band filters to an on state so no overlays or annotations are displayed.
  func setAllBandFiltersOn() {
    for (index, spot) in displayedSpots.enumerated() {
      var mutatingSpot = spot
      mutatingSpot.manageFilters(filterType: .band)
      deleteOverlayById(overlayId: spot.overlayId!, log: " \(spot.spotterStation) to \(spot.dxStation)")
      displayedSpots[index] = mutatingSpot
    }
    deleteAllAnnotations()
  }

  /// Set all the band filters to off for all spots.
  func resetAllBandFilters() {
    logger.info("reset all band filters")
    for (index, spot) in displayedSpots.enumerated() where spot.isFiltered {
      var mutatingSpot = spot
      mutatingSpot.manageFilters(filterType: .band)
      if !mutatingSpot.isFiltered {
        regenerateOverlayAndAnnotations(spot: &mutatingSpot)
      }

      displayedSpots[index] = mutatingSpot
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
