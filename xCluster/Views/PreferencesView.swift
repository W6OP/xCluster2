//
//  PreferencesView.swift
//  xCluster
//
//  Created by Peter Bourget on 3/13/21.
//

import SwiftUI

struct PreferencesView: View {
  @Environment(\.presentationMode) var presentationMode
  @Environment(\.colorScheme) var currentMode
  @ObservedObject var userSettings = UserSettings()

  var body: some View {
    VStack {
      HStack {
        Form {
          Section(header: Text("Your Information")) {
            HStack {
              Text("Call")
              Spacer()
              TextField("", text: $userSettings.callsign)
              .textFieldStyle(RoundedBorderTextFieldStyle())
              //.frame(minWidth: 230, maxWidth: 230)
            }
            HStack {
              Text("Full Name")
              TextField("", text: $userSettings.fullname)
                .textFieldStyle(RoundedBorderTextFieldStyle())
              //.frame(minWidth: 230, maxWidth: 230)
            }
            HStack {
              Text("City, State")
              Spacer()
              TextField("", text: $userSettings.location)
                .textFieldStyle(RoundedBorderTextFieldStyle())
              //.frame(minWidth: 230, maxWidth: 230)
            }
            HStack {
              Text("Grid")
              Spacer()
              TextField("", text: $userSettings.grid)
                .textFieldStyle(RoundedBorderTextFieldStyle())
              //.frame(minWidth: 230, maxWidth: 230)
            }
          }
        }
      }

      HStack {
        Spacer()
      }

      HStack {
        Form {
          Section(header: Text("QRZ Credentials")) {
            HStack {
              Text("User Name")
              TextField("", text: $userSettings.username)
              .textFieldStyle(RoundedBorderTextFieldStyle())
            }
            HStack {
              Text("Password")
              Spacer()
                .frame(minWidth: 18, maxWidth: 18)
              SecureField("", text: $userSettings.password)
              .textFieldStyle(RoundedBorderTextFieldStyle())
            }
            Button(action: {self
              .presentationMode
              .wrappedValue
              .dismiss()}) {
              Text("Close")
            }
          }
        }
      }
      //.frame(minWidth: 275,maxWidth: 275)
    }
      .frame(minWidth: 300, maxWidth: 300)
    .padding(5)
    .background(currentMode == .dark ?  Color.black : Color(red: 209 / 255, green: 215 / 255, blue: 226 / 255))
  }
}

struct PreferencesView_Previews: PreviewProvider {
  static var previews: some View {
    PreferencesView()
  }
}
