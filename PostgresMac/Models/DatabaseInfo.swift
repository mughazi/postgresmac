//
//  DatabaseInfo.swift
//  PostgresMac
//
//  Created by ghazi on 11/28/25.
//

import Foundation

struct DatabaseInfo: Identifiable, Hashable {
    let id: String
    let name: String
    var sizeInBytes: Int64?
    var tableCount: Int?
    
    init(name: String, sizeInBytes: Int64? = nil, tableCount: Int? = nil) {
        self.id = name
        self.name = name
        self.sizeInBytes = sizeInBytes
        self.tableCount = tableCount
    }
}
