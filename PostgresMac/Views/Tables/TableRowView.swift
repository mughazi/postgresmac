//
//  TableRowView.swift
//  PostgresMac
//
//  Created by ghazi on 11/28/25.
//

import SwiftUI

struct TableRowView: View {
    let table: TableInfo

    var body: some View {
        NavigationLink(value: table.id) {
            VStack(alignment: .leading, spacing: 4) {
                Text(table.name)
                    .font(.headline)

                HStack {
                    if let rowCount = table.rowCount {
                        Text("\(Formatters.formatNumber(rowCount)) rows")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if let size = table.sizeInBytes {
                        Text("• \(Formatters.formatBytes(size))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
        }
    }
}
