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

  func qrzManagerDidGetSessionKey(_ qrzManager: QRZManager, messageKey: QRZManagerMessage, haveSessionKey: Bool)

  func qrzManagerDidGetCallSignData(_ qrzManager: QRZManager, messageKey: QRZManagerMessage, stationInfoCombined: StationInformationCombined, spot: ClusterSpot)
}

public enum KeyName: String {
  case errorKeyName = "Error"
  case sessionKeyName = "Session"
  case recordKeyName = "Callsign"
}

class QRZManager: NSObject {

  private let serialQRZProcessorQueue =
    DispatchQueue(
      label: "com.w6op.virtualcluster.qrzProcessorQueue")

  // MARK: - Field Definitions

  //static let modelLog = OSLog(subsystem: "com.w6op.TelnetManager", category: "Model")
  let logger = Logger(subsystem: "com.w6op.xCluster", category: "QRZManager")

  // delegate to pass messages back to view
  weak var qrZedManagerDelegate: QRZManagerDelegate?
  let callParser = PrefixFileParser()
  var callLookup = CallLookup()

  var sessionKey: String!
  var haveSessionKey: Bool = false

  var qrzUserName = ""
  var qrzPassword = ""

  // a few variables to hold the results as we parse the XML
  //let sessionKeyName = "Session"
  //let recordKeyName = "Callsign"
  //let errorKeyName = "Error"

  //var temp = [String]()
  //var temp2 = [String]()

  let callSignDictionaryKeys = Set<String>(["call", "country", "lat", "lon", "grid", "lotw", "aliases", "Error"])
  let sessionDictionaryKeys = Set<String>(["Key", "Count", "SubExp", "GMTime", "Remark"])
  var results: [[String: String]]?         // the whole array of dictionaries
  var results2: StationInformation!
  var sessionDictionary: [String: String]! // the current session dictionary
  var callSignDictionary: [String: String]! // the current call sign dictionary
  var currentValue = ""
  var locationDictionary: (spotter: [String: String], dx: [String: String])!

  var callSignCache = [String: StationInformation]()
  var callSignPair = [StationInformation]()
  //var stationInfo: StationInformation!

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

    // TODO: account for no QRZ account or incorrect id/password
    qrzUserName = name
    qrzPassword = password

    sessionDictionary = [String: String]()

    // this dies if session key is missing
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

        //do {
          let parser = XMLParser(data: data)
          parser.delegate = self

          //let stringValue = String(decoding: data, as: UTF8.self)
          //print("DATA: \(stringValue)")

          if parser.parse() {
            if self.results != nil {
              self.sessionKey = self.sessionDictionary?["Key"]
              //?.trimmingCharacters(in: .whitespacesAndNewlines)
              self.haveSessionKey = true
              self.qrZedManagerDelegate?.qrzManagerDidGetSessionKey(self, messageKey: .session, haveSessionKey: true)
            }
          }
    }
    task.resume()
  }

  /// Request all the call information from QRZ.com to make a line on the map.
  /// All we really need is to get the latitude and longitude.
  /// - Parameter spot: cluster spot
  func getConsolidatedQRZInformation(spot: ClusterSpot) {
    var cacheHits = 0

    /// TODO: Make called function throw
    serialQRZProcessorQueue.sync(flags: .barrier) { //[weak self] in
      // check the call sign cache
      if callSignCache[spot.spotter] != nil {
        let spotterInfo = callSignCache[spot.spotter]
        callSignPair.append(spotterInfo!)
        cacheHits += 1
        cacheRequestCount += 1
      } else {
        requestStationInformation(call: spot.spotter, spot: spot, isSpotter: true)
        return
//        let spotterInfo = requestStationInformation(call: spot.spotter, isSpotter: true)
//
//        // add to call sign cache
//        if callSignCache[spotterInfo.call] == nil {
//          callSignCache[spotterInfo.call] = spotterInfo
//        }
//        callSignPair.append(spotterInfo)
      }

      if callSignCache[spot.dxStation] != nil {
        let dxInfo = callSignCache[spot.dxStation]
        callSignPair.append(dxInfo!)
        cacheHits += 1
        cacheRequestCount += 1
      } else {
        requestStationInformation(call: spot.dxStation, spot: spot, isSpotter: false)
        return
//        let dxInfo = requestStationInformation(call: spot.dxStation, isSpotter: false)
//
//        // add to call sign cache
//        if callSignCache[dxInfo.call] == nil {
//          callSignCache[dxInfo.call] = dxInfo
//        }
//        callSignPair.append(dxInfo)
      }

      // only hit if both calls were in the cache
      //if cacheHits == 2 {
        combineQRZInfo(spot: spot)
      //}
    }
  }

  /// Request all the call information from QRZ.com.
  /// - Parameters:
  ///   - callSign: call sign to look up.
  ///   - frequency: frequency to pass on.
//  func requestQRZInformation(spot: ClusterSpot, isSpotter: Bool) {
//
//    var call: String
//
//    callSignDictionary = [String: String]()
//    callSignDictionary["Error"] = nil
//
//    if haveSessionKey == false {
//      requestSessionKey(name: qrzUserName, password: qrzPassword)
//      return
//    }
//
//    if isSpotter {
//      call = spot.spotter
//    } else {
//      call = spot.dxStation
//    }
//
//    // if there is a prefix or suffix the QRZ info will
//    // only be for the base call - use the call parser to get
//    // the correct area information if the call parser can't
//    // find it then use the base call information
//    if call.contains("/") {
//        stationInfo = StationInformation()
//        logger.info("Use callparser (2) \(call)")
//        let hitList: [Hit] = callLookup.lookupCall(call: call)
//        if !hitList.isEmpty {
//          logger.info("Use callparser(2) success \(call)")
//          stationInfo = populateStationInformation(hitList: hitList)
//
//          // add to call sign cache
//          if callSignCache[stationInfo.call] == nil {
//            callSignCache[stationInfo.call] = stationInfo
//          }
//
//          callSignPair.append(stationInfo)
//          // combineQRZInfo(spot: spot)
//          return
//        }
//      }
//
//    //------------------------------------
//    // this dies if session key is missing
//    guard let url = URL(string: "https://xmldata.qrz.com/xml/current/?s=\(String(self.sessionKey));callsign=\(call)") else {
//      logger.info("Session key is invalid: \(self.sessionKey)")
//      return
//    }
//
//    qrzRequestCount += 1
//
//    logger.info("QRZ requests vs cache hits: \(self.qrzRequestCount) : \(self.cacheRequestCount)")
//
//    let task = URLSession.shared.dataTask(with: url) { [self] data, response, error in
//      if let error = error {
//        fatalError("Error 1: \(error.localizedDescription)")
//      }
//      guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
//        fatalError("Error: invalid HTTP response code")
//      }
//      guard let data = data else {
//        fatalError("Error: missing response data")
//      }
//
//      // to look at xml input for debugging
//      //let str = String(decoding: data, as: UTF8.self)
//      //print(str)
//
//      let parser = XMLParser(data: data)
//      parser.delegate = self
//
//      if parser.parse() {
//        if self.results != nil {
//          if callSignPair.count > 1 {
//            callSignPair.removeAll()
//          }
//          getQRZInfo(spot: spot)
//        } else {
//          // we did not get one or more hits
//          // will move this to CallParser and call it there
//          logger.info("Use CallParser: (0) \(call)") // above I think
//        }
//      }
//    }
//    task.resume()
//  }

  func requestStationInformation(call: String, spot: ClusterSpot, isSpotter: Bool)  {

    callSignDictionary = [String: String]()
    callSignDictionary["Error"] = nil

    if haveSessionKey == false {
      requestSessionKey(name: qrzUserName, password: qrzPassword)
      return
    }

    // if there is a prefix or suffix the QRZ info will
    // only be for the base call - use the call parser to get
    // the correct area information if the call parser can't
    // find it then use the base call information
    if call.contains("/") {
        logger.info("Use callparser (2) \(call)")
        let hitList: [Hit] = callLookup.lookupCall(call: call)
        if !hitList.isEmpty {
          logger.info("Use callparser(2) success \(call)")
/// TODO: fix this
          //stationInfo = populateStationInformation(hitList: hitList)

          return
        }
      }

    requestQRZInformation(call: call, spot: spot, isSpotter: isSpotter)

    return
  }

  func requestQRZInformation(call: String, spot: ClusterSpot, isSpotter: Bool) {
    //------------------------------------
    // this dies if session key is missing
    guard let url = URL(string: "https://xmldata.qrz.com/xml/current/?s=\(String(self.sessionKey));callsign=\(call)") else {
      logger.info("Session key is invalid: \(self.sessionKey)")
      return
    }

    qrzRequestCount += 1

    //logger.info("QRZ requests vs cache hits: \(self.qrzRequestCount) : \(self.cacheRequestCount)")

    let task = URLSession.shared.dataTask(with: url) { [self] data, response, error in
      if let error = error {
        fatalError("Error 1: \(error.localizedDescription)")
      }
      guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
        fatalError("Error: invalid HTTP response code")
      }
      guard let data = data else {
        fatalError("Error: missing response data")
      }

      // to look at xml input for debugging
      //let str = String(decoding: data, as: UTF8.self)
      //print(str)

      print("requestQRZInformation: 1")

      let parser = XMLParser(data: data)
      parser.delegate = self

      if parser.parse() {
        if self.results != nil {
          if callSignPair.count > 1 {
            callSignPair.removeAll()
          }

          print("requestQRZInformation: 2")

          if isSpotter {
          let spotterInfo = getQRZInfo(call: call)
          // add to call sign cache
          if callSignCache[spotterInfo.call] == nil {
            callSignCache[spotterInfo.call] = spotterInfo
          }
          callSignPair.append(spotterInfo)
          } else {
            let dxInfo = getQRZInfo(call: call)

            // add to call sign cache
            if callSignCache[dxInfo.call] == nil {
              callSignCache[dxInfo.call] = dxInfo
            }
            callSignPair.append(dxInfo)
          }

          combineQRZInfo(spot: spot)

        } else {

          logger.info("Use CallParser: (0) \(call)") // above I think
        }
      }
    }
    task.resume()

    print("requestQRZInformation: 3")
  }

  func getQRZInfo(call: String) -> StationInformation {
    var stationInfo = StationInformation()
    var isProcessed = false

    // need to check if dictionary is empty
    if callSignDictionary.isEmpty {
      logger.info("callSignDictionary is empty")
      return stationInfo
    }

    stationInfo.call = callSignDictionary["call"] ?? ""

    if callSignDictionary[KeyName.errorKeyName.rawValue] != nil {
      print("CallSignDictionary not found: \(String(describing: callSignDictionary["Error"]))")

      // QRZ.com could not find it
      let error = callSignDictionary["Error"]
      if let range = error!.range(of: "found: ") {
        let callSign = error![range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        //logger.info("Use callparser (1) \(callSign)")
        let hitList: [Hit] = callLookup.lookupCall(call: callSign)
        if !hitList.isEmpty {
          logger.info("Use callparser(1) success \(callSign)")
          stationInfo = populateStationInformation(hitList: hitList)
          isProcessed = true
        } else {
          logger.info("THIS IS AN ERROR \(callSign)")
          return  stationInfo // SHOULD THROW
        }
      }
    }

      if !isProcessed {
        stationInfo = populateQRZInfo(stationInfoIncomplete: stationInfo)
      }

    return stationInfo
  }

  /// Populate the qrzInfo with latitude, longitude, etc. If there is a pair
  /// send them to the view controller for a line to be drawn.
  /// - Parameter frequency: frequency represented as a string
  func getQRZInfo(spot: ClusterSpot) {

    var stationInfo = StationInformation()
    var isProcessed = false

    // need to check if dictionary is empty
    if callSignDictionary.isEmpty {
      logger.info("callSignDictionary is empty")
      return
    }

    stationInfo.call = callSignDictionary["call"] ?? ""
    //print("QRZInfo: \(String(describing: callSignDictionary))")

    if callSignDictionary[KeyName.errorKeyName.rawValue] != nil {
      print("CallSignDictionary not found: \(String(describing: callSignDictionary["Error"]))")

      // QRZ.com could not find it
      let error = callSignDictionary["Error"]
      if let range = error!.range(of: "found: ") {
        let callSign = error![range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        //logger.info("Use callparser (1) \(callSign)")
        let hitList: [Hit] = callLookup.lookupCall(call: callSign)
        if !hitList.isEmpty {
          logger.info("Use callparser(1) success \(callSign)")
          stationInfo = populateStationInformation(hitList: hitList)
          isProcessed = true
        } else {
          logger.info("THIS IS AN ERROR \(callSign)")
          return // SHOULD THROW
        }
      }
    }

      if !isProcessed {
        stationInfo = populateQRZInfo(stationInfoIncomplete: stationInfo)
      }

    // add to call sign cache
    if callSignCache[stationInfo.call] == nil {
      callSignCache[stationInfo.call] = stationInfo
    }

    callSignPair.append(stationInfo)

    combineQRZInfo(spot: spot)
  }

  func populateQRZInfo(stationInfoIncomplete: StationInformation) -> StationInformation {
    var stationInfo = stationInfoIncomplete

    stationInfo.latitude = Double(callSignDictionary["lat"] ?? "0.0") ?? 00
    if stationInfo.latitude == 00 {
      stationInfo.error = true
      logger.info("Latitude error: \(stationInfo.call)")
    }

    stationInfo.longitude = Double(callSignDictionary["lon"] ?? "0.0") ?? 00
    if stationInfo.longitude == 00 {
      stationInfo.error = true
      logger.info("Longitude error: \(stationInfo.call)")
    }

    // if there is a prefix or suffix I need to find correct country and lat/lon
    stationInfo.country = callSignDictionary["country"] ?? ""
    stationInfo.grid = callSignDictionary["grid"] ?? ""
    stationInfo.lotw = Bool(callSignDictionary["lotw"] ?? "0") ?? false
    stationInfo.aliases = callSignDictionary["aliases"] ?? ""

    stationInfo.isInitialized = true

    return stationInfo
  }

  /**
   Create a QRZInfo object from the hitlist.
   - parameters:
   - hitList: the array of hits returned
   */
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

    return stationInfo
  }

  /**
   Combine the QRZ information and send it to the view controller for a line to be drawn.
   - parameters:
   - qrzCallSignPairCopy: the pair of QRZInfo to be combined
   - frequency: frequency to add to structure
   */
  func combineQRZInfo(spot: ClusterSpot) {

    if callSignPair.count == 2 {
      let qrzCallSignPairCopy = callSignPair // use copy so we don't read while modifying
      var qrzInfoCombined = StationInformationCombined()

      qrzInfoCombined.setFrequency(frequency: spot.frequency)

      qrzInfoCombined.spotterCall = qrzCallSignPairCopy[0].call
      qrzInfoCombined.spotterCountry = qrzCallSignPairCopy[0].country
      qrzInfoCombined.spotterLatitude = qrzCallSignPairCopy[0].latitude
      qrzInfoCombined.spotterLongitude = qrzCallSignPairCopy[0].longitude
      qrzInfoCombined.spotterGrid = qrzCallSignPairCopy[0].grid
      qrzInfoCombined.spotterLotw = qrzCallSignPairCopy[0].lotw
      //qrzInfoCombined.spotId = qrzCallSignPairCopy[0].spotId
      qrzInfoCombined.error = qrzCallSignPairCopy[0].error

      qrzInfoCombined.dxCall = qrzCallSignPairCopy[1].call
      qrzInfoCombined.dxCountry = qrzCallSignPairCopy[1].country
      qrzInfoCombined.dxLatitude = qrzCallSignPairCopy[1].latitude
      qrzInfoCombined.dxLongitude = qrzCallSignPairCopy[1].longitude
      qrzInfoCombined.dxGrid = qrzCallSignPairCopy[1].grid
      qrzInfoCombined.dxLotw = qrzCallSignPairCopy[1].lotw
      if !qrzInfoCombined.error {
        qrzInfoCombined.error = qrzCallSignPairCopy[1].error
      }

      self.qrZedManagerDelegate?.qrzManagerDidGetCallSignData(
        self,messageKey: .qrzInformation,
        stationInfoCombined: qrzInfoCombined,
        spot: spot)
    }
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
