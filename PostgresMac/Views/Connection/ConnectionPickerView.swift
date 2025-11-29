//
//  ConnectionPickerView.swift
//  PostgresMac
//
//  Created by ghazi on 11/28/25.
//

import SwiftUI
import SwiftData

struct ConnectionPickerView: View {
    @Query(sort: \ConnectionProfile.lastUsed, order: .reverse) private var connections: [ConnectionProfile]
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        Picker("Connection", selection: Binding(
            get: { appState.currentConnection },
            set: { appState.currentConnection = $0 }
        )) {
            Text("Select Connection").tag(nil as ConnectionProfile?)
            ForEach(connections) { connection in
                Text(connection.name).tag(connection as ConnectionProfile?)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .onAppear {
            // Auto-select the most recently used connection if none is selected
            if appState.currentConnection == nil, let lastUsed = connections.first {
                appState.currentConnection = lastUsed
            }
        }
        .onChange(of: appState.currentConnection) { oldValue, newValue in
            if let connection = newValue {
                Task {
                    await connect(to: connection)
                }
            }
        }
    }
    
    private func connect(to connection: ConnectionProfile) async {
        do {
            // Get password from Keychain
            let password = try KeychainService.getPassword(for: connection.id) ?? ""
            
            // Connect
            try await appState.databaseService.connect(
                host: connection.host,
                port: connection.port,
                username: connection.username,
                password: password,
                database: connection.database
            )
            
            // Update connection timestamp
            connection.lastUsed = Date()
            try? modelContext.save()
            
            // Update app state
            appState.isConnected = true
            
            // Load databases
            await loadDatabases()
            
        } catch {
            // Handle error - could show alert here
            print("Failed to connect: \(error)")
        }
    }
    
    private func loadDatabases() async {
        do {
            appState.databases = try await appState.databaseService.fetchDatabases()
        } catch {
            print("Failed to load databases: \(error)")
        }
    }
}
