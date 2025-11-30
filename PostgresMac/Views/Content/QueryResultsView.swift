//
//  QueryResultsView.swift
//  PostgresMac
//
//  Created by Claude on 11/29/25.
//

import SwiftUI

struct QueryResultsView: View {
    @Environment(AppState.self) private var appState
    @State private var selection = Set<TableRow.ID>()

    var body: some View {
        VStack(spacing: 0) {
            // Results or error display
            if let error = appState.queryError {
                ContentUnavailableView {
                    Label {
                        Text("Query Failed")
                            .font(.title3)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.red)
                    }
                } description: {
                    Text(error)
                        .foregroundColor(.secondary)
                        .padding()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if appState.queryResults.isEmpty {
                ContentUnavailableView(
                    "Empty Table",
                    systemImage: "tablecells",
                    description: Text("Query returned no rows")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Display results using SwiftUI Table
                resultsTable
            }
        }
    }

    @ViewBuilder
    private var resultsTable: some View {
        if let columnNames = getColumnNames() {
            Table(of: PostgresMac.TableRow.self, selection: $selection) {
                TableColumnForEach(columnNames, id: \.self) { columnName in
                    TableColumn(columnName) { row in
                        Text(formatValue(row.values[columnName] ?? nil))
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    .width(min: Constants.ColumnWidth.tableColumnMin)
                }
            } rows: {
                ForEach(appState.queryResults) { row in
                    SwiftUI.TableRow(row)
                }
            }
        }
    }

    private func getColumnNames() -> [String]? {
        // Extract column names from the first row, maintaining order
        guard let firstRow = appState.queryResults.first else {
            return nil
        }
        // Sort column names alphabetically for consistent ordering
        return Array(firstRow.values.keys.sorted())
    }

    private func formatValue(_ value: String?) -> String {
        value ?? "NULL"
    }
}
