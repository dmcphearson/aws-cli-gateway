import Foundation

// Role Manager
struct Role: Codable, Identifiable, Equatable {
    var id: String { name }
    let name: String
    let arn: String
}

class RoleManager {
    static let shared = RoleManager()
    private let fileManager = FileManager.default

    private var roles: [Role] = []

    private var configURL: URL? {
        guard let dir = Self.ensureAppSupportDirectory() else { return nil }
        return dir.appendingPathComponent("role_manager.json")
    }

    static func ensureAppSupportDirectory() -> URL? {
        let fileManager = FileManager.default
        guard let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }

        let dirURL = appSupportURL.appendingPathComponent("AWS CLI Gateway", isDirectory: true)

        do {
            if fileManager.fileExists(atPath: dirURL.path) {
                let attrs = try fileManager.attributesOfItem(atPath: dirURL.path)
                let ownerID = attrs[.ownerAccountID] as? Int ?? -1
                if ownerID != Int(getuid()) {
                    // Directory owned by wrong user (e.g. root) — migrate contents
                    let tempDir = appSupportURL.appendingPathComponent("AWS CLI Gateway.migrate", isDirectory: true)
                    try? fileManager.removeItem(at: tempDir)
                    try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
                    let contents = try fileManager.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: nil)
                    for file in contents {
                        try? fileManager.copyItem(at: file, to: tempDir.appendingPathComponent(file.lastPathComponent))
                    }
                    try fileManager.removeItem(at: dirURL)
                    try fileManager.moveItem(at: tempDir, to: dirURL)
                }
            } else {
                try fileManager.createDirectory(at: dirURL, withIntermediateDirectories: true)
            }
        } catch {
            return nil
        }

        return dirURL
    }

    init() {
        loadRoles()

        // If no roles exist, populate with default roles
        if roles.isEmpty {
            populateDefaultRoles()
        }
    }

    func loadRoles() {
        guard let configURL = configURL,
              fileManager.fileExists(atPath: configURL.path) else {
            return
        }

        do {
            let data = try Data(contentsOf: configURL)
            roles = try JSONDecoder().decode([Role].self, from: data)
        } catch {
            print("Error loading roles: \(error)")
        }
    }

    func saveRoles() {
        guard let configURL = configURL else { return }

        do {
            let data = try JSONEncoder().encode(roles)
            try data.write(to: configURL)
        } catch {
            print("Error saving roles: \(error)")
        }
    }

    func getRoles() -> [Role] {
        return roles
    }

    func addRole(_ role: Role) {
        if !roles.contains(where: { $0.name == role.name }) {
            roles.append(role)
            saveRoles()
        }
    }

    func deleteRole(named name: String) {
        roles.removeAll(where: { $0.name == name })
        saveRoles()
        
    }

    private func populateDefaultRoles() {
        roles = []
        saveRoles()
    }
}

// Permission Set Manager
struct PermissionSet: Codable, Identifiable, Equatable {
    var id: String { displayName }
    let displayName: String
    let permissionSetName: String
}

class PermissionSetManager {
    static let shared = PermissionSetManager()
    private let fileManager = FileManager.default

    private var permissionSets: [PermissionSet] = []

    private var configURL: URL? {
        guard let dir = RoleManager.ensureAppSupportDirectory() else { return nil }
        return dir.appendingPathComponent("permission_set_manager.json")
    }

    init() {
        loadPermissionSets()

        // If no permission sets exist, populate with default ones
        if permissionSets.isEmpty {
            populateDefaultPermissionSets()
        }
    }

    func loadPermissionSets() {
        guard let configURL = configURL,
              fileManager.fileExists(atPath: configURL.path) else {
            return
        }

        do {
            let data = try Data(contentsOf: configURL)
            permissionSets = try JSONDecoder().decode([PermissionSet].self, from: data)
        } catch {
            print("Error loading permission sets: \(error)")
        }
    }

    func savePermissionSets() {
        guard let configURL = configURL else { return }

        do {
            let data = try JSONEncoder().encode(permissionSets)
            try data.write(to: configURL)
        } catch {
            print("Error saving permission sets: \(error)")
        }
    }

    func getPermissionSets() -> [PermissionSet] {
        return permissionSets
    }

    func addPermissionSet(_ permissionSet: PermissionSet) {
        if !permissionSets.contains(where: { $0.displayName == permissionSet.displayName }) {
            permissionSets.append(permissionSet)
            savePermissionSets()
        }
    }

    func deletePermissionSet(named name: String) {
        permissionSets.removeAll(where: { $0.displayName == name })
        savePermissionSets()

    }

    private func populateDefaultPermissionSets() {
        // Start with an empty array - no default permission sets
        permissionSets = []
        savePermissionSets()
    }

}
