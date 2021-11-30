//
//  QRZManager.swift
//  xCluster
//
//  Created by Peter Bourget on 7/8/20.
//  Copyright © 2020 Peter Bourget. All rights reserved.
//

import Cocoa
import Network
import CoreLocation
import os
import CallParser

protocol QRZManagerDelegate: AnyObject {
  func qrzManagerDidGetSessionKey(_ qrzManager: QRZManager, messageKey: QRZManagerMessage, doHaveSessionKey: Bool)
  func qrzManagerDidGetCallSignData(_ qrzManager: QRZManager, messageKey: QRZManagerMessage, stationInfoCombined: StationInformationCombined, spot: ClusterSpot)
}

public enum KeyName: String {
  case errorKeyName = "Error"
  case sessionKeyName = "Session"
  case recordKeyName = "Callsign"
}

class QRZManager: NSObject {

  private let lockQueue =
    DispatchQueue(
      label: "com.w6op.virtualcluster.lockQueue")// , attributes: .concurrent

  // MARK: - Field Definitions

  var callSignPairs = [UUID: [StationInformation]]()
  let logger = Logger(subsystem: "com.w6op.xCluster", category: "QRZManager")

  // delegate to pass messages back to view
  weak var qrZedManagerDelegate: QRZManagerDelegate?

  let callParser = PrefixFileParser()
  var callLookup = CallLookup()

  var sessionKey: String!
  var isSessionKeyValid: Bool = false

  var qrzUserName = ""
  var qrzPassword = ""
  var useCallLookupOnly = false

  var results: [[String: String]]?
  var sessionLookup: [String: String] = ["Key": "", "Count": "", "SubExp": "", "GMTime": "", "Remark": ""] // the current session dictionary
  var callSignLookup: [String: String] = ["call": "", "country": "", "lat": "", "lon": "", "grid": "", "lotw": "0", "aliases": "", "Error": ""]

  var currentValue = ""
  var callSignCache = [String: StationInformation]()

  // temp to test with
  var qrzRequestCount = 0
  var cacheRequestCount = 0

  // MARK: - Overrides

  override init() {

    super.init()

    callLookup = CallLookup(prefixFileParser: callParser)
  }

  // MARK: - Network Implementation

  /// Get a Session Key from QRZ.com.
  /// - Parameters:
  ///   - name: logon name with xml plan.
  ///   - password: password for account.
  func requestSessionKey(name: String, password: String) {

    logger.info("Request Session Key.")

    qrzUserName = name
    qrzPassword = password

    sessionLookup = ["Key": "", "Count": "", "SubExp": "", "GMTime": "", "Remark": ""] //[String: String]()

    guard let url = URL(string: "https://xmldata.qrz.com/xml/current/?username=\(name);password=\(password);xCluster=1.0") else {
      logger.info("Invalid user name or password: \(name)")
      return
    }

    let task = URLSession.shared.dataTask(with: url) { [self] data, response, error in
        if let error = error {
            fatalError("Error: \(error.localizedDescription)")
        }
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
            fatalError("Error: invalid HTTP response code")
        }
        guard let data = data else {
            fatalError("Error: missing response data")
        }

          let parser = XMLParser(data: data)
          parser.delegate = self

          if parser.parse() {
            if self.results != nil {
              sessionKey = self.sessionLookup["Key"]
              isSessionKeyValid = true
              qrZedManagerDelegate?.qrzManagerDidGetSessionKey(self,
                                                               messageKey: .session,
                                                               doHaveSessionKey: true)
            }
          }
    }
    task.resume()
  }

  /// Initial starting point to queue work
  /// - Parameter spot: ClusterSpot
  func buildStationInformation(spot: ClusterSpot) {
      requestConsolidatedStationInformationQRZ(spot: spot)
  }

  /// If the user does not have a subscription to QRZ.com then
  /// only use the Call Parser for lookups.
  /// - Parameter spot: ClusterSpot
  func requestConsolidatedStationInformationCallParser(spot: ClusterSpot) {
    var cacheHits = 0
    var callSignPair = [StationInformation]()

    if let spotterInfo = checkCache(call: spot.spotter) {
      callSignPair.append(spotterInfo)
      cacheHits += 1
      cacheRequestCount += 1
    } else {
      lockQueue.async { [self] in
        let spotterInfo = requestCallParserInformation(call: spot.spotter)
        callSignPair.append(spotterInfo)
      }
    }

    if let dxInfo = checkCache(call: spot.dxStation) {
      callSignPair.append(dxInfo)
      cacheHits += 1
      cacheRequestCount += 1
    } else {
      lockQueue.async { [self] in
        let dxInfo = requestCallParserInformation(call: spot.dxStation)
        callSignPair.append(dxInfo)
      }
    }

      if callSignPair.count == 2 {
        logger.info("Call Parser success for spot")
        combineQRZInfo(spot: spot, callSignPair: callSignPair)
      }
  }

  /// Check to see if we already have all the information needed.
  /// - Parameter call: call sign to lookup.
  /// - Returns: StationInformation
  func checkCache(call: String) -> StationInformation? {

    if callSignCache[call] != nil { return callSignCache[call] }

    return nil
  }

  /// Request all the call information from QRZ.com to make a line on the map.
  /// All we really need is to get the latitude and longitude.
  /// - Parameter spot: ClusterSpot
  func requestConsolidatedStationInformationQRZ(spot: ClusterSpot) {
    var cacheHits = 0

    if let spotterInfo = checkCache(call: spot.spotter) {
      lockQueue.async { [self] in
        decide(stationInfo: spotterInfo, spot: spot)
      }
      logger.info("Cache hit for: \(spot.spotter)")
      cacheHits += 1
      cacheRequestCount += 1
    } else {
      if !requestStationInformation(call: spot.spotter, spot: spot) {
        Task {
          try? await requestQRZInformationAsync(call: spot.spotter, spot: spot)
        }
      }
    }

    if let dxInfo = checkCache(call: spot.dxStation) {
      lockQueue.async { [self] in
        decide(stationInfo: dxInfo, spot: spot)
      }
      logger.info("Cache hit for: \(spot.dxStation)")
      cacheHits += 1
      cacheRequestCount += 1
    } else {
      if !requestStationInformation(call: spot.spotter, spot: spot) {
        Task {
          try? await requestQRZInformationAsync(call: spot.dxStation, spot: spot)
        }
        //requestQRZInformation(call: spot.dxStation, spot: spot)
      }
    }

    logger.info("QRZ requests vs cache hits: \(self.qrzRequestCount) : \(self.cacheRequestCount)")
  }

  /// Request all the call information from QRZ.com
  /// If there is a prefix or suffix the QRZ info will
  /// only be for the base call - use the call parser to get
  /// the correct area information if the call parser can't
  /// find it then use the base call information
  /// - Parameters:
  ///   - call: call sign
  ///   - spot: cluster spot
  ///   - isSpotter: is it the spotter or the dx call sign
  func requestStationInformation(call: String, spot: ClusterSpot) -> Bool {

    if call.contains("/") {
      logger.info("Use callparser (2) \(call)")
      var stationInfo = requestCallParserInformation(call: call)
      stationInfo.id = spot.id
        lockQueue.async { [self] in
          decide(stationInfo: stationInfo, spot: spot)
        }
      return true
    }
    return false
  }

  /// Request the information about a call sign from the Call Parser.
  /// - Parameter call: call sign to lookup
  /// - Returns: StationInformation
  func requestCallParserInformation(call: String) -> StationInformation {

    var stationInfo = StationInformation()

      let hitList: [Hit] = callLookup.lookupCall(call: call)
      if !hitList.isEmpty {
        logger.info("Use callparser(5) success \(call)")
        stationInfo = populateStationInformation(hitList: hitList)
          if callSignCache[stationInfo.call] == nil {
            callSignCache[stationInfo.call] = stationInfo
        }
      //}
    }
    //          // THIS IS AN ERROR 9W64BW/E46V
    //          // THIS IS AN ERROR D1DX
    //          logger.info("THIS IS AN ERROR \(callSign)")
    //          throw (RequestError.invalidCallSign)

    return stationInfo
  }


  func requestQRZInformation(call: String, spot: ClusterSpot) {

    if isSessionKeyValid == false {
      requestSessionKey(name: qrzUserName, password: qrzPassword)
      // throw?
    }

    // this dies if session key is missing
    guard let url = URL(string: "https://xmldata.qrz.com/xml/current/?s=\(String(self.sessionKey));callsign=\(call)") else {
      logger.info("Session key is invalid: \(self.sessionKey)")
      return
    }

    qrzRequestCount += 1

    let task = URLSession.shared.dataTask(with: url) { [self] data, response, error in
      if let error = error {
        logger.error("Error 1: \(error.localizedDescription)")
      }

      guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
        guard error != nil else {
          return
        }
        logger.error("Error 2: \(error!.localizedDescription)")
        return
      }

      guard let data = data else {
        logger.error("Error 3: \(error!.localizedDescription)")
        return
      }

      parseReceivedData(data: data, call: call, spot: spot)

      }
    task.resume()
  }

  func requestQRZInformationAsync(call: String, spot: ClusterSpot) async throws {

    if isSessionKeyValid == false {
      requestSessionKey(name: qrzUserName, password: qrzPassword)
      // throw?
    }

    // this dies if session key is missing
    guard let url = URL(string: "https://xmldata.qrz.com/xml/current/?s=\(String(self.sessionKey));callsign=\(call)") else {
      logger.info("Session key is invalid: \(self.sessionKey)")
      return
    }

    qrzRequestCount += 1

    let (data, response) = try await
        URLSession.shared.data(from: url)

    guard (response as? HTTPURLResponse)?.statusCode == 200 else {
      print("The server responded with an error")
      return
    }

    parseReceivedData(data: data, call: call, spot: spot)
  }


  fileprivate func parseReceivedData(data: Data, call: String, spot: ClusterSpot) {
    //stationProcessorQueue.async { [self] in
    // if you need to look at xml input for debugging
    //let str = String(decoding: data, as: UTF8.self)
    //print(str)
    let parser = XMLParser(data: data)
    parser.delegate = self

    if parser.parse() {
      if self.results != nil {

        do {

          var stationInfo = try processQRZInformation(call: call)
          stationInfo.id = spot.id

          callSignCache[stationInfo.call] = stationInfo

          lockQueue.async { [self] in
            decide(stationInfo: stationInfo, spot: spot)
          }

        } catch {
          logger.info("RequestError Error: \(error as NSObject)")
        }
      } else {
        logger.info("Use CallParser: (0) \(call)") // above I think
      }
    }
  }


  /// Determine if we have enough information to create an overlay.
  /// Check the cache first.
  /// - Parameters:
  ///   - stationInfo: StationInformation
  ///   - spot: ClusterSpot
  func decide(stationInfo: StationInformation, spot: ClusterSpot) {

    if callSignPairs[spot.id] != nil {
      var callSignPair = callSignPairs[spot.id]
      callSignPair?.append(stationInfo)
      if callSignPair!.count == 2 {
        combineQRZInfo(spot: spot, callSignPair: callSignPair!)
        callSignPairs[spot.id] = nil
      }
    } else {
      var callSignPair = [StationInformation]()
      callSignPair.append(stationInfo)
      callSignPairs[spot.id] = callSignPair
    }
  }

  /// Process the information returned by the QRZ.com request.
  /// - Parameter call: call sign.
  /// - Returns: a station information struct.
  func processQRZInformation(call: String) throws -> StationInformation {
    var stationInfo = StationInformation()
    var isProcessed = false

    // need to check if dictionary is empty
    if callSignLookup.isEmpty {
      logger.info("callSignDictionary is empty")
      // need to throw here
      return stationInfo
    }

    stationInfo.call = callSignLookup["call"] ?? ""

    if callSignLookup[KeyName.errorKeyName.rawValue] != "" {
      print("CallSignDictionary error found: \(String(describing: callSignLookup["Error"]))")

      // QRZ.com could not find it
      let error = callSignLookup["Error"]
      if let range = error!.range(of: "found: ") {
        let callSign = error![range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        stationInfo = requestCallParserInformation(call: callSign)
        isProcessed = true
      }
    }

      if !isProcessed {
        do {
          stationInfo = try populateQRZInformation(stationInfo: stationInfo)
        } catch {
          // throw
        }
      }

    return stationInfo
  }

  /// Populate the qrzInfo with latitude, longitude, etc.
  /// - Parameter stationInfoIncomplete: partial station information.
  /// - Returns: station information.
  func populateQRZInformation(stationInfo: StationInformation) throws -> StationInformation {
    var stationInfo = stationInfo

    guard (callSignLookup["lat"]!.double != nil) else {
      throw RequestError.invalidLatitude
    }

    stationInfo.latitude = Double(callSignLookup["lat"]!)!

    guard (callSignLookup["lon"]!.double != nil) else {
      throw RequestError.invalidLongitude
    }

    stationInfo.longitude = Double(callSignLookup["lon"]!)!

    // if there is a prefix or suffix I need to find correct country and lat/lon
    stationInfo.country = callSignLookup["country"] ?? ""
    stationInfo.grid = callSignLookup["grid"] ?? ""
    stationInfo.lotw = Bool(callSignLookup["lotw"] ?? "0") ?? false
    stationInfo.aliases = callSignLookup["aliases"] ?? ""

    stationInfo.isInitialized = true

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

      self.qrZedManagerDelegate?.qrzManagerDidGetCallSignData(
        self, messageKey: .qrzInformation,
        stationInfoCombined: qrzInfoCombined,
        spot: spot)
  }

} // end class

/*

 <QRZDatabase version="1.34" xmlns="http://xmldata.qrz.com">
 <Session>
 <Error>Not found: R0AT</Error>
 <Key>6c68f99260205b52dfc90dba54f8d059</Key>
 <Count>9581729</Count>
 <SubExp>Wed Dec 29 00:00:00 2021</SubExp>
 <GMTime>Tue Apr  6 17:22:01 2021</GMTime>
 <Remark>cpu: 0.034s</Remark>
 </Session>
 </QRZDatabase>

 <QRZDatabase version="1.33" xmlns="http://xmldata.qrz.com">
 <Session>
 <Key>d078471d55aef6e17fb566ef6e381e03</Key>
 <Count>9465097</Count>
 <SubExp>Sun Dec 29 00:00:00 2019</SubExp>
 <GMTime>Thu Feb 28 18:11:31 2019</GMTime>
 <Remark>cpu: 0.162s</Remark>
 </Session>
 </QRZDatabase>

 <QRZDatabase version="1.33" xmlns="http://xmldata.qrz.com">
 <Callsign>
 <call>F2JD</call>
 <xref>HR5/F2JD</xref>
 <aliases>HR5/F2JD</aliases>
 <dxcc>227</dxcc>
 <fname>Gerard</fname>
 <name>JACOT</name>
 <addr1>Boucle de l'Observatoite - Le Mont Revard</addr1>
 <addr2>73100 PUGNY- CHATENOD</addr2>
 <zip>73100</zip>
 <country>France</country>
 <lat>45.686667</lat>
 <lon>5.956667</lon>
 <grid>JN25xq</grid>
 <ccode>97</ccode>
 <land>France</land>
 <class>A</class>
 <codes>TP</codes>
 <qslmgr>ALL VIA F6AJA (NOW FROM 36 YEARS)</qslmgr>
 <email>f2jd@orange.fr</email>
 <u_views>120353</u_views>
 <bio>4146</bio>
 <biodate>2015-07-16 00:28:33</biodate>
 <image>https://s3.amazonaws.com/files.qrz.com/d/f2jd/f2jd_1039532297.jpg</image>
 <imageinfo>274:400:27678</imageinfo>
 <moddate>2018-08-24 06:38:45</moddate>
 <eqsl>0</eqsl>
 <mqsl>1</mqsl>
 <cqzone>14</cqzone>
 <ituzone>27</ituzone>
 <born>1947</born>
 <lotw>1</lotw>
 <user>F2JD</user>
 <geoloc>user</geoloc>
 </Callsign>
 <Session>
 <Key>8c0e9b8e4072e5782727928413417bc2</Key>
 <Count>9471417</Count>
 <SubExp>Sun Dec 29 00:00:00 2019</SubExp>
 <GMTime>Fri Mar  8 23:26:34 2019</GMTime>
 <Remark>cpu: 0.131s</Remark>
 </Session>
 </QRZDatabase>
 
 <QRZDatabase version="1.33" xmlns="http://xmldata.qrz.com">
 <Callsign>
 <call>F2JD</call>
 <aliases>HR5/F2JD</aliases>
 <dxcc>227</dxcc>
 <fname>Gerard</fname>
 <name>JACOT</name>
 <addr1>Boucle de l'Observatoite - Le Mont Revard</addr1>
 <addr2>73100 PUGNY- CHATENOD</addr2>
 <zip>73100</zip>
 <country>France</country>
 <lat>45.686667</lat>
 <lon>5.956667</lon>
 <grid>JN25xq</grid>
 <ccode>97</ccode>
 <land>France</land>
 <class>A</class>
 <codes>TP</codes>
 <qslmgr>ALL VIA F6AJA (NOW FROM 36 YEARS)</qslmgr>
 <email>f2jd@orange.fr</email>
 <u_views>120354</u_views>
 <bio>4146</bio>
 <biodate>2015-07-16 00:28:33</biodate>
 <image>https://s3.amazonaws.com/files.qrz.com/d/f2jd/f2jd_1039532297.jpg</image>
 <imageinfo>274:400:27678</imageinfo>
 <moddate>2018-08-24 06:38:45</moddate>
 <eqsl>0</eqsl>
 <mqsl>1</mqsl>
 <cqzone>14</cqzone>
 <ituzone>27</ituzone>
 <born>1947</born>
 <lotw>1</lotw>
 <user>F2JD</user>
 <geoloc>user</geoloc>
 </Callsign>
 <Session>
 <Key>8c0e9b8e4072e5782727928413417bc2</Key>
 <Count>9471418</Count>
 <SubExp>Sun Dec 29 00:00:00 2019</SubExp>
 <GMTime>Fri Mar  8 23:28:18 2019</GMTime>
 <Remark>cpu: 0.348s</Remark>
 </Session>
 </QRZDatabase>
 
 
 <QRZDatabase version="1.33" xmlns="http://xmldata.qrz.com">
 <Callsign>
 <call>WY8I</call>
 <dxcc>291</dxcc>
 <fname>WILLIAM J</fname>
 <name>ODAM, JR</name>
 <addr1>7840 INGLEWOOD BEACH, PO BOX 230337</addr1>
 <addr2>FAIR HAVEN</addr2>
 <state>MI</state>
 <zip>48023</zip>
 <country>United States</country>
 <lat>42.663863</lat>
 <lon>-82.622504</lon>
 <grid>EN82qp</grid>
 <county>Saint Clair</county>
 <ccode>271</ccode>
 <fips>26147</fips>
 <land>United States</land>
 <efdate>2016-07-19</efdate>
 <expdate>2026-10-13</expdate>
 <class>E</class>
 <codes>HVIE</codes>
 <qslmgr>BURO OR DIRECT</qslmgr>
 <email>wy8i@comcast.net</email>
 <u_views>24299</u_views>
 <bio>1076</bio>
 <biodate>2015-07-16 00:30:18</biodate>
 <image>https://s3.amazonaws.com/files.qrz.com/i/wy8i/Jim.jpg</image>
 <imageinfo>694:565:58980</imageinfo>
 <moddate>2019-01-15 13:13:27</moddate>
 <MSA>2160</MSA>
 <AreaCode>810</AreaCode>
 <TimeZone>Eastern</TimeZone>
 <GMTOffset>-5</GMTOffset>
 <DST>Y</DST>
 <eqsl>0</eqsl>
 <mqsl>1</mqsl>
 <cqzone>4</cqzone>
 <ituzone>8</ituzone>
 <lotw>0</lotw>
 <user>WY8I</user>
 <geoloc>user</geoloc>
 </Callsign>
 <Session>
 <Key>d078471d55aef6e17fb566ef6e381e03</Key>
 <Count>9465097</Count>
 <SubExp>Sun Dec 29 00:00:00 2019</SubExp>
 <GMTime>Thu Feb 28 19:12:42 2019</GMTime>
 <Remark>cpu: 0.027s</Remark>
 </Session>
 </QRZDatabase>
 */
