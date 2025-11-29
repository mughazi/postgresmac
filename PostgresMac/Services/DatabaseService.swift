//
//  DatabaseService.swift
//  PostgresMac
//
//  Created by ghazi on 11/28/25.
//

import Foundation
import PostgresNIO
import Logging

@MainActor
class DatabaseService {
    private var connection: PostgresConnection?
    private var eventLoopGroup: EventLoopGroup?
    private let logger = Logger(label: "com.postgresmac.database")
    
    var isConnected: Bool {
        connection != nil
    }
    
    init() {}
    
    deinit {
        // Don't create async tasks in deinit - it causes retain cycles
        // The connection and eventLoopGroup will be cleaned up when they go out of scope
        // If we need cleanup, it should be done explicitly before deallocation
    }
    
    /// Connect to PostgreSQL database
    func connect(
        host: String,
        port: Int,
        username: String,
        password: String,
        database: String
    ) async throws {
        print("🔌 [DatabaseService.connect] START - Connecting to \(database) at \(host):\(port) as \(username)")

        // Validate inputs
        guard !host.isEmpty else {
            print("❌ [DatabaseService.connect] Invalid host: \(host)")
            throw ConnectionError.invalidHost(host)
        }

        guard port > 0 && port <= 65535 else {
            print("❌ [DatabaseService.connect] Invalid port: \(port)")
            throw ConnectionError.invalidPort
        }

        // Disconnect existing connection if any
        print("🔄 [DatabaseService.connect] Disconnecting existing connection...")
        await disconnect()
        print("✅ [DatabaseService.connect] Disconnected")

        // Create event loop group
        print("⚙️  [DatabaseService.connect] Creating event loop group...")
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        self.eventLoopGroup = eventLoopGroup
        print("✅ [DatabaseService.connect] Event loop group created")

        // Create connection configuration
        let configuration = PostgresConnection.Configuration(
            host: host,
            port: port,
            username: username,
            password: password,
            database: database,
            tls: .disable // MVP: TLS disabled as per requirements
        )
        print("⚙️  [DatabaseService.connect] Configuration created for \(database)")

        do {
            // Connect to PostgreSQL
            print("🔌 [DatabaseService.connect] Attempting PostgreSQL connection...")
            let connection = try await PostgresConnection.connect(
                on: eventLoopGroup.next(),
                configuration: configuration,
                id: 1,
                logger: logger
            )

            self.connection = connection
            print("✅ [DatabaseService.connect] SUCCESS - Connected to \(database)")
        } catch {
            print("❌ [DatabaseService.connect] FAILED with error: \(error)")
            await disconnect()

            // Map PostgresNIO errors to ConnectionError
            if let postgresError = error as? PostgresError {
                print("❌ [DatabaseService.connect] PostgresError code: \(postgresError.code)")
                switch postgresError.code {
                case .invalidPassword, .invalidAuthorizationSpecification:
                    throw ConnectionError.authenticationFailed
                case .invalidCatalogName:
                    throw ConnectionError.databaseNotFound(database)
                default:
                    throw ConnectionError.unknownError(postgresError)
                }
            } else {
                // Check for network errors
                let nsError = error as NSError
                print("❌ [DatabaseService.connect] NSError domain: \(nsError.domain), code: \(nsError.code)")
                if nsError.domain == NSPOSIXErrorDomain {
                    switch nsError.code {
                    case 60: // ETIMEDOUT
                        throw ConnectionError.timeout
                    case 51, 50: // ENETUNREACH, EHOSTUNREACH
                        throw ConnectionError.networkUnreachable
                    default:
                        throw ConnectionError.unknownError(error)
                    }
                } else {
                    throw ConnectionError.unknownError(error)
                }
            }
        }
    }
    
    /// Disconnect from database
    func disconnect() async {
        if let connection = connection {
            try? await connection.close()
            self.connection = nil
        }
        
        if let eventLoopGroup = eventLoopGroup {
            try? await eventLoopGroup.shutdownGracefully()
            self.eventLoopGroup = nil
        }
    }
    
    /// Test connection without saving (static method - doesn't require instance)
    nonisolated static func testConnection(
        host: String,
        port: Int,
        username: String,
        password: String,
        database: String
    ) async throws -> Bool {
        // Run PostgresNIO operations off the main actor to avoid threading issues
        return try await Task.detached {
            // Create temporary connection for testing
            let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
            let testLogger = Logger(label: "com.postgresmac.test")
            
            var testConnection: PostgresConnection?
            
            // Cleanup helper
            func cleanup() async {
                if let connection = testConnection {
                    try? await connection.close()
                    testConnection = nil
                }
                try? await eventLoopGroup.shutdownGracefully()
            }
            
            let configuration = PostgresConnection.Configuration(
                host: host,
                port: port,
                username: username,
                password: password,
                database: database,
                tls: .disable
            )
            
            do {
                testConnection = try await PostgresConnection.connect(
                    on: eventLoopGroup.next(),
                    configuration: configuration,
                    id: 1,
                    logger: testLogger
                )
                
                // Test successful - close connection and cleanup
                try await testConnection?.close()
                testConnection = nil
                try await eventLoopGroup.shutdownGracefully()
                return true
            } catch {
                // Error occurred - ensure cleanup happens
                await cleanup()
                
                // Map PostgresNIO errors to ConnectionError for better error messages
                if let postgresError = error as? PostgresError {
                    switch postgresError.code {
                    case .invalidPassword, .invalidAuthorizationSpecification:
                        throw ConnectionError.authenticationFailed
                    case .invalidCatalogName:
                        throw ConnectionError.databaseNotFound(database)
                    default:
                        throw ConnectionError.unknownError(postgresError)
                    }
                } else {
                    // Check for network errors
                    let nsError = error as NSError
                    if nsError.domain == NSPOSIXErrorDomain {
                        switch nsError.code {
                        case 1: // EPERM - Operation not permitted (sandbox issue)
                            throw ConnectionError.networkUnreachable
                        case 60: // ETIMEDOUT
                            throw ConnectionError.timeout
                        case 51, 50: // ENETUNREACH, EHOSTUNREACH
                            throw ConnectionError.networkUnreachable
                        case 61: // ECONNREFUSED - Connection refused
                            throw ConnectionError.networkUnreachable
                        default:
                            throw ConnectionError.unknownError(error)
                        }
                    } else {
                        throw ConnectionError.unknownError(error)
                    }
                }
            }
        }.value
    }
    
    /// Fetch list of databases
    func fetchDatabases() async throws -> [DatabaseInfo] {
        guard let connection = connection else {
            throw ConnectionError.notConnected
        }
        
        let query: PostgresQuery = """
            SELECT datname, pg_database_size(datname) as size
            FROM pg_database
            WHERE datistemplate = false
            ORDER BY datname;
            """
        
        let rows = try await connection.query(query, logger: logger)
        
        var databases: [DatabaseInfo] = []
        for try await row in rows {
            let randomAccess = row.makeRandomAccess()
            let name = try randomAccess[0].decode(String.self)
            let size = try randomAccess[1].decode(Int64?.self)
            databases.append(DatabaseInfo(name: name, sizeInBytes: size))
        }
        
        return databases
    }
    
    /// Fetch list of tables in a database
    func fetchTables(database: String) async throws -> [TableInfo] {
        print("📊 [DatabaseService.fetchTables] START for database: \(database)")

        guard let connection = connection else {
            print("❌ [DatabaseService.fetchTables] ERROR: Not connected")
            throw ConnectionError.notConnected
        }
        print("✅ [DatabaseService.fetchTables] Connection exists")

        let query: PostgresQuery = """
            SELECT
                table_name,
                table_schema,
                (SELECT reltuples::bigint FROM pg_class WHERE relname = table_name) as row_count,
                pg_total_relation_size(quote_ident(table_schema)||'.'||quote_ident(table_name)) as size
            FROM information_schema.tables
            WHERE table_schema NOT IN ('pg_catalog', 'information_schema')
            AND table_type = 'BASE TABLE'
            ORDER BY table_schema, table_name;
            """
        print("📝 [DatabaseService.fetchTables] Executing query...")

        let rows = try await connection.query(query, logger: logger)
        print("✅ [DatabaseService.fetchTables] Query executed, processing rows...")

        var tables: [TableInfo] = []
        for try await row in rows {
            let randomAccess = row.makeRandomAccess()
            let name = try randomAccess[0].decode(String.self)
            let schema = try randomAccess[1].decode(String.self)
            let rowCount = try randomAccess[2].decode(Int64?.self)
            let size = try randomAccess[3].decode(Int64?.self)
            tables.append(TableInfo(name: name, schema: schema, rowCount: rowCount, sizeInBytes: size))
            print("   ➕ Found table: \(schema).\(name)")
        }

        print("✅ [DatabaseService.fetchTables] SUCCESS - Fetched \(tables.count) tables")
        return tables
    }
    
    /// Fetch column information for a table
    func fetchColumns(schema: String, table: String) async throws -> [ColumnInfo] {
        print("📋 [DatabaseService.fetchColumns] START for \(schema).\(table)")

        guard let connection = connection else {
            print("❌ [DatabaseService.fetchColumns] ERROR: Not connected")
            throw ConnectionError.notConnected
        }

        // Fetch column information
        // Escape single quotes for string literals in SQL
        let escapedSchema = schema.replacingOccurrences(of: "'", with: "''")
        let escapedTable = table.replacingOccurrences(of: "'", with: "''")

        let columnQuerySQL = """
            SELECT
                column_name,
                data_type,
                character_maximum_length,
                is_nullable,
                column_default
            FROM information_schema.columns
            WHERE table_schema = '\(escapedSchema)' AND table_name = '\(escapedTable)'
            ORDER BY ordinal_position;
            """

        print("📝 [DatabaseService.fetchColumns] Query: \(columnQuerySQL)")
        let columnQuery = PostgresQuery(unsafeSQL: columnQuerySQL)

        var columns: [ColumnInfo] = []

        do {
            let columnRows = try await connection.query(columnQuery, logger: logger)
            print("✅ [DatabaseService.fetchColumns] Column query executed successfully")

            for try await row in columnRows {
                let randomAccess = row.makeRandomAccess()
                let name = try randomAccess[0].decode(String.self)
                var dataType = try randomAccess[1].decode(String.self)
                let maxLength = try randomAccess[2].decode(Int?.self)
                let isNullable = try randomAccess[3].decode(String.self) == "YES"
                let defaultValue = try randomAccess[4].decode(String?.self)

                // Format data type with length if applicable
                if let maxLength = maxLength, dataType.contains("character") {
                    dataType = "\(dataType)(\(maxLength))"
                }

                columns.append(ColumnInfo(
                    name: name,
                    dataType: dataType,
                    isNullable: isNullable,
                    defaultValue: defaultValue
                ))
            }
            print("✅ [DatabaseService.fetchColumns] Processed \(columns.count) columns")
        } catch {
            print("❌ [DatabaseService.fetchColumns] ERROR in column query: \(error)")
            print("❌ [DatabaseService.fetchColumns] Error details: \(String(reflecting: error))")
            throw error
        }
        
        // Fetch primary key constraints
        let pkQuerySQL = """
            SELECT column_name
            FROM information_schema.table_constraints tc
            JOIN information_schema.constraint_column_usage ccu
                ON tc.constraint_name = ccu.constraint_name
            WHERE tc.table_schema = '\(escapedSchema)'
            AND tc.table_name = '\(escapedTable)'
            AND tc.constraint_type = 'PRIMARY KEY';
            """

        let pkQuery = PostgresQuery(unsafeSQL: pkQuerySQL)
        let pkRows = try await connection.query(pkQuery, logger: logger)
        
        var pkColumns: Set<String> = []
        for try await row in pkRows {
            let randomAccess = row.makeRandomAccess()
            let columnName = try randomAccess[0].decode(String.self)
            pkColumns.insert(columnName)
        }
        
        // Fetch unique constraints
        let uniqueQuerySQL = """
            SELECT column_name
            FROM information_schema.table_constraints tc
            JOIN information_schema.constraint_column_usage ccu
                ON tc.constraint_name = ccu.constraint_name
            WHERE tc.table_schema = '\(escapedSchema)'
            AND tc.table_name = '\(escapedTable)'
            AND tc.constraint_type = 'UNIQUE';
            """

        let uniqueQuery = PostgresQuery(unsafeSQL: uniqueQuerySQL)
        let uniqueRows = try await connection.query(uniqueQuery, logger: logger)
        
        var uniqueColumns: Set<String> = []
        for try await row in uniqueRows {
            let randomAccess = row.makeRandomAccess()
            let columnName = try randomAccess[0].decode(String.self)
            uniqueColumns.insert(columnName)
        }
        
        // Fetch foreign key constraints
        let fkQuerySQL = """
            SELECT column_name
            FROM information_schema.table_constraints tc
            JOIN information_schema.constraint_column_usage ccu
                ON tc.constraint_name = ccu.constraint_name
            WHERE tc.table_schema = '\(escapedSchema)'
            AND tc.table_name = '\(escapedTable)'
            AND tc.constraint_type = 'FOREIGN KEY';
            """

        let fkQuery = PostgresQuery(unsafeSQL: fkQuerySQL)
        let fkRows = try await connection.query(fkQuery, logger: logger)
        
        var fkColumns: Set<String> = []
        for try await row in fkRows {
            let randomAccess = row.makeRandomAccess()
            let columnName = try randomAccess[0].decode(String.self)
            fkColumns.insert(columnName)
        }
        
        // Update columns with constraint information
        for index in columns.indices {
            columns[index].isPrimaryKey = pkColumns.contains(columns[index].name)
            columns[index].isUnique = uniqueColumns.contains(columns[index].name)
            columns[index].isForeignKey = fkColumns.contains(columns[index].name)
        }
        
        return columns
    }
    
    /// Fetch table data with pagination
    func fetchTableData(
        schema: String,
        table: String,
        offset: Int,
        limit: Int
    ) async throws -> [TableRow] {
        print("📊 [DatabaseService.fetchTableData] START for \(schema).\(table), offset=\(offset), limit=\(limit)")

        guard let connection = connection else {
            print("❌ [DatabaseService.fetchTableData] ERROR: Not connected")
            throw ConnectionError.notConnected
        }

        // Build query with properly escaped identifiers (using quote_ident would be better but requires a function call)
        // For now, use simple escaping for schema and table names
        let escapedSchema = schema.replacingOccurrences(of: "\"", with: "\"\"")
        let escapedTable = table.replacingOccurrences(of: "\"", with: "\"\"")

        // Note: We can't use PostgresNIO's parameter binding for table/schema names (identifiers)
        // They must be part of the SQL string, but LIMIT/OFFSET can be bound
        let querySQL = """
            SELECT * FROM "\(escapedSchema)"."\(escapedTable)"
            LIMIT \(limit) OFFSET \(offset);
            """

        print("📝 [DatabaseService.fetchTableData] Query: \(querySQL)")
        let query = PostgresQuery(unsafeSQL: querySQL)

        let rows: PostgresRowSequence
        do {
            rows = try await connection.query(query, logger: logger)
            print("✅ [DatabaseService.fetchTableData] Query executed successfully")
        } catch {
            print("❌ [DatabaseService.fetchTableData] ERROR executing query: \(error)")
            print("❌ [DatabaseService.fetchTableData] Error details: \(String(reflecting: error))")
            throw error
        }
        
        var tableRows: [TableRow] = []
        for try await row in rows {
            var values: [String: String?] = [:]
            
            // Get all column names and values
            let randomAccess = row.makeRandomAccess()
            // Get column metadata - need to query column names separately or use a different approach
            // For SELECT *, column order matches table column order
            // We'll need to fetch column names separately or use a different query approach
            // For now, use a workaround: fetch column names from information_schema first
            // But for simplicity in MVP, let's use column indices and fetch names separately if needed
            
            // Try to decode all columns - PostgresNIO should provide column metadata
            // Use a simpler approach: try to decode as string for all columns
            for index in 0..<randomAccess.count {
                let columnName = "col_\(index)" // Temporary - will need actual column names
                let value: String?
                
                // Try to decode as string (PostgresNIO will handle type conversion)
                do {
                    value = try randomAccess[index].decode(String.self)
                } catch {
                    // Try other types if string fails
                    if let intValue = try? randomAccess[index].decode(Int64.self) {
                        value = String(intValue)
                    } else if let doubleValue = try? randomAccess[index].decode(Double.self) {
                        value = String(doubleValue)
                    } else if let boolValue = try? randomAccess[index].decode(Bool.self) {
                        value = String(boolValue)
                    } else {
                        value = nil // NULL or unsupported type
                    }
                }
                
                values[columnName] = value
            }
            
            tableRows.append(TableRow(values: values))
        }
        
        return tableRows
    }
    
    /// Get total row count for a table
    func getRowCount(schema: String, table: String) async throws -> Int64 {
        guard let connection = connection else {
            throw ConnectionError.notConnected
        }

        // Escape schema and table names
        let escapedSchema = schema.replacingOccurrences(of: "\"", with: "\"\"")
        let escapedTable = table.replacingOccurrences(of: "\"", with: "\"\"")
        let query: PostgresQuery = """
            SELECT COUNT(*) as count FROM "\(escapedSchema)"."\(escapedTable)";
            """

        let rows = try await connection.query(query, logger: logger)

        for try await row in rows {
            let randomAccess = row.makeRandomAccess()
            return try randomAccess[0].decode(Int64.self)
        }

        return 0
    }

    /// Execute arbitrary SQL query and return results
    func executeQuery(_ sql: String) async throws -> [TableRow] {
        print("🔍 [DatabaseService.executeQuery] START")
        print("📝 [DatabaseService.executeQuery] Query: \(sql)")

        guard let connection = connection else {
            print("❌ [DatabaseService.executeQuery] ERROR: Not connected")
            throw ConnectionError.notConnected
        }

        // Create query from raw SQL
        let query = PostgresQuery(unsafeSQL: sql)

        let rows: PostgresRowSequence
        do {
            rows = try await connection.query(query, logger: logger)
            print("✅ [DatabaseService.executeQuery] Query executed successfully")
        } catch {
            print("❌ [DatabaseService.executeQuery] ERROR executing query: \(error)")
            print("❌ [DatabaseService.executeQuery] Error details: \(String(reflecting: error))")
            throw error
        }

        var tableRows: [TableRow] = []
        for try await row in rows {
            var values: [String: String?] = [:]
            let randomAccess = row.makeRandomAccess()

            // Extract all columns
            for index in 0..<randomAccess.count {
                let columnName = "col_\(index)" // Using index-based names for now
                let value: String?

                // Try to decode as string first (PostgresNIO will handle type conversion)
                do {
                    value = try randomAccess[index].decode(String.self)
                } catch {
                    // Try other types if string fails
                    if let intValue = try? randomAccess[index].decode(Int64.self) {
                        value = String(intValue)
                    } else if let doubleValue = try? randomAccess[index].decode(Double.self) {
                        value = String(doubleValue)
                    } else if let boolValue = try? randomAccess[index].decode(Bool.self) {
                        value = String(boolValue)
                    } else {
                        value = nil // NULL or unsupported type
                    }
                }

                values[columnName] = value
            }

            tableRows.append(TableRow(values: values))
        }

        print("✅ [DatabaseService.executeQuery] SUCCESS - Returned \(tableRows.count) rows")
        return tableRows
    }
}
