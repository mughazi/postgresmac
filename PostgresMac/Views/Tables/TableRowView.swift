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
            HStack(spacing: 8) {
                Image(systemName: "tablecells")
                    .foregroundColor(.secondary)

                Text(table.name)
                    .font(.headline)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
        }
    }
}
