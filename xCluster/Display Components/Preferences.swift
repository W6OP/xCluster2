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
    callsign = UserDefaults.standard.string(forKey: "callsign") ?? ""
    username = UserDefaults.standard.string(forKey: "username") ?? ""
    password = UserDefaults.standard.string(forKey: "password") ?? ""
    fullname = UserDefaults.standard.string(forKey: "fullname") ?? ""
    location = UserDefaults.standard.string(forKey: "location") ?? ""
    grid = UserDefaults.standard.string(forKey: "grid") ?? ""
  }
}
