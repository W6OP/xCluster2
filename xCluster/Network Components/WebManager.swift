//
//  WebManager.swift
//  xCluster
//
//  Created by Peter Bourget on 11/28/21.
//

import Foundation
import os

/// Web Manager Protocol
protocol WebManagerDelegate: AnyObject {
  func connect(cluster: ClusterIdentifier)
  func webManagerDataReceived(_ webManager: WebManager,
                              messageKey: NetworkMessage,
                              message: String)
}

class WebManager {

  let logger = Logger(subsystem: "com.w6op.xCluster", category: "WebManager")

  // delegate to pass messages back to controller
  weak var webManagerDelegate: WebManagerDelegate?

  var connected: Bool
  var connectionChanged: Bool
  var isLoggedOn: Bool
  var connectedHost = ClusterIdentifier(id: 0, name: "", address: "",
                                        port: "",
                                        clusterProtocol: ClusterProtocol.none)

  var clusterType: ClusterType
  var currentCommandType: CommandType

  init() {
    self.connected = false
    self.currentCommandType = .ignore
    self.clusterType = ClusterType.unknown
    self.connectionChanged = false
    self.isLoggedOn = false
  }

  /// Connect to the cluster server.
  /// - Parameter cluster: ClusterIdentifier
  func connectAsync(cluster: ClusterIdentifier) async {

    connectedHost = cluster

    if cluster.clusterProtocol == ClusterProtocol.html {
        try? await createHttpSessionAsync(host: cluster)
    } else {
      return
    }
  }

  /// Create an http session.
  /// - Parameter host: ClusterIdentifier
  func createHttpSessionAsync(host: ClusterIdentifier) async throws {

    guard let url = URL(string: host.address) else {
      print("Could not create the URL")
      return
    }

    let (data, response) = try await
        URLSession.shared.data(from: url)

    guard (response as? HTTPURLResponse)?.statusCode == 200 else {
      print("The server responded with an error")
      return
    }

    guard let mime = response.mimeType, mime == "application/json" else {
      // if not json do this
      let html = String(decoding: data, as: UTF8.self)
      self.removeHeaderAndFooter(html: html)
      return
    }

    //      do { // for future use
    //        let json = try JSONSerialization.jsonObject(with: data!, options: [])
    //        print(json)
    //      } catch {
    //        print("JSON error: \(error.localizedDescription)")
    //      }
  }

  /// Remove the header and footer from the html.
  /// - Parameter html: String
  func removeHeaderAndFooter(html: String) {

    if html.contains("<PRE>") {

      guard let startIndex = html.index(of: "<PRE>") else { return }
      guard let startIndex2 = html.index(of: "</PRE>") else { return }

      // remove the header and footer
      let range = html.index(startIndex, offsetBy: 5)..<startIndex2

      let substring = String(html[range])
      let lines = substring.split(whereSeparator: \.isNewline)

      for line in lines where !line.isEmpty {
          determineMessageType(message: "<html>" + line
                                .trimmingCharacters(in: .whitespaces))
        }
    }
  }

  /// Determine if the message is a spot or a status message.
  /// - Parameter message: String
  func determineMessageType(message: String) {

    switch message.description {

    case _ where message.contains("<html>"):
      determineClusterType(message: message)

    default:
      if self.connectionChanged {
        determineClusterType(message: message)
      }
      self.webManagerDelegate?
        .webManagerDataReceived(self, messageKey:
                                    .clusterInformation,
                                message: message)
    }
  }

  /// Determine what cluster type we connected to.
  /// - Parameter message: String
  func determineClusterType(message: String) {

    switch message.description {
    case _ where message.contains("<html>"):
      self.clusterType = .html
      self.webManagerDelegate?.webManagerDataReceived(self,
                  messageKey: .htmlSpotReceived, message: message)
    default:
      self.clusterType = .unknown
      print("line 135")
    }
  }
} // end class
