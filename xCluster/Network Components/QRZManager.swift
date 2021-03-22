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

protocol QRZManagerDelegate: class {

  func qrzManagerDidGetSessionKey(_ qrzManager: QRZManager, messageKey: QRZManagerMessage, haveSessionKey: Bool)

  func qrzManagerDidGetCallSignData(_ qrzManager: QRZManager, messageKey: QRZManagerMessage, qrzInfoCombined: QRZInfoCombined)
}

class QRZManager: NSObject {

  private let serialQRZProcessorQueue =
    DispatchQueue(
      label: "com.w6op.virtualcluster.qrzProcessorQueue")

  // MARK: - Field Definitions

  //static let modelLog = OSLog(subsystem: "com.w6op.TelnetManager", category: "Model")
  let logger = Logger(subsystem: "com.w6op.xCluster", category: "QRZManager")

  // delegate to pass messages back to viewcontroller
  weak var qrZedManagerDelegate: QRZManagerDelegate?
  let callParser = PrefixFileParser()
  var callLookup = CallLookup()

  var sessionKey: String!
  var haveSessionKey: Bool = false

  // a few variables to hold the results as we parse the XML
  var recordKey = "Session"
  var dictionaryKeys = Set<String>(["Key", "Count", "SubExp", "GMTime", "Remark"])
  var results: [[String: String]]?         // the whole array of dictionaries
  var results2: QRZInfo!
  var sessionDictionary: [String: String]! // the current dictionary
  var currentValue: String?
  var locationDictionary: (spotter: [String: String], dx: [String: String])!

  var qrZedCallSignCache = [String: QRZInfo]()
  var qrZedCallSignPair = [QRZInfo]()
  var qrZedInfo: QRZInfo!

  // MARK: - Overrides

  override init() {

    super.init()

    callLookup = CallLookup(prefixFileParser: callParser)
  }

  // MARK: - Network Implementation

  /**
   Get a Session Key from QRZ.com.
   - parameters:
   - name: logon name with xml plan.
   - password: password for account. LetsFindSomeDXToday$56
   */
  func parseQRZSessionKeyRequest(name: String, password: String) {

    recordKey = "Session"
    dictionaryKeys = Set<String>(["Key", "Count", "SubExp", "GMTime", "Remark"])

    let urlString = URL(string: "https://xmldata.qrz.com/xml/current/?username=\(name);password=\(password);VirtualCluster=1.0")

    let parser = XMLParser(contentsOf: urlString!)!

    parser.delegate = self
    if parser.parse() {
      print(self.results ?? "No results")
      self.sessionKey = self.sessionDictionary?["Key"]?.trimmingCharacters(in: .whitespaces)
      self.haveSessionKey = true
      self.qrZedManagerDelegate?.qrzManagerDidGetSessionKey(self, messageKey: .session, haveSessionKey: true)
    }
  }

  /**
   Request all the call information from QRZ.com to make a line on the map.
   - parameters:
   - spotterCall: first of a pair call signs to look up.
   - dxCall: second of a pair call signs to look up.
   */
  func getConsolidatedQRZInformation(spotterCall: String, dxCall: String, frequency: String) {

    serialQRZProcessorQueue.sync(flags: .barrier) { [weak self] in
      self?.parseQRZData(callSign: spotterCall, frequency: frequency)
      self?.parseQRZData(callSign: dxCall, frequency: frequency)
    }
  }

  /**
   Request all the call information from QRZ.com.
   - parameters:
   - call: call sign to look up.
   */
  func parseQRZData(callSign: String, frequency: String) {

    recordKey = "Callsign"
    sessionDictionary = [String: String]()
    dictionaryKeys = Set<String>(["call", "country", "lat", "lon", "grid", "lotw", "aliases"])

    // this dies if session key is missing
    guard let urlString = URL(string: "https://xmldata.qrz.com/xml/current/?s=\(String(self.sessionKey));callsign=\(callSign)") else {
      //print("Invalid call sign: \(callSign)") // 'PY2OT  05'
      logger.info("Invalid call sign: \(callSign)")
      return
    }

    // first check to see if I have the info cached already
    if let qrzInfo = qrZedCallSignCache[callSign] {
      combineQRZInfo(qrzInfo: qrzInfo, frequency: frequency)
    } else {
      let parser = XMLParser(contentsOf: urlString)!

      parser.delegate = self
      if parser.parse() {
        if self.results != nil { //} && self.results?.count != 0 {
          switch qrZedCallSignPair.count {
          case 0:
            return
          case 1:
            populateQRZInfo(frequency: frequency)
          default:
            print("Excess CallSignPairCount: \(qrZedCallSignPair.count)")
          }
//          if qrZedCallSignPair.count > 1 {
//            qrZedCallSignPair.removeAll()
//          } else {
//            if qrZedCallSignPair.count > 2 {
//              print("Excess CallSignPairCount: \(qrZedCallSignPair.count)")
//            }
//          }
//          populateQRZInfo(frequency: frequency)
        } else {
          // we did not get one or more hits
          // will move this to CallParser and call it there
          logger.info("Use CallParser: \(callSign)") // above I think
        }
      }
    }
  }

  /// Populate the qrzInfo with latitude, longitude, etc. If there is a pair
  /// send them to the view controller for a line to be drawn.
  /// - Parameter frequency: frequency represented as a string
  func populateQRZInfo(frequency: String) {

    qrZedInfo = QRZInfo()

    // maybe check if dictionary is empty
    qrZedInfo.call = sessionDictionary["call"] ?? ""

    //qrzInfo.call = ("\(qrzInfo.call)/W5") // for debug
    // IF THERE IS A PREFIX OR SUFFIX CALL CALL PARSER AND SKIP SOME OF THIS
    // ALSO IF WE DON'T GET ANYTHING from QRZ
    if qrZedInfo.call.contains("/") { // process it
      let hitList: [Hit] = callLookup.lookupCall(call: qrZedInfo.call)
      if !hitList.isEmpty {
        qrZedInfo = populateQRZInfo(hitList: hitList)
      }
    } else {
      qrZedInfo.latitude = Double(sessionDictionary["lat"] ?? "0.0") ?? 00
      if qrZedInfo.latitude == 00 {
        qrZedInfo.error = true
        //print("latitude error: \(qrZedInfo.call)")
        logger.info("Latitude error: \(self.qrZedInfo.call)")
      }

      qrZedInfo.longitude = Double(sessionDictionary["lon"] ?? "0.0") ?? 00
      if qrZedInfo.longitude == 00 {
        qrZedInfo.error = true
        //print("longitude error: \(qrZedInfo.call)")
        logger.info("Longitude error: \(self.qrZedInfo.call)")
      }

      // if there is a prefix or suffix I need to find correct country and lat/lon
      qrZedInfo.country = sessionDictionary["country"] ?? ""
      qrZedInfo.grid = sessionDictionary["grid"] ?? ""
      qrZedInfo.lotw = Bool(sessionDictionary["lotw"] ?? "0") ?? false
      qrZedInfo.aliases = sessionDictionary["aliases"] ?? ""
    }

    // add to call sign cache
    qrZedCallSignCache[qrZedInfo.call] = qrZedInfo
    combineQRZInfo(qrzInfo: qrZedInfo, frequency: frequency)
  }

  /**
   Create a QRZInfo object from the hitlist.
   - parameters:
   - hitList: the array of hits returned
   */
  func populateQRZInfo(hitList: [Hit]) -> QRZInfo {
    qrZedInfo = QRZInfo()

    let hit = hitList[hitList.count - 1]

    qrZedInfo.call = hit.call
    qrZedInfo.country = hit.country

    if let latitude = Double(hit.latitude) {
      qrZedInfo.latitude = latitude
    }

    if let longitude = Double(hit.longitude) {
      qrZedInfo.latitude = longitude
    }

    print("hit: \(qrZedInfo.call)")

    return qrZedInfo
  }

  /**
   Combine the QRZ information and send it to the view controller for a line to be drawn.
   - parameters:
   - qrzCallSignPairCopy: the pair of QRZInfo to be combined
   - frequency: frequency to add to structure
   */
  func combineQRZInfo(qrzInfo: QRZInfo, frequency: String) {

    qrZedCallSignPair.append(qrzInfo)

    if qrZedCallSignPair.count == 2 {
      let qrzCallSignPairCopy = qrZedCallSignPair // use copy so we don't read while modifying
      var qrzInfoCombined = QRZInfoCombined()

      qrzInfoCombined.setFrequency(frequency: frequency)

      qrzInfoCombined.spotterCall = qrzCallSignPairCopy[0].call
      qrzInfoCombined.spotterCountry = qrzCallSignPairCopy[0].country
      qrzInfoCombined.spotterLatitude = qrzCallSignPairCopy[0].latitude
      qrzInfoCombined.spotterLongitude = qrzCallSignPairCopy[0].longitude
      qrzInfoCombined.spotterGrid = qrzCallSignPairCopy[0].grid
      qrzInfoCombined.spotterLotw = qrzCallSignPairCopy[0].lotw
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

      self.qrZedManagerDelegate?.qrzManagerDidGetCallSignData(self,
        messageKey: .qrzInformation, qrzInfoCombined: qrzInfoCombined)
    }
  }

} // end class

/*
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
 
 
 <QRZDatabase version="1.33" xmlns="http://xmldata.qrz.com">
 <Session>
 <Key>d078471d55aef6e17fb566ef6e381e03</Key>
 <Count>9465097</Count>
 <SubExp>Sun Dec 29 00:00:00 2019</SubExp>
 <GMTime>Thu Feb 28 18:11:31 2019</GMTime>
 <Remark>cpu: 0.162s</Remark>
 </Session>
 </QRZDatabase>
 */
