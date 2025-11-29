//
//  QueryResultsView.swift
//  PostgresMac
//
//  Created by Claude on 11/29/25.
//

import SwiftUI

struct QueryResultsView: View {
    @Environment(AppState.self) private var appState

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
                // Display results in table format
                ScrollView([.horizontal, .vertical]) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        queryResultsHeader
                        queryResultsRows
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var queryResultsHeader: some View {
        if let firstRow = appState.queryResults.first {
            let columnNames = Array(firstRow.values.keys.sorted())
            HStack(spacing: 0) {
                ForEach(columnNames, id: \.self) { columnName in
                    Text(columnName)
                        .font(.headline)
                        .frame(minWidth: Constants.ColumnWidth.tableColumnMin, alignment: .leading)
                        .padding(8)
                        .background(Color(NSColor.controlBackgroundColor))
                        .border(Color(NSColor.separatorColor), width: 0.5)
                }
            }
        }
    }

    @ViewBuilder
    private var queryResultsRows: some View {
        ForEach(Array(appState.queryResults.enumerated()), id: \.element.id) { index, row in
            let columnNames = Array(row.values.keys.sorted())
            HStack(spacing: 0) {
                ForEach(columnNames, id: \.self) { columnName in
                    let value = row.values[columnName] ?? nil
                    Text(formatValue(value))
                        .font(.system(.body, design: .monospaced))
                        .frame(minWidth: Constants.ColumnWidth.tableColumnMin, alignment: .leading)
                        .padding(8)
                        .background(index % 2 == 0 ? Color.clear : Color(NSColor.controlBackgroundColor).opacity(0.5))
                        .border(Color(NSColor.separatorColor), width: 0.5)
                }
            }
        }
    }

    private func formatValue(_ value: String?) -> String {
        value ?? "NULL"
    }
}
