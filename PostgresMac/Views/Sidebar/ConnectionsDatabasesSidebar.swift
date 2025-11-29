//
//  ConnectionsDatabasesSidebar.swift
//  PostgresMac
//
//  Created by ghazi on 11/28/25.
//

import SwiftUI

struct ConnectionsDatabasesSidebar: View {
    @Environment(AppState.self) private var appState
    @State private var selectedDatabaseID: DatabaseInfo.ID?

    var body: some View {
        List(selection: Binding<DatabaseInfo.ID?>(
            get: { selectedDatabaseID },
            set: { newID in
                guard let unwrappedID = newID else {
                    selectedDatabaseID = nil
                    appState.selectedDatabase = nil
                    appState.tables = []
                    appState.isLoadingTables = false
                    print("🔴 [ConnectionsDatabasesSidebar] Selection cleared")
                    return
                }
                selectedDatabaseID = unwrappedID
                print("🟢 [ConnectionsDatabasesSidebar] selectedDatabaseID changed to \(unwrappedID)")

                // Find the database object from the ID
                let database = appState.databases.first { $0.id == unwrappedID }

                print("🔵 [ConnectionsDatabasesSidebar] Updating selectedDatabase to: \(database?.name ?? "nil")")
                appState.selectedDatabase = database

                // Clear tables immediately and show loading state
                appState.tables = []
                appState.isLoadingTables = true
                print("🟡 [ConnectionsDatabasesSidebar] Cleared tables, isLoadingTables=true")

                if let database = database {
                    print("🟠 [ConnectionsDatabasesSidebar] Starting loadTables for: \(database.name)")
                    Task {
                        await loadTables(for: database)
                    }
                } else {
                    print("🔴 [ConnectionsDatabasesSidebar] No database selected, stopping loading")
                    appState.isLoadingTables = false
                }
            }
        )) {
            Section("Connection") {
                ConnectionPickerView()
            }

            Section("Databases") {
                if appState.databases.isEmpty {
                    Text("No databases")
                        .foregroundColor(.secondary)
                        .italic()
                } else {
                    ForEach(appState.databases) { database in
                        DatabaseRowView(database: database)
                    }
                }
            }
        }
        .navigationTitle("Databases")
        .toolbar {
            ToolbarItem {
                Button(action: refreshDatabases) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(!appState.isConnected)
            }
        }
        .onChange(of: appState.isConnected) { oldValue, newValue in
            if newValue {
                refreshDatabases()
            }
        }
    }
    
    private func refreshDatabases() {
        Task {
            await refreshDatabasesAsync()
        }
    }
    
    private func refreshDatabasesAsync() async {
        do {
            appState.databases = try await appState.databaseService.fetchDatabases()
        } catch {
            print("Failed to refresh databases: \(error)")
        }
    }
    
    private func loadTables(for database: DatabaseInfo) async {
        print("📍 [loadTables] START for database: \(database.name)")

        defer {
            print("📍 [loadTables] END - setting isLoadingTables=false")
            appState.isLoadingTables = false
        }

        do {
            // Reconnect to the selected database
            guard let connection = appState.currentConnection else {
                print("❌ [loadTables] ERROR: No current connection")
                return
            }
            print("✅ [loadTables] Current connection: \(connection.name)")

            // Get password from Keychain
            print("🔑 [loadTables] Getting password from Keychain for connection: \(connection.id)")
            let password = try KeychainService.getPassword(for: connection.id) ?? ""
            print("✅ [loadTables] Password retrieved (length: \(password.count))")

            // Reconnect to the selected database
            print("🔌 [loadTables] Connecting to database: \(database.name) at \(connection.host):\(connection.port)")
            try await appState.databaseService.connect(
                host: connection.host,
                port: connection.port,
                username: connection.username,
                password: password,
                database: database.name
            )
            print("✅ [loadTables] Connected successfully to \(database.name)")

            // Now fetch tables from the newly connected database
            print("📊 [loadTables] Fetching tables from database: \(database.name)")
            appState.tables = try await appState.databaseService.fetchTables(database: database.name)
            print("✅ [loadTables] Fetched \(appState.tables.count) tables")
            for (index, table) in appState.tables.enumerated() {
                print("   Table \(index + 1): \(table.schema).\(table.name)")
            }
        } catch {
            print("❌ [loadTables] ERROR: \(error)")
            print("❌ [loadTables] Error details: \(String(describing: error))")
            appState.tables = []
        }
    }
}

private struct DatabaseRowView: View {
    let database: DatabaseInfo

    var body: some View {
        NavigationLink(value: database.id) {
            Label(database.name, systemImage: "externaldrive")
        }
    }
}
