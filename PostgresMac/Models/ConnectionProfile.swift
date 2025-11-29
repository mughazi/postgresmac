//
//  ConnectionProfile.swift
//  PostgresMac
//
//  Created by ghazi on 11/28/25.
//

import Foundation
import SwiftData

@Model
final class ConnectionProfile: Identifiable {
    var id: UUID
    var name: String
    var host: String
    var port: Int
    var username: String
    var database: String
    var lastUsed: Date?
    var isFavorite: Bool
    
    init(
        id: UUID = UUID(),
        name: String,
        host: String,
        port: Int = Constants.PostgreSQL.defaultPort,
        username: String,
        database: String = Constants.PostgreSQL.defaultDatabase,
        lastUsed: Date? = nil,
        isFavorite: Bool = false
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.username = username
        self.database = database
        self.lastUsed = lastUsed
        self.isFavorite = isFavorite
    }
}

extension ConnectionProfile {
    /// Creates a default localhost connection profile
    static func localhost() -> ConnectionProfile {
        ConnectionProfile(
            name: "localhost",
            host: "localhost",
            port: Constants.PostgreSQL.defaultPort,
            username: Constants.PostgreSQL.defaultUsername,
            database: Constants.PostgreSQL.defaultDatabase
        )
    }
}
