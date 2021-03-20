//
//  Spot Processor.swift
//  xCluster
//
//  Created by Peter Bourget on 7/8/20.
//  Copyright © 2020 Peter Bourget. All rights reserved.
//

// Take a raw spot and break it into its component parts

import Foundation

class SpotProcessor {

     init() {

    }

    //      12 chars
    // DX de LY3AB:     1887.0  LY2RJ        cq cq cq                       1743Z KO25
    func processSpot(rawSpot: String) throws -> ClusterSpot {

      var spot = ClusterSpot(id: 0, dxStation: "", frequency: "", spotter: "", dateTime: "", comment: "", grid: "")

      //print("processSpot: \(rawSpot)")

        if rawSpot.count < 75 {
            print("\(rawSpot.count) -- \(rawSpot)")
            throw SpotError.spotError("processRawSpot: spot length too short")
        }

        let spotter = rawSpot.components(separatedBy: ":")
        // replacing -# for AE5E - don't know why he does that "W6OP-#" and "W6OP-2-#"
        spot.spotter =  convertStringSliceToString(spotter[0].components(separatedBy: " ")[2])
        if spot.spotter.contains("-") {
          let index = spot.spotter.firstIndex(of: "-")
          let startIndex = spot.spotter.startIndex
          spot.spotter = convertStringSliceToString(String(spot.spotter[startIndex..<index!])).condenseWhitespace()
        }

        var startIndex = rawSpot.index(rawSpot.startIndex, offsetBy: 16)
        var endIndex = rawSpot.index(startIndex, offsetBy: 9)
        let frequency = convertStringSliceToString(String(rawSpot[startIndex..<endIndex])).condenseWhitespace()
        guard Float(frequency) != nil else {
            throw SpotError.spotError("processRawSpot: unable to parse frequency")
        }
        spot.frequency = convertFrequencyToDecimalString(frequency: frequency)

        startIndex = rawSpot.index(rawSpot.startIndex, offsetBy: 26)
        endIndex = rawSpot.index(startIndex, offsetBy: 11)
        spot.dxStation = convertStringSliceToString(String(rawSpot[startIndex..<endIndex]))

        startIndex = rawSpot.index(rawSpot.startIndex, offsetBy: 39)
        endIndex = rawSpot.index(startIndex, offsetBy: 30)
        spot.comment = convertStringSliceToString(String(rawSpot[startIndex..<endIndex]))

        startIndex = rawSpot.index(rawSpot.startIndex, offsetBy: 70)
        endIndex = rawSpot.index(startIndex, offsetBy: 5)
        // clean of junk on end so it displays correctly when no grid supplied
        spot.dateTime = convertStringSliceToString(String(rawSpot[startIndex..<endIndex])).condenseWhitespace()

        endIndex = rawSpot.endIndex
        startIndex = rawSpot.index(rawSpot.startIndex, offsetBy: 75)

        // clean of junk on end so it displays correctly
        spot.grid = convertStringSliceToString(String(rawSpot[startIndex..<endIndex])).condenseWhitespace()
        // remove /a/a at end
        spot.grid = spot.grid.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()

        return spot
    }

  /**
     Process a telnet packet from a show/dx command.
     real or rt - Format the output the same as for real time spots. The
                      formats are deliberately different (so you can tell
                      one sort from the other). This is useful for some
                      logging programs that can't cope with normal sh/dx
                      output. An alias of SHOW/FDX is available.
     - parameters:
     - rawSpot: the string received via telnet.
     - returns:
     */
    func processShowDxSpot(rawSpot: String) throws ->  ClusterSpot {

        var spot = ClusterSpot(id: 0, dxStation: "", frequency: "", spotter: "", dateTime: "", comment: "", grid: "")

        //print("processShowDxSpot: \(rawSpot)")

        if rawSpot.count < 65 {
            print("\(rawSpot.count) -- \(rawSpot)")
            throw SpotError.spotError("processRawShowDxSpot: spot length too short")
        }

        // grab the frequency off the front some we can get exact lengths
        let beginning = rawSpot.components(separatedBy: " ").first
        var startIndex = rawSpot.index(rawSpot.startIndex, offsetBy: beginning!.count + 1)
        var endIndex = rawSpot.endIndex
        let balance = convertStringSliceToString(String(rawSpot[startIndex..<endIndex])
                                                  .trimmingCharacters(in: .whitespaces))

        let frequency = convertStringSliceToString(beginning!).condenseWhitespace()
        // first see if the first chunk is numeric (frequency) otherwise it is a status message, probably all spots
        // have arrived
        guard Float(frequency) != nil else {
            print(frequency)
            throw SpotError.spotError("processRawShowDxSpot: unable to parse frequency")
        }
        spot.frequency = convertFrequencyToDecimalString(frequency: frequency)

        startIndex = balance.startIndex
        endIndex = balance.index(startIndex, offsetBy: 12)
        spot.dxStation = convertStringSliceToString(String(balance[startIndex..<endIndex]))

        startIndex = balance.index(balance.startIndex, offsetBy: 13)
        endIndex = balance.index(startIndex, offsetBy: 17)
        spot.dateTime = String(balance[startIndex..<endIndex])

        startIndex = balance.index(balance.startIndex, offsetBy: 30)
        endIndex = balance.index(startIndex, offsetBy: 30)
        spot.comment = convertStringSliceToString(String(balance[startIndex..<endIndex]))
        spot.comment = spot.comment.replacingOccurrences(of: "<", with: "")

        // clean of junk on end so it displays correctly when no grid supplied
        startIndex = balance.index(rawSpot.startIndex, offsetBy: 60)
        endIndex = balance.endIndex
        spot.spotter = convertStringSliceToString(String(balance[startIndex..<endIndex])).condenseWhitespace()
        spot.spotter = spot.spotter.replacingOccurrences(of: "<", with: "").replacingOccurrences(of: ">", with: "")
        // replacing -# for AE5E - don't know why he does that "W6OP-#" and "W6OP-2-#"
        if spot.spotter.contains("-") {
          let index = spot.spotter.firstIndex(of: "-")
          let startIndex = spot.spotter.startIndex
          spot.spotter = convertStringSliceToString(String(spot.spotter[startIndex..<index!])).condenseWhitespace()
        }

        return spot
    }

  /*
   spotter
   FR8TG      14032.5 LA4EJA     Tks for Qso Chris 73 cw       1558 19 Mar
   R0AT-@      7009.0 LA1MFA     tnx QSO                       1558 19 Mar
   DL4CH      14080.0 VA3EKG                                   1558 19 Mar
   CT1ASM     14237.0 VU3WEW     5/9 20db STRONG tnks QSO      1558 19 Mar
   LZ3YG       7165.0 YU1JW      TNX FOR qso 5/9 73 Lazare     1558 19 Mar
   R9XM        3647.0 RA3RNB                                   1558 19 Mar
   */

  func processHtmlSpot(rawSpot: String) throws -> ClusterSpot {

    var spot = ClusterSpot(id: 0, dxStation: "", frequency: "", spotter: "", dateTime: "", comment: "", grid: "")

    // first strip first 6 chars (<html>)
    var balance = rawSpot.dropFirst(6)
    var endIndex = balance.endIndex

    spot.spotter = balance.components(separatedBy: " ").first ?? "???????"

    balance = balance.dropFirst(11)
    endIndex = balance.index(balance.startIndex, offsetBy: 8)
    let frequency = convertStringSliceToString(String(balance[balance.startIndex..<endIndex]))
    guard Float(frequency) != nil else {
        print(frequency)
        throw SpotError.spotError("processRawShowDxSpot: unable to parse frequency")
    }
    spot.frequency = convertFrequencyToDecimalString(frequency: frequency)

    balance = balance.dropFirst(8)
    endIndex = balance.index(balance.startIndex, offsetBy: 10)

    spot.dxStation = convertStringSliceToString(String(balance[balance.startIndex..<endIndex]))

    balance = balance.dropFirst(11)
    endIndex = balance.index(balance.startIndex, offsetBy: 30)

    spot.comment = convertStringSliceToString(String(balance[balance.startIndex..<endIndex]))

    balance = balance.dropFirst(30)
    endIndex = balance.index(balance.startIndex, offsetBy: 4)

    spot.dateTime = convertStringSliceToString(String(balance[balance.startIndex..<endIndex]))

    return spot
  }
    /**
     Read handler.
     - parameters:
     - s: Initialize a new string instance from a slice of a string.
     Otherwise the reference to the string will never go away.
     */
    func convertStringSliceToString(_ slice: String) -> String {
        return slice.trimmingCharacters(in: .whitespaces)
    }

    /**
     Convert the frequency (10136000) to a string with a decimal place (10136.000)
     Use an extension to String to format frequency correctly. This is used to
     display the frequency formatted in the tableview.
     */
    func convertFrequencyToDecimalString (frequency: String) -> String {

        var converted: String

        var components = frequency.trimmingCharacters(in: .whitespaces).components(separatedBy: ".")
        let frequencyString = components[0]

        if components.count == 1 {
            components.append("0")
        }

        if components[1] == "" {
            components[1] = "0"
        }

        var startIndex = frequencyString.startIndex
        var endIndex = frequencyString.endIndex

        switch frequencyString.count {
        case 8: // 24048940.0 - 2404.894.00
            startIndex = frequencyString.startIndex
            endIndex = frequencyString.index(startIndex, offsetBy: 4)
            let start = frequencyString[startIndex..<endIndex]
            startIndex = frequencyString.index(frequencyString.startIndex, offsetBy: 4)
            endIndex = frequencyString.index(startIndex, offsetBy: 3)
            let end = frequencyString[startIndex..<endIndex]
            converted = ("\(start).\(end)")
        case 7: // 1296.789.000 - "2320905."
            startIndex = frequencyString.startIndex
            endIndex = frequencyString.index(startIndex, offsetBy: 4)
            let start = frequencyString[startIndex..<endIndex]
            startIndex = frequencyString.index(frequencyString.startIndex, offsetBy: 4)
            endIndex = frequencyString.endIndex
            let end = frequencyString[startIndex..<endIndex]
            converted = ("\(start).\(end)")
        case 6: //144.234.0 432174.0
            startIndex = frequencyString.startIndex
            endIndex = frequencyString.index(startIndex, offsetBy: 3)
            let start = frequencyString[startIndex..<endIndex]
            startIndex = frequencyString.index(frequencyString.startIndex, offsetBy: 3)
            endIndex = frequencyString.endIndex
            let end = frequencyString[startIndex..<endIndex]
            converted = ("\(start).\(end)")
        case 5: // 10.113
            startIndex = frequencyString.startIndex
            endIndex = frequencyString.index(startIndex, offsetBy: 2)
            let start = frequencyString[startIndex..<endIndex]
            startIndex = frequencyString.index(frequencyString.startIndex, offsetBy: 2)
            endIndex = frequencyString.endIndex
            let end = frequencyString[startIndex..<endIndex]
            converted = ("\(start).\(end)")
        case 4: // 3.563.0
            startIndex = frequencyString.startIndex
            endIndex = frequencyString.index(startIndex, offsetBy: 1)
            let start = frequencyString[startIndex..<endIndex]
            startIndex = frequencyString.index(frequencyString.startIndex, offsetBy: 1)
            endIndex = frequencyString.endIndex
            let end = frequencyString[startIndex..<endIndex]
            converted = ("\(start).\(end)")
        default:
            return frequency
        }

        if components[1] != "0" {
            converted += (".\(components[1])")
        }

        return converted
    }

} // end class

//send("set/ve7cc")
// CC11^14197.0^R7DN^27-Feb-2019^1628Z^59+9^PI3CQ^179^139^EA7URM-5^30^16^27^14^^^Eur-Russia-UA^Netherlands-PA^^\r\n
// DX de F4FGC:     14074.0  K7QXG        FT8 Tnx                        1630Z\u{07}\u{07}\r\n
// CC11^14173.0^AA3B^27-Feb-2019^1625Z^^IU7EKB^226^85^OH8X-12^8^5^28^15^^^DC-K^Italy-I^FN20^
// 14197.0  R7DN        27-Feb-2019 1628Z  59+9                         <PI3CQ>

/* DXSummit Text output
 data: <META HTTP-EQUIV="Pragma" CONTENT="no-cache"><META HTTP-EQUIV="Refresh" CONTENT=60><CENTER><PRE>
 DK4YJ       3623.5 DL5LYM                                   2020 18 Mar
 TF4M        1825.5 VK3NX      Hears well                    2020 18 Mar
 SP3DOF      7074.0 G8RZ       FT8 73 gl                     2019 18 Mar
 DF1LX       3748.6 DL9EE      bcc party LSB                 2019 18 Mar
 DJ7YP       7076.1 US0UB      tnx good dx my Tx Freq 2141Hz 2019 18 Mar
 AA0DX      14278.0 DL1KFS                                   2019 18 Mar
 DK4YJ       3705.1 DL6NCY                                   2019 18 Mar
 LZ2GS       5352.4 LA8HGA                                   2019 18 Mar
 EI8IU       3709.0 EI2SBC                                   2019 18 Mar
 F4UJU      10136.0 KO4DO      FT8 -12dB from FM07 1530Hz    2018 18 Mar
 DK4YJ       3741.9 DL8LAS                                   2018 18 Mar
 DK4YJ       3767.9 DO4OD                                    2018 18 Mar
 PP5RT       7105.0 ZZ5FLORIPA Certificate                   2018 18 Mar
 HA4XG-@     7022.0 SX7A       Pse 40m CW 60m CW/SSB         2018 18 Mar
 DK4YJ       3752.2 DB7BN                                    2018 18 Mar
 SP3DOF      7074.0 SZ21AD     FT8 73 gl                     2018 18 Mar
 DF1LX       3592.5 DL5LYM     bcc party RTTY                2017 18 Mar
 IU3KGO      7023.0 LY11LY     SES tks 73                    2017 18 Mar
 PD0LK      14080.0 K2JWD      -18 TNX FT4 QSO 73 from Leen  2017 18 Mar
 DK4YJ       3773.6 DC1MUS                                   2017 18 Mar
 F5IND       7105.0 EI7JN                                    2017 18 Mar
 RN3QRY     10136.0 F5ADE      KO91OH JN06VU FT8 +2db 73!    2017 18 Mar
 VA3EBM     14319.0 K5DGR      FN03EK DM68RV SSB             2017 18 Mar
 PT2OP-@    14074.0 PA3FQK     TKS 73                        2017 18 Mar
 WB2FVR     14075.8 IK2SAR                                   2017 18 Mar
 </PRE></CENTER><H4>DX-Summit: Last 25 DX-spots - reloaded every minute</H4><BODY></HTML>
 */
