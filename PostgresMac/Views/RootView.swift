//
//  RootView.swift
//  PostgresMac
//
//  Created by ghazi on 11/28/25.
//

import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(AppState.self) private var appState
    @Query private var connections: [ConnectionProfile]
    
    var body: some View {
        Group {
            if appState.isShowingWelcomeScreen && connections.isEmpty {
                WelcomeView()
            } else {
                MainSplitView()
            }
        }
        .sheet(isPresented: Binding(
            get: { appState.isShowingConnectionForm },
            set: { appState.isShowingConnectionForm = $0 }
        )) {
            ConnectionFormView()
        }
    }
}
