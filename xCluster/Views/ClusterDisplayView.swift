//
//  ClusterDisplayView.swift
//  xCluster
//
//  Created by Peter Bourget on 7/27/20.
//  Copyright © 2020 Peter Bourget. All rights reserved.
//

import SwiftUI

struct ClusterDisplayView: View {
  @ObservedObject var controller: Controller
  
    var body: some View {
        // MARK: - Spot list display.
        
        HStack{
          ListDisplayView(controller: controller)
          
          StatusDisplayView(controller: controller)
        }
        .frame(maxWidth: .infinity, minHeight: 800, maxHeight: 1000)// , maxHeight: 300
        .padding(.vertical,0)
    }
}

// MARK: - Cluster list display.
struct ListDisplayView: View {
  @ObservedObject var controller: Controller
  
    var body: some View {
      HStack{
        ScrollView {
          VStack{
            SpotHeader()
            Divider()
              .frame(maxHeight: 1)
              .padding(-5)
            ForEach(controller.spots, id: \.self) { spot in
              SpotRow(spot: spot)
            }
          }
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 30, maxHeight: .infinity, alignment: .topLeading) // minHeight: 300, maxHeight: 300,
          .background(Color(red: 209 / 255, green: 215 / 255, blue: 226 / 255))
        }
      }
      .border(Color.gray)
    }
}

// MARK: - Spot Header

struct SpotHeader: View {
  var body: some View {
    
    HStack{
      Text("DX")
        .frame(minWidth: 75)
      Text("Frequency")
        .frame(minWidth: 90)
      Text("Spotter")
        .frame(minWidth: 75)
      Text("Time")
        .frame(minWidth: 60)
      Text("Comment")
        .padding(.leading, 20)
        .frame(minWidth: 250, alignment: .leading)
      Text("Grid")
        .frame(minWidth: 50)
      Spacer()
    }
    .foregroundColor(Color.red)
    .font(.system(size: 14))
    .padding(0)
  }
}

// MARK: - Spot Row

struct SpotRow: View {
  var spot: ClusterSpot
  
  var body: some View {
    VStack{
      HStack{
        Text(spot.dxStation)
          .frame(minWidth: 75,alignment: .leading)
          .padding(.leading, 5)
        Text(spot.frequency)
          .frame(minWidth: 90,alignment: .leading)
        Text(spot.spotter)
          .frame(minWidth: 75,alignment: .leading)
        Text(spot.dateTime)
          .frame(minWidth: 60,alignment: .leading)
        Text(spot.comment)
          .frame(minWidth: 250,alignment: .leading)
          .padding(.leading, 5)
          .padding(.trailing, 5)
        Text(spot.grid)
          .frame(minWidth: 50,alignment: .leading)
        Spacer()
      }
      .frame(maxWidth: .infinity, maxHeight: 15)
      .padding(.leading, 5)
      .padding(.top, -5)
      .padding(.bottom, -5)
      
      VStack{
        Divider()
          .frame(maxHeight: 1)
          .padding(-5)
      }
      .frame(maxWidth: .infinity, maxHeight: 1)
    }
  }
}


// MARK: - Status message display.
struct StatusDisplayView: View {
  @ObservedObject var controller: Controller
  
    var body: some View {
      HStack{
        ScrollView {
          VStack{
            ForEach(controller.statusMessage, id: \.self) { message in
              HStack{
                Text(message)
                  .padding(.leading, 2)
                  .foregroundColor(Color.black)
                Spacer()
              }
              .frame(maxHeight: 15)
              .multilineTextAlignment(.leading)
            }
          }
            .frame(minWidth: 300, maxWidth: .infinity, minHeight: 30, maxHeight: .infinity, alignment: .topLeading) // , minHeight: 300, maxHeight: 300
          .background(Color(red: 209 / 255, green: 215 / 255, blue: 226 / 255))
        }
      }
      .border(Color.gray)
    }
}


/// Preview of ClusterDisplayView
struct ClusterDisplayView_Previews: PreviewProvider {
    static var previews: some View {
      ClusterDisplayView(controller: Controller())
    }
}
