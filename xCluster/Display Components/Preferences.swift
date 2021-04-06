//
//  Preferences.swift
//  xCluster
//
//  Created by Peter Bourget on 3/29/21.
//

import Foundation

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
