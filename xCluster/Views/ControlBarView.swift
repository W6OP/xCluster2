//
//  ControlBarView.swift
//  xCluster
//
//  Created by Peter Bourget on 4/3/22.
//

import SwiftUI

/// Cluster name picker
struct ControlBarView: View {
  var controller: Controller
  let characterLimit = 10

  @Environment(\.openURL) var openURL
  @State private var callSignFilter = ""
  @State private var showSpots = true
  @State private var filterByTime = false
  //@State private var exactMatch = false

  @State private var callSign = ""

  var body: some View {
    HStack {
      Spacer()
      HStack {

        NumberOfSpotsPickerView(controller: controller)

//        Divider()
//
//        Toggle("Last 30 minutes", isOn: $filterByTime.didSet { (filterByTime) in
//          controller.setTimeFilter(filterState: filterByTime)
//        })
//        .toggleStyle(SwitchToggleStyle(tint: Color.green))

        Divider()

        HStack {
        Image(systemName: "magnifyingglass")
        TextField("Call Filter", text: $callSignFilter, onEditingChanged: { _ in
          // onEditingChanged
          callSignFilter = callSignFilter.uppercased()
          print("editing changed \(callSignFilter)")
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

        CheckBoxView(controller: controller)

//        HStack {
//          Image(systemName: "magnifyingglass")
//          TextField("Search", text:$callSign)
//        }

        CommandButtonsView(controller: controller)
      }
      .frame(minWidth: 600)
      .padding(.leading)
      .padding(.vertical, 2)

      Spacer()
    }
  } // end body
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

struct CheckBoxView: View {
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

struct ControlBarView_Previews: PreviewProvider {
    static var previews: some View {
      ControlBarView(controller: Controller())
    }
}
