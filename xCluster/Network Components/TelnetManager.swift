//
//  TelnetManager.swift
//  xCluster
//
//  Created by Peter Bourget on 7/8/20.
//  Copyright © 2020 Peter Bourget. All rights reserved.
//

import Cocoa
import Network
import os

//struct ServerStatus: Codable {
//  let activeUsers: Int
//}

protocol TelnetManagerDelegate: AnyObject {

  func connect(cluster: ClusterIdentifier)

  func telnetManagerStatusMessageReceived(_ telnetManager: TelnetManager, messageKey: NetworkMessage, message: String)

  func telnetManagerDataReceived(_ telnetManager: TelnetManager, messageKey: NetworkMessage, message: String)
}

// Someday look at rewriting this from
// https://rderik.com/blog/building-a-server-client-aplication-using-apple-s-network-framework/

class TelnetManager {

  // MARK: - Field Definitions ----------------------------------------------------------------------------

  private let serialTelnetQueue =
    DispatchQueue(label: "com.w6op.virtualCluster.telnetQueue") // ,attributes: .concurrent

  let logger = Logger(subsystem: "com.w6op.xCluster", category: "TelnetManager")

  // delegate to pass messages back to controller
  weak var telnetManagerDelegate: TelnetManagerDelegate?

  var connection: NWConnection!
  let defaultPort = NWEndpoint.Port(23)

  var connected: Bool
  var connectionChanged: Bool
  var isLoggedOn: Bool
  var connectedHost = ClusterIdentifier(id: 0, name: "", address: "", port: "", clusterProtocol: ClusterProtocol.none)

  var clusterType: ClusterType
  var currentCommandType: CommandType

  // MARK: - init Overrides ----------------------------------------------------------------------------

  init() {

    self.connected = false
    self.currentCommandType = .ignore
    self.clusterType = ClusterType.unknown
    self.connectionChanged = false
    self.isLoggedOn = false

  }

  // MARK: - Network Implementation ----------------------------------------------------------------------------

  /**
   Connect to the cluster server.
   - parameters:
   - host: The host name to connect to.
   - port: The port to connect to.
   */
  func connect(cluster: ClusterIdentifier) {

      connectedHost = cluster

      connection = NWConnection(host: NWEndpoint.Host(cluster.address),
                                port: NWEndpoint.Port(cluster.port) ?? defaultPort, using: .tcp)
      connection.stateUpdateHandler = stateDidChange(to:)
      start()

  }

  /// Start the telnet connection.
  func start() {
    connection.start(queue: serialTelnetQueue)
  }

  /// Handle state changes to the connection.
  /// - Parameter state: state description.
  private func stateDidChange(to state: NWConnection.State) {

    switch state {

    case .ready:
      self.connected = true
      self.connectionChanged = true
      //self.clusterType = .unknown
      //print("line 99")

      self.telnetManagerDelegate?.telnetManagerStatusMessageReceived(self,
        messageKey: .connected, message: "Connected to \(connectedHost)")

      self.telnetManagerDelegate?.telnetManagerDataReceived(self,
        messageKey: .clusterType, message: "Connected")

      self.startReceive()

    case .waiting(let error):
      self.connection.restart()
      print("Restarted: \(error)")

    case .failed(let error):
      self.handleConnectionError(error: error)

    case .cancelled:
      print("Connection Cancelled")

    case .setup:
      print("Connection Setup")

    case .preparing:
      print("Connection Preparing")

    @unknown default:
      print("Connection State Unknown")
    }
  }

  /// Start receiving data.
  func startReceive() {
    connection.receive(minimumIncompleteLength: 1, maximumLength: Int(UINT32_MAX), completion: receiveMessage)
  }

  /**
   Receive completion handler.
   - parameters:
   - data: The data received.
   - context:
   - isComplete:
   - error:
   */
  func receiveMessage(data: Data?, context: NWConnection.ContentContext?, isComplete: Bool, error: NWError?) {

    if let error = error {
      print("receiveMessage: \(error)")
      handleConnectionError(error: error)
    }

    // ignore nil messages
    guard data != nil else { return }
    if currentCommandType == .keepAlive {currentCommandType = .ignore}

    guard let response = String(data: data!, encoding: .utf8)?.trimmingCharacters(in: .whitespaces) else {
      return
    }

    let lines = response.components(separatedBy: "\r\n")
    if lines.isEmpty {
      print("nil response: \(response)")
    }

    for line in lines where !line.isEmpty {
        determineMessageType(message: line.trimmingCharacters(in: .whitespaces))
    }

    if isComplete {
      logger.info("Data receive completed.")
      //os_log("Data receive completed.", log: TelnetManager.modelLog, type: .info)
    }

    startReceive()
  }

  ///Send a message or command to the cluster server.
  ///
  ///- parameters:
  ///- message: The data sent.
  ///- commandType: The type of command received.
  func send(_ message: String, commandType: CommandType) {

      if connected {
        let newMessage = message + "\r\n"

        if let data = newMessage.data(using: .utf8) {
          connection.send(content: data, completion: .contentProcessed({(error) in
            if let error = error {
              print("send: \(error)")
              self.telnetManagerDelegate?.telnetManagerStatusMessageReceived(self,
                              messageKey: .error, message: "SEND ERROR: \(error)")
              self.handleConnectionError(error: error)
            }
          }))
        }
      }

  }

  /// Disconnect from the telnet session and break the connection.
  func disconnect() {
    if connected && clusterType != .html {
      send("bye", commandType: .ignore)
      connection.cancel()
    }
  }

  /// Determine if the message is a spot or a status message.
  /// - Parameter message: The message text.
  func determineMessageType(message: String) {

    switch message.description {
    case _ where message.contains("login:"):
      self.telnetManagerDelegate?.telnetManagerStatusMessageReceived(self,
                            messageKey: .loginRequested, message: message)

    case _ where message.contains("Please enter your call"):
      self.telnetManagerDelegate?.telnetManagerStatusMessageReceived(self,
                          messageKey: .callSignRequested, message: message)

    case _ where message.contains("Please enter your name"):
      self.telnetManagerDelegate?.telnetManagerStatusMessageReceived(self,
                              messageKey: .nameRequested, message: message)

    case _ where message.contains("Please enter your QTH"):
      self.telnetManagerDelegate?.telnetManagerStatusMessageReceived(self,
                              messageKey: .qthRequested, message: message)

    case _ where message.contains("Please enter your location"):
      self.telnetManagerDelegate?.telnetManagerStatusMessageReceived(self,
                                  messageKey: .location, message: message)

    case _ where message.contains("DX de"):
      self.telnetManagerDelegate?.telnetManagerDataReceived(self,
                              messageKey: .spotReceived, message: message)

    case _ where message.contains("Is this correct"):
      send("Y", commandType: .yes)
      currentCommandType = .yes

    case _ where message.contains("dxspider >"):
      if !isLoggedOn {
        isLoggedOn = true
        self.telnetManagerDelegate?.telnetManagerStatusMessageReceived(self,
                              messageKey: .loginCompleted, message: message)
      }

    case _ where Int(message.condenseWhitespace().prefix(4)) != nil:
      self.telnetManagerDelegate?.telnetManagerDataReceived(self, messageKey: .showDxSpots, message: message)

    case _ where message.contains("Invalid command"):
      self.telnetManagerDelegate?.telnetManagerDataReceived(self, messageKey: .invalid, message: "")
      print("sequence invalid command \(message)")

    default:
      if self.connectionChanged {
        determineClusterType(message: message)
      }
      self.telnetManagerDelegate?.telnetManagerDataReceived(self, messageKey: .clusterInformation, message: message)
    }
  }

  /// Determine what cluster type we connected to.
  /// - Parameter message: string to be parsed.
  func determineClusterType(message: String) {

    switch message.description {
    case _ where message.contains("Invalid command"):
      self.telnetManagerDelegate?.telnetManagerDataReceived(self, messageKey: .invalid, message: "")

    case _ where message.contains("CC-Cluster"):
      self.clusterType = .ccCluster
      self.connectionChanged = false
      self.telnetManagerDelegate?.telnetManagerDataReceived(self,
      messageKey: .clusterType, message: "Connected to CC-Cluster")

    case _ where message.contains("CC Cluster"), _ where message.contains("CCC_Commands"):
      self.clusterType = .ccCluster
      self.connectionChanged = false
      self.telnetManagerDelegate?.telnetManagerDataReceived(self,
          messageKey: .clusterType, message: "Connected to CC-Cluster")

    case _ where message.contains("AR-Cluster"):
      self.clusterType = .arCluster
      self.connectionChanged = false
      self.telnetManagerDelegate?.telnetManagerDataReceived(self,
          messageKey: .clusterType, message: "Connected to AR-Cluster")

    case _ where message.contains("DXSpider"):
      self.clusterType = .dxSpider
      self.connectionChanged = false
      self.telnetManagerDelegate?.telnetManagerDataReceived(self,
          messageKey: .clusterType, message: "Connected to DXSpider")

    case _ where message.uppercased().contains("VE7CC"):
      self.clusterType = .ve7cc
      self.connectionChanged = false
      self.telnetManagerDelegate?.telnetManagerDataReceived(self,
          messageKey: .clusterType, message: "Connected to VE7CC Cluster")

    default:
      //break
      print("line 299: \(message)")
      //self.clusterType = .unknown
    }
  }

  /// Handle the errors when there is a connection problem.
  /// - Parameter error: error description.
  func handleConnectionError(error: NWError) {

    switch error {

    case .posix(.ECONNREFUSED):
      print("Posix .ECONNREFUSED")

    case .posix(.EPERM):
      print("Posix .EPERM")

    case .posix(.ENOENT):
      print("Posix .ENOENT")

    //    case .posix(.ESRCH):
    //      break
    //    case .posix(.EINTR):
    //      break
    //    case .posix(.EIO):
    //      break
    //    case .posix(.ENXIO):
    //      break
    //    case .posix(.E2BIG):
    //      break
    //    case .posix(.ENOEXEC):
    //      break
    //    case .posix(.EBADF):
    //      break
    //    case .posix(.ECHILD):
    //      break
    //    case .posix(.EDEADLK):
    //      break
    //    case .posix(.ENOMEM):
    //      break
    //    case .posix(.EACCES):
    //      break
    //    case .posix(.EFAULT):
    //      break
    //    case .posix(.ENOTBLK):
    //      break
    //    case .posix(.EBUSY):
    //      break
    //    case .posix(.EEXIST):
    //      break
    //    case .posix(.EXDEV):
    //      break
    //    case .posix(.ENODEV):
    //      break
    //    case .posix(.ENOTDIR):
    //      break
    //    case .posix(.EISDIR):
    //      break
    //    case .posix(.EINVAL):
    //      break
    //    case .posix(.ENFILE):
    //      break
    //    case .posix(.EMFILE):
    //      break
    //    case .posix(.ENOTTY):
    //      break
    //    case .posix(.ETXTBSY):
    //      break
    //    case .posix(.EFBIG):
    //      break
    //    case .posix(.ENOSPC):
    //      break
    //    case .posix(.ESPIPE):
    //      break
    //    case .posix(.EROFS):
    //      break
    //    case .posix(.EMLINK):
    //      break
    //    case .posix(.EPIPE):
    //      break
    //    case .posix(.EDOM):
    //      break
    //    case .posix(.ERANGE):
    //      break
    //    case .posix(.EAGAIN):
    //      break
    //    case .posix(.EINPROGRESS):
    //      break
    //    case .posix(.EALREADY):
    //      break
    //    case .posix(.ENOTSOCK):
    //      break
    //    case .posix(.EDESTADDRREQ):
    //      break
    //    case .posix(.EMSGSIZE):
    //      break
    //    case .posix(.EPROTOTYPE):
    //      break
    //    case .posix(.ENOPROTOOPT):
    //      break
    //    case .posix(.EPROTONOSUPPORT):
    //      break
    //    case .posix(.ESOCKTNOSUPPORT):
    //      break
    //    case .posix(.ENOTSUP):
    //      break
    //    case .posix(.EPFNOSUPPORT):
    //      break
    //    case .posix(.EAFNOSUPPORT):
    //      break
    //    case .posix(.EADDRINUSE):
    //      break
    //    case .posix(.EADDRNOTAVAIL):
    //      break
    //    case .posix(.ENETDOWN):
    //      break
    //    case .posix(.ENETUNREACH):
    //      break
    //    case .posix(.ENETRESET):
    //      break
    //    case .posix(.ECONNABORTED):
    //      break
    case .posix(.ECONNRESET):
      print("Posix .ECONNRESET")
      self.telnetManagerDelegate?.telnetManagerStatusMessageReceived(self, messageKey: .disconnected, message: "")
    //    case .posix(.ENOBUFS):
    //      break
    //    case .posix(.EISCONN):
    //      break
    case .posix(.ENOTCONN):
      print("Posix .ENOTCONN")
      self.telnetManagerDelegate?.telnetManagerStatusMessageReceived(self, messageKey: .disconnected, message: "")
    //    case .posix(.ESHUTDOWN):
    //      break
    //    case .posix(.ETOOMANYREFS):
    //      break
    //    case .posix(.ETIMEDOUT):
    //      break
    //    case .posix(.ELOOP):
    //      break
    //    case .posix(.ENAMETOOLONG):
    //      break
    //    case .posix(.EHOSTDOWN):
    //      break
    case .posix(.EHOSTUNREACH):
      print("Posix .EHOSTUNREACH")
      print("Connection Error: \(error) Localized: \(error.localizedDescription)")
      self.telnetManagerDelegate?.telnetManagerStatusMessageReceived(self, messageKey: .disconnected, message: "")
    //    case .posix(.ENOTEMPTY):
    //      break
    //    case .posix(.EPROCLIM):
    //      break
    //    case .posix(.EUSERS):
    //      break
    //    case .posix(.EDQUOT):
    //      break
    //    case .posix(.ESTALE):
    //      break
    //    case .posix(.EREMOTE):
    //      break
    //    case .posix(.EBADRPC):
    //      break
    //    case .posix(.ERPCMISMATCH):
    //      break
    //    case .posix(.EPROGUNAVAIL):
    //      break
    //    case .posix(.EPROGMISMATCH):
    //      break
    //    case .posix(.EPROCUNAVAIL):
    //      break
    //    case .posix(.ENOLCK):
    //      break
    //    case .posix(.ENOSYS):
    //      break
    //    case .posix(.EFTYPE):
    //      break
    //    case .posix(.EAUTH):
    //      break
    //    case .posix(.ENEEDAUTH):
    //      break
    //    case .posix(.EPWROFF):
    //      break
    //    case .posix(.EDEVERR):
    //      break
    //    case .posix(.EOVERFLOW):
    //      break
    //    case .posix(.EBADEXEC):
    //      break
    //    case .posix(.EBADARCH):
    //      break
    //    case .posix(.ESHLIBVERS):
    //      break
    //    case .posix(.EBADMACHO):
    //      break
    case .posix(.ECANCELED):
      print("Posix .ECANCELED")
      self.telnetManagerDelegate?.telnetManagerStatusMessageReceived(self, messageKey: .cancelled, message: "")
    //    case .posix(.EIDRM):
    //      break
    //    case .posix(.ENOMSG):
    //      break
    //    case .posix(.EILSEQ):
    //      break
    //    case .posix(.ENOATTR):
    //      break
    //    case .posix(.EBADMSG):
    //      break
    //    case .posix(.EMULTIHOP):
    //      break
    //    case .posix(.ENODATA):
    //      break
    //    case .posix(.ENOLINK):
    //      break
    //    case .posix(.ENOSR):
    //      break
    //    case .posix(.ENOSTR):
    //      break
    //    case .posix(.EPROTO):
    //      break
    //    case .posix(.ETIME):
    //      break
    //    case .posix(.ENOPOLICY):
    //      break
    //    case .posix(.ENOTRECOVERABLE):
    //      break
    //    case .posix(.EOWNERDEAD):
    //      break
    //    case .posix(.EQFULL):
    //      break
    case .posix:
      print("Posix .posix")
      print("Connection Error: \(error) Localized: \(error.localizedDescription)")
      self.telnetManagerDelegate?.telnetManagerStatusMessageReceived(self, messageKey: .disconnected, message: "")
    case .dns:
      print("Posix .dns")
    case .tls:
      print("Posix .tls")
    @unknown default:
      print("Posix @unknown default: \(String(describing: error))")
    }
  }
} // end class
