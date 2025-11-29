//
//  ConnectionFormView.swift
//  PostgresMac
//
//  Created by ghazi on 11/28/25.
//

import SwiftUI
import SwiftData

struct ConnectionFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    
    @State private var name: String = ""
    @State private var host: String = "localhost"
    @State private var port: String = "5432"
    @State private var username: String = "postgres"
    @State private var password: String = ""
    @State private var database: String = "postgres"
    
    @State private var testResult: String?
    @State private var testResultColor: Color = .primary
    @State private var isConnecting: Bool = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Connection Details") {
                    TextField("Connection Name", text: $name)
                    TextField("Host", text: $host)
                    TextField("Port", text: $port)
                    TextField("Username", text: $username)
                    SecureField("Password", text: $password)
                    TextField("Database", text: $database)
                }
                
                if let testResult = testResult {
                    Text(testResult)
                        .foregroundColor(testResultColor)
                        .font(.caption)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("New Connection")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    HStack {
                        Button("Test") {
                            Task {
                                await testConnection()
                            }
                        }
                        .disabled(isConnecting)
                        
                        Button("Connect") {
                            Task {
                                await connect()
                            }
                        }
                        .disabled(isConnecting || name.isEmpty)
                    }
                }
            }
        }
        .frame(width: 500, height: 400)
    }
    
    private func testConnection() async {
        isConnecting = true
        testResult = nil
        
        guard let portInt = Int(port), portInt > 0 && portInt <= 65535 else {
            testResult = "Invalid port number"
            testResultColor = .red
            isConnecting = false
            return
        }
        
        do {
            let success = try await DatabaseService.testConnection(
                host: host.isEmpty ? "localhost" : host,
                port: portInt,
                username: username.isEmpty ? "postgres" : username,
                password: password,
                database: database.isEmpty ? "postgres" : database
            )
            
            if success {
                testResult = "Connection successful!"
                testResultColor = .green
            } else {
                testResult = "Connection failed"
                testResultColor = .red
            }
        } catch {
            testResult = error.localizedDescription
            testResultColor = .red
        }
        
        isConnecting = false
    }
    
    private func connect() async {
        isConnecting = true
        
        guard !name.isEmpty else {
            testResult = "Connection name is required"
            testResultColor = .red
            isConnecting = false
            return
        }
        
        guard let portInt = Int(port), portInt > 0 && portInt <= 65535 else {
            testResult = "Invalid port number"
            testResultColor = .red
            isConnecting = false
            return
        }
        
        do {
            // 1. Create ConnectionProfile
            let profile = ConnectionProfile(
                name: name,
                host: host.isEmpty ? "localhost" : host,
                port: portInt,
                username: username.isEmpty ? "postgres" : username,
                database: database.isEmpty ? "postgres" : database,
                lastUsed: Date()
            )
            
            // 2. Save password to Keychain
            if !password.isEmpty {
                try KeychainService.savePassword(password, for: profile.id)
            }
            
            // 3. Save profile to SwiftData
            modelContext.insert(profile)
            try modelContext.save()
            
            // 4. Connect to database
            let passwordToUse = password.isEmpty ? (try? KeychainService.getPassword(for: profile.id)) ?? "" : password
            
            try await appState.databaseService.connect(
                host: profile.host,
                port: profile.port,
                username: profile.username,
                password: passwordToUse,
                database: profile.database
            )
            
            // 5. Update app state
            appState.currentConnection = profile
            appState.isConnected = true
            appState.isShowingWelcomeScreen = false
            
            // 6. Load databases
            await loadDatabases()
            
            // 7. Dismiss and transition to MainSplitView
            dismiss()
            
        } catch {
            testResult = error.localizedDescription
            testResultColor = .red
        }
        
        isConnecting = false
    }
    
    private func loadDatabases() async {
        do {
            appState.databases = try await appState.databaseService.fetchDatabases()
        } catch {
            testResult = "Connected but failed to load databases: \(error.localizedDescription)"
            testResultColor = .orange
        }
    }
}
