import Foundation

// MARK: - Models

struct Role: Codable, Identifiable, Equatable {
    var id: String { name }
    let name: String
    let arn: String
}

struct PermissionSet: Codable, Identifiable, Equatable {
    var id: String { displayName }
    let displayName: String
    let permissionSetName: String
}

// MARK: - Generic JSON File Store

class JSONFileStore<T: Codable & Identifiable & Equatable> where T.ID == String {
    private let filename: String
    private(set) var items: [T] = []

    init(filename: String) {
        self.filename = filename
        load()
    }

    private var fileURL: URL? {
        guard let dir = Self.ensureAppSupportDirectory() else { return nil }
        return dir.appendingPathComponent(filename)
    }

    func load() {
        guard let url = fileURL, FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            items = try JSONDecoder().decode([T].self, from: data)
        } catch {
            print("Error loading \(filename): \(error)")
        }
    }

    func save() {
        guard let url = fileURL else { return }
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: url)
        } catch {
            print("Error saving \(filename): \(error)")
        }
    }

    func add(_ item: T) {
        guard !items.contains(where: { $0.id == item.id }) else { return }
        items.append(item)
        save()
    }

    func delete(id: String) {
        items.removeAll { $0.id == id }
        save()
    }

    static func ensureAppSupportDirectory() -> URL? {
        let fm = FileManager.default
        guard let appSupportURL = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }

        let dirURL = appSupportURL.appendingPathComponent("AWS CLI Gateway", isDirectory: true)

        do {
            if fm.fileExists(atPath: dirURL.path) {
                let attrs = try fm.attributesOfItem(atPath: dirURL.path)
                let ownerID = attrs[.ownerAccountID] as? Int ?? -1
                if ownerID != Int(getuid()) {
                    let tempDir = appSupportURL.appendingPathComponent("AWS CLI Gateway.migrate", isDirectory: true)
                    try? fm.removeItem(at: tempDir)
                    try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
                    let contents = try fm.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: nil)
                    for file in contents {
                        try? fm.copyItem(at: file, to: tempDir.appendingPathComponent(file.lastPathComponent))
                    }
                    try fm.removeItem(at: dirURL)
                    try fm.moveItem(at: tempDir, to: dirURL)
                }
            } else {
                try fm.createDirectory(at: dirURL, withIntermediateDirectories: true)
            }
        } catch {
            return nil
        }

        return dirURL
    }
}

// MARK: - Concrete Managers

class RoleManager: JSONFileStore<Role> {
    static let shared = RoleManager()
    private init() { super.init(filename: "role_manager.json") }

    func getRoles() -> [Role] { items }
    func addRole(_ role: Role) { add(role) }
    func deleteRole(named name: String) { delete(id: name) }
}

class PermissionSetManager: JSONFileStore<PermissionSet> {
    static let shared = PermissionSetManager()
    private init() { super.init(filename: "permission_set_manager.json") }

    func getPermissionSets() -> [PermissionSet] { items }
    func addPermissionSet(_ ps: PermissionSet) { add(ps) }
    func deletePermissionSet(named name: String) { delete(id: name) }
}
