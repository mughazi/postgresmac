//
//  TableSchemaView.swift
//  PostgresMac
//
//  Created by ghazi on 11/28/25.
//

import SwiftUI

struct TableSchemaView: View {
    @Environment(AppState.self) private var appState
    
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Constants.Spacing.small) {
                ForEach(appState.columns) { column in
                    ColumnRowView(column: column)
                }
            }
            .padding(Constants.Spacing.medium)
        }
    }
}
