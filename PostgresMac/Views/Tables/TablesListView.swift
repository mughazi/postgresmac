//
//  TablesListView.swift
//  PostgresMac
//
//  Created by ghazi on 11/28/25.
//

import SwiftUI

struct TablesListView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedTableID: TableInfo.ID?

    var body: some View {
        Group {
            if appState.isLoadingTables {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading tables...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if appState.tables.isEmpty {
                ContentUnavailableView {
                    Label {
                        Text("No tables found")
                            .font(.title3)
                            .fontWeight(.regular)
                    } icon: { }
                }
            } else {
                List(selection: Binding<TableInfo.ID?>(
                    get: { selectedTableID },
                    set: { newID in
                        guard let unwrappedID = newID else {
                            selectedTableID = nil
                            appState.selectedTable = nil
                            appState.showQueryResults = false
                            appState.queryText = ""
                            appState.queryResults = []
                            print("🔴 [TablesListView] Table selection cleared")
                            return
                        }
                        selectedTableID = unwrappedID
                        print("🟢 [TablesListView] selectedTableID changed to \(unwrappedID)")

                        // Find the table object from the ID
                        let table = appState.tables.first { $0.id == unwrappedID }

                        print("🔵 [TablesListView] Updating selectedTable to: \(table?.name ?? "nil")")
                        appState.selectedTable = table

                        if let table = table {
                            print("🟠 [TablesListView] Generating and executing query for: \(table.schema).\(table.name)")
                            Task {
                                await populateAndExecuteQuery(for: table)
                            }
                        }
                    }
                )) {
                    ForEach(appState.tables) { table in
                        TableRowView(table: table)
                    }
                }
            }
        }
        .navigationTitle("Tables")
    }

    private func generateTableQuery(for table: TableInfo) -> String {
        let escapedSchema = table.schema.replacingOccurrences(of: "\"", with: "\"\"")
        let escapedTable = table.name.replacingOccurrences(of: "\"", with: "\"\"")
        return "SELECT * FROM \"\(escapedSchema)\".\"\(escapedTable)\" LIMIT \(appState.rowsPerPage);"
    }

    @MainActor
    private func populateAndExecuteQuery(for table: TableInfo) async {
        print("🔍 [TablesListView] Auto-generating query for table: \(table.schema).\(table.name)")

        // Generate SELECT query with pagination
        let query = generateTableQuery(for: table)
        print("📝 [TablesListView] Generated query: \(query)")

        // Update query text in editor
        appState.queryText = query

        // Execute query
        appState.isExecutingQuery = true
        appState.queryError = nil
        appState.queryExecutionTime = nil
        
        let startTime = Date()

        do {
            print("📊 [TablesListView] Executing query...")
            appState.queryResults = try await appState.databaseService.executeQuery(query)
            appState.showQueryResults = true
            
            let endTime = Date()
            appState.queryExecutionTime = endTime.timeIntervalSince(startTime)
            
            print("✅ [TablesListView] Query executed successfully - \(appState.queryResults.count) rows")
        } catch {
            appState.queryError = error.localizedDescription
            appState.showQueryResults = true
            
            let endTime = Date()
            appState.queryExecutionTime = endTime.timeIntervalSince(startTime)
            
            print("❌ [TablesListView] Query execution failed: \(error)")
        }

        appState.isExecutingQuery = false
    }
}
