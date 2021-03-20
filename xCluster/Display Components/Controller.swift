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

// MARK: - ClusterSpots

struct ClusterSpot: Identifiable, Hashable {
  var id: Int
  var dxStation: String
  var frequency: String
  var spotter: String
  var dateTime: String
  var comment: String
  var grid: String
}

// MARK: - Controller Class

// Good read on clusters
// https://www.hamradiodeluxe.com/blog/Ham-Radio-Deluxe-Newsletter-April-19-2018--Understanding-DX-Clusters.html

/// <#Description#>
public class  Controller: ObservableObject, TelnetManagerDelegate, QRZManagerDelegate {

  private let concurrentSpotProcessorQueue =
    DispatchQueue(
      label: "com.w6op.virtualcluster.spotProcessorQueue",
      attributes: .concurrent)

  @Published var spots = [ClusterSpot]()
  @Published var statusMessage = [String]()
  @Published var haveSessionKey = false
  @Published var overlays = [MKPolyline]()

  @Published var filter = (id: 0, state: false) {
    didSet {
      setBandButtons(buttonTag: filter.id, state: filter.state)
    }
  }

  @Published var connectedCluster = "" {
    didSet {
      if !connectedCluster.isEmpty {
        connect(clusterName: connectedCluster)
      }
    }
  }

  @Published var clusterCommand = (tag: 0, command: "") {
    didSet {
      sendClusterCommand(tag: clusterCommand.tag, command: clusterCommand.command)
    }
  }

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
  let maxNumberOfSpots = 1000
  let maxNumberOfMapLines = 50
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

  var bandFilters = [Int: Int]()

  var lastSpotReceivedTime = Date()

  // MARK: - Initialization

  init () {

    bandFilters = [99: 99, 160: 160, 80: 80, 60: 60, 40: 40, 30: 30, 20: 20, 18: 18, 15: 15, 12: 12, 10: 10, 6: 6]

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
  func  connect(clusterName: String) {

    disconnect()
    let cluster = clusterData.first(where: {$0.name == clusterName})

      // clear the status message
    DispatchQueue.main.async {
        if !cluster!.address.isEmpty {
            self.statusMessage = [String]()
          }
        }

    self.telnetManager.connect(host: cluster!.address, port: cluster!.port)
  }

  /// Disconnect on cluster change or application termination.
  func disconnect() {
    telnetManager.disconnect()
  }

  /// Reconnect when the connection drops.
  func reconnectCluster() {
    print("Reconnect attempt")
    disconnect()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
        self.reconnect()
    }
  }

   /// Telnet Manager protocol - Process a status message from the Telnet Manager.
   /// - parameters:
   /// - telnetManager: Reference to the class sending the message.
   /// - messageKey: Key associated with this message.
   /// - message: message text.
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
        print("Error: \(message)")
        self.statusMessage.append(message)
      }

    case .callSignRequested:
      self.sendClusterCommand(message: "\(callSign)", commandType: CommandType.logon)

    case .nameRequested:
      self.sendClusterCommand(message: "set/name \(fullName)", commandType: CommandType.callsign)

    case .qthRequested:
      self.sendClusterCommand(message: "set/qth \(location)", commandType: CommandType.setQth)

    case .location:
      self.sendClusterCommand(message: "set/qra \(grid)", commandType: CommandType.message)// want lat/long

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
        // don't propagate to xCluster
        if self.statusMessage.count > 200 {
        self.statusMessage.removeFirst()
      }
    }
  }

   /// Telnet Manager protocol - Process information messages from the Telnet Manager
   /// - parameters:
   /// - telnetManager: Reference to the class sending the message.
   /// - messageKey: Key associated with this message.
   /// - message: message text.
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
      // don't propagate to xCluster
      if self.statusMessage.count > 200 {
        self.statusMessage.removeFirst()
      }
    }
  }

  // MARK: - QRZ Implementation ----------------------------------------------------------------------------

   /// QRZ Manager protocol - Retrieve the session key from QRZ.com
  ///
   /// - parameters:
   /// - qrzManager: Reference to the class sending the message.
   /// - messageKey: Key associated with this message.
   /// - message: message text.
  func qrzManagerdidGetSessionKey(_ qrzManager: QRZManager, messageKey: QRZManagerMessage, haveSessionKey: Bool) {
    DispatchQueue.main.async {
      self.haveSessionKey = haveSessionKey
    }
  }

  /**
   QRZ Manager protocol - Receive the call sign data QRZ.com.
   - parameters:
   - qrzManager: Reference to the class sending the message.
   - messageKey: Key associated with this message.
   - message: message text.
   */
  func qrzManagerDidGetCallSignData(_ qrzManager: QRZManager, messageKey: QRZManagerMessage, qrzInfoCombined: QRZInfoCombined) {

    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      self!.buildMapLines(qrzInfoCombined: qrzInfoCombined)
    }
  }

  func getQRZSessionKey() {
    self.qrzManager.parseQRZSessionKeyRequest(name: self.qrzUserName, password: self.qrzPassword)
  }

  // MARK: - Cluster Login and Commands

  /**
   Send the operators call sign to the telnet server.
   set/name Ian
   set/qth Morecambe, Lancashire IO84NB
   set/location 48 34 n 12 12 e
   set/qra IO84NB
   set/home gb7mbc
   */
  func sendLogin() {
    sendClusterCommand(message: qrzUserName, commandType: .logon)
  }

  func sendPersonalData() {
    /**
     set/name Ian
     set/qth Morecambe, Lancashire IO84NB
     set/location 48 34 n 12 12 e
     set/qra IO84NB
     set/home gb7mbc
     */

    sendClusterCommand(message: "set/name \(fullName)", commandType: .ignore)
    sendClusterCommand(message: "set/qth \(location)", commandType: .ignore)
    sendClusterCommand(message: "set/qra \(grid)", commandType: .ignore)
    //sendClusterCommand(message: "set/ft8", commandType: .ignore)
  }

  /**
   Send a message or command to the telnet manager.
   - parameters:
   - message: The data sent.
   - commandType: The type of command sent.
   */
  func sendClusterCommand (message: String, commandType: CommandType) {
    telnetManager.send(message, commandType: commandType)
  }

  /**
   Send a message or command to the telnet manager.
   - parameters:
   - tag: The tag value from the button to identify what command needs to be sent.
   - commandType: The type of command sent.
   */
  func sendClusterCommand(tag: Int, command: String) {

    switch tag {
    case 20:
      telnetManager.send("show/fdx 20", commandType: .getDxSpots)
    case 50:
      telnetManager.send("show/fdx 50", commandType: .getDxSpots)
    default:
      telnetManager.send(command, commandType: .ignore)
    }
  }

  func limitMessageLength(message: String) -> [String] {

    var messages = [String]()

    if message.count > 80 {
      messages = message.components(withMaxLength: 80)
    } else {
      messages.append(message)
    }

    return messages
  }

  /**
   "DX de W3EX:      28075.6  N9AMI                                       1912Z FN20\a\a"
   */
  func parseClusterSpot(message: String, messageType: TelnetManagerMessage) {

    do {
      var spot = ClusterSpot(id: 0, dxStation: "", frequency: "", spotter: "", dateTime: "", comment: "", grid: "")

      switch messageType {
      case .showDxSpots:
        spot = try self.spotProcessor.processShowDxSpot(rawSpot: message)
      case .spotReceived:
        spot = try self.spotProcessor.processSpot(rawSpot: message)
        lastSpotReceivedTime = Date()
      case .htmlSpotReceived:
        spot = try self.spotProcessor.processHtmlSpot(rawSpot: message)
        lastSpotReceivedTime = Date()
      default:
        return
      }

      if bandFilters[convertFrequencyToBand(frequency: spot.frequency)] == nil {
        return
      }

      DispatchQueue.main.async {
        self.spots.insert(spot, at: 0)
      }

      if self.haveSessionKey {
        DispatchQueue.global(qos: .background).async { [weak self] in
          self!.qrzManager.getConsolidatedQRZInformation(spotterCall: spot.spotter,
                                dxCall: spot.dxStation, frequency: spot.frequency)
        }
      }

      DispatchQueue.main.async {
          if self.spots.count > 100 {
          self.spots.removeLast()
        }
      }
    } catch {
      print("Error: \(error)")
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

  // MARK: - Button Action Implementation ----------------------------------------------------------------------------

  /**
   Manage the band button state.
   - parameters:
   - buttonTag: the tag that identifies the button.
   - state: the state of the button .on or .off.
   */
  func setBandButtons( buttonTag: Int, state: Bool) {

    if buttonTag == 9999 {return}

    switch state {
    case true:
      self.bandFilters[buttonTag] = buttonTag
      if buttonTag == 0 {
        //resetBandButtons()
      } else {
        bandFilters[buttonTag] = buttonTag
      }
    case false:
      self.bandFilters.removeValue(forKey: buttonTag)
    }

    filterMapLines()
  }

  /**
   
   */
  func filterMapLines() {
    for polyLine in self.overlays {
      guard let band = Int(polyLine.title ?? "0") else { return }
      if bandFilters[band] == nil {
        DispatchQueue.main.async {
          self.overlays = self.overlays.filter {$0.title != String(band)}
        }
      }
    }
  }

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
      connect(clusterName: connectedCluster)
  }

  /**
   Calculate the number of minutes between two dates
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

  // MARK: - Map Implementation ----------------------------------------------------------------------------

  func centerMapOnLocation(location: CLLocation) {
    //          let coordinateRegion = MKCoordinateRegion(center: location.coordinate,
    //                                                    latitudinalMeters: REGION_RADIUS, longitudinalMeters: REGION_RADIUS)
    //clustermapView.setRegion(coordinateRegion, animated: true)
  }

  /*
   Build the line (overlay) to display on the map.
   - parameters:
   - qrzInfoCombined: combined data of a pair of call signs QRZ information.
   */
  func buildMapLines(qrzInfoCombined: QRZInfoCombined) {

    if qrzInfoCombined.error {return}

    let locations = [
      CLLocationCoordinate2D(latitude: qrzInfoCombined.spotterLatitude, longitude: qrzInfoCombined.spotterLongitude),
      CLLocationCoordinate2D(latitude: qrzInfoCombined.dxLatitude, longitude: qrzInfoCombined.dxLongitude)]

    let polyline = MKGeodesicPolyline(coordinates: locations, count: locations.count)
    polyline.title = String(qrzInfoCombined.band)

    DispatchQueue.main.async {
      if self.bandFilters[qrzInfoCombined.band] != nil {
        DispatchQueue.main.async {
          self.overlays.append(polyline)
        }
      }
      //self.filterMapLines()
    }

    DispatchQueue.main.async {
        if self.overlays.count > 50 {
        self.overlays.remove(at: self.overlays.count - 1)
      }
    }
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

// MARK: - User Defaults

// https://www.simpleswiftguide.com/how-to-use-userdefaults-in-swiftui/
class UserSettings: ObservableObject {

  @Published var callsign: String {
    didSet {
      UserDefaults.standard.set(callsign.uppercased(), forKey: "callsign")
    }
  }

  @Published var fullname: String {
    didSet {
      UserDefaults.standard.set(fullname, forKey: "fullname")
    }
  }

  @Published var username: String {
    didSet {
      UserDefaults.standard.set(username, forKey: "username")
    }
  }

  @Published var password: String {
    didSet {
      UserDefaults.standard.set(password, forKey: "password")
    }
  }

  @Published var location: String {
    didSet {
      UserDefaults.standard.set(location, forKey: "location")
    }
  }

  @Published var grid: String {
    didSet {
      UserDefaults.standard.set(grid, forKey: "grid")
    }
  }

  init() {
    self.callsign = UserDefaults.standard.string(forKey: "callsign") ?? ""
    self.username = UserDefaults.standard.string(forKey: "username") ?? ""
    self.password = UserDefaults.standard.string(forKey: "password") ?? ""
    self.fullname = UserDefaults.standard.string(forKey: "fullname") ?? ""
    self.location = UserDefaults.standard.string(forKey: "location") ?? ""
    self.grid = UserDefaults.standard.string(forKey: "grid") ?? ""
  }
}
