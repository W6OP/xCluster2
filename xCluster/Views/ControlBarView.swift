//
//  ControlBarView.swift
//  xCluster
//
//  Created by Peter Bourget on 4/3/22.
//

import SwiftUI

// MARK: - Control Bar View Definition

/// Cluster name picker
struct ControlBarView: View {

  @Environment(\.openURL) var openURL
  @ObservedObject var userSettings = UserSettings()
  @State private var callSignFilter = ""
  @State private var showSpots = true
  @State private var filterByTime = false
  @State private var didTap: Bool = false
  @State private var callSign = ""

  var controller: Controller
  var clusters: [ClusterIdentifier]
  let characterLimit = 10

  var body: some View {
    HStack {
      HStack {
        Divider()

        Button("QRZ Logon") {
          self.didTap = true; controller.qrzLogon(userId: userSettings.username, password: userSettings.password)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.black, lineWidth: 1) /// here!
        )
        .background(didTap ? Color.green : Color.blue)
        .padding(.leading, 4)

        Divider()
        ClusterPickerView(controller: controller, clusters: clusters)

        Divider()
        NumberOfSpotsPickerView(controller: controller)

        Divider()

        HStack {
        Image(systemName: "magnifyingglass")
        TextField("Call Filter", text: $callSignFilter, onEditingChanged: { _ in
          // onEditingChanged
          callSignFilter = callSignFilter.uppercased()
          //print("editing changed \(callSignFilter)")
          if callSignFilter.count > characterLimit {
            callSignFilter = String(callSignFilter.prefix(characterLimit))
          }
        }) {
          // onCommit
          self.controller.setCallFilter(callSign: callSignFilter.uppercased())
        }
        .textFieldStyle(RoundedBorderTextFieldStyle())
        .modifier(ClearButton(boundText: $callSignFilter))
        .frame(maxWidth: 150)
        }

        HStack {
          CheckBoxViewExact(controller: controller)
          Divider()
          CheckBoxViewFT8(controller: controller)
        }

        CommandButtonsView(controller: controller)
      }
      .frame(minWidth: 600, maxWidth: .infinity)
      .padding(.leading)
      .padding(.vertical, 2)

      Spacer()
    }
  }
}

// MARK: - Number of Lines Picker

struct NumberOfSpotsPickerView: View {
  var controller: Controller
  let numberOfSpots: [SpotsIdentifier] = spotsData

  @State private var selectedNumberOfSpots = spotsData[1]

  var body: some View {
    HStack {
      Text("Show")
      Picker(selection: $selectedNumberOfSpots.id, label: Text("")) {
        ForEach(numberOfSpots) { spot in
          Text("\(spot.displayedLines)")
        }
      }
      .frame(minWidth: 75, maxWidth: 75)
      .onReceive([selectedNumberOfSpots].publisher.first()) { value in
        if value.id != 999 {
          if self.controller.selectedNumberOfSpots.id != value.id {
            self.controller.selectedNumberOfSpots = spotsData.first {$0.id == value.id}!
          }
        }
      }
    }
    .border(.green)
  }
}

// MARK: - Exact CheckBox

struct CheckBoxViewExact: View {
    var controller: Controller
    @State private var exactMatch = false

    var body: some View {
        Image(systemName: exactMatch ? "checkmark.square.fill" : "square")
        .foregroundColor(exactMatch ? Color(.red) : Color.black)
            .onTapGesture {
                self.exactMatch.toggle()
                controller.exactMatch = exactMatch
            }
      Text("Exact")
    }
}

// MARK: - FT8/FT4 Checkbox

struct CheckBoxViewFT8: View {
    var controller: Controller
    @State private var digiOnly = false

    var body: some View {
        Image(systemName: digiOnly ? "checkmark.square.fill" : "square")
        .foregroundColor(digiOnly ? Color(.black) : Color.black)
            .onTapGesture {
                self.digiOnly.toggle()
                controller.digiOnly = digiOnly
            }
      Text("FT4/FT8 Only")
    }
}

// MARK: - Command Buttons
struct CommandButtonsView: View {
  var controller: Controller

  var body: some View {
    HStack {
      Divider()

      Button(action: {self.controller.clusterMessage = CommandType.show20}) {
        Text("Last 20")
      }

      Divider()

      Button(action: {self.controller.clusterMessage = CommandType.show50}) {
        Text("Last 50")
      }

      Divider()

      Button(action: {self.controller.applicationMessage = CommandType.clear}) {
        Text("Clear")
      }
    }
  }
}

// MARK: - Clear Button View Modifier

public struct ClearButton: ViewModifier {
    var text: Binding<String>
    var trailing: Bool

    public init(boundText: Binding<String>, trailing: Bool = true) {
        self.text = boundText
        self.trailing = trailing
    }

    public func body(content: Content) -> some View {
        ZStack(alignment: trailing ? .trailing : .leading) {
            content

            if !text.wrappedValue.isEmpty {
                Image(systemName: "x.circle")
                    .resizable()
                    .frame(width: 17, height: 17)
                    .onTapGesture {
                        text.wrappedValue = ""
                    }
            }
        }
    }
}

// MARK: - Preview pProvider

struct ControlBarView_Previews: PreviewProvider {
    static var previews: some View {
      let clusters: [ClusterIdentifier] = clusterData
      ControlBarView(controller: Controller(), clusters: clusters)
    }
}
