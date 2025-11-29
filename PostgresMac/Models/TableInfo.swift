//
//  TableInfo.swift
//  PostgresMac
//
//  Created by ghazi on 11/28/25.
//

import Foundation

struct TableInfo: Identifiable, Hashable {
    let id: String
    let name: String
    let schema: String
    var rowCount: Int64?
    var sizeInBytes: Int64?
    
    init(name: String, schema: String = "public", rowCount: Int64? = nil, sizeInBytes: Int64? = nil) {
        self.id = "\(schema).\(name)"
        self.name = name
        self.schema = schema
        self.rowCount = rowCount
        self.sizeInBytes = sizeInBytes
    }
}
