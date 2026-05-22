import SwiftUI
import AppKit

struct AddProfileView: View {
    let onClose: () -> Void
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.blue.gradient)

                Text("Add AWS Profile")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            TabView(selection: $selectedTab) {
                SSOProfileTab(onClose: onClose)
                    .tabItem {
                        Label("SSO Profile", systemImage: "person.badge.key")
                    }
                    .tag(0)

                IAMRoleTab(onClose: onClose)
                    .tabItem {
                        Label("IAM Role", systemImage: "key")
                    }
                    .tag(1)
            }
            .tabViewStyle(.automatic)
        }
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 0))
    }
}

// MARK: - Native Dropdown Component

struct NativePopUpButton: NSViewRepresentable {
    @Binding var selection: String
    var options: [String]
    var onDelete: ((String) -> Void)?
    var onAddNew: (() -> Void)?
    var addNewText: String = "Add new..."

    func makeNSView(context: Context) -> NSView {
        let container = NSView()

        let popUpButton = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 220, height: 26), pullsDown: false)
        popUpButton.target = context.coordinator
        popUpButton.action = #selector(Coordinator.selectionChanged(_:))
        popUpButton.bezelStyle = .texturedSquare
        popUpButton.font = NSFont.systemFont(ofSize: 13)
        popUpButton.tag = 100
        container.addSubview(popUpButton)

        if onDelete != nil {
            let deleteButton = NSButton(frame: NSRect(x: 225, y: 0, width: 25, height: 26))
            deleteButton.bezelStyle = .texturedSquare
            deleteButton.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "Delete")
            deleteButton.isBordered = true
            deleteButton.target = context.coordinator
            deleteButton.action = #selector(Coordinator.deleteSelectedOption(_:))
            deleteButton.tag = 101
            deleteButton.isHidden = true
            container.addSubview(deleteButton)
        }

        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        guard let popUpButton = container.viewWithTag(100) as? NSPopUpButton else { return }
        let deleteButton = container.viewWithTag(101) as? NSButton

        popUpButton.removeAllItems()
        for option in options {
            popUpButton.addItem(withTitle: option)
        }

        if onAddNew != nil {
            popUpButton.menu?.addItem(NSMenuItem.separator())
            let addItem = NSMenuItem(title: addNewText, action: #selector(Coordinator.addNewOption(_:)), keyEquivalent: "")
            addItem.target = context.coordinator
            popUpButton.menu?.addItem(addItem)
        }

        if let index = options.firstIndex(of: selection) {
            popUpButton.selectItem(at: index)
            deleteButton?.isHidden = (selection == "-----" || onDelete == nil)
        } else if !options.isEmpty {
            popUpButton.selectItem(at: 0)
            deleteButton?.isHidden = true
            if !options.contains(selection) {
                DispatchQueue.main.async { selection = options[0] }
            }
        }

        context.coordinator.options = options
        context.coordinator.container = container
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject {
        var parent: NativePopUpButton
        var options: [String] = []
        weak var container: NSView?

        init(_ parent: NativePopUpButton) {
            self.parent = parent
            self.options = parent.options
        }

        @objc func selectionChanged(_ sender: NSPopUpButton) {
            let deleteButton = container?.viewWithTag(101) as? NSButton
            guard sender.indexOfSelectedItem >= 0 else { return }
            let selectedOption = sender.titleOfSelectedItem ?? ""
            DispatchQueue.main.async {
                self.parent.selection = selectedOption
                deleteButton?.isHidden = (selectedOption == "-----" || self.parent.onDelete == nil)
            }
        }

        @objc func deleteSelectedOption(_ sender: NSButton) {
            guard let popUpButton = container?.viewWithTag(100) as? NSPopUpButton,
                  let selectedOption = popUpButton.titleOfSelectedItem,
                  selectedOption != "-----" else { return }

            let alert = NSAlert()
            alert.messageText = "Delete Item"
            alert.informativeText = "Are you sure you want to delete \(selectedOption)?"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Delete")
            alert.addButton(withTitle: "Cancel")

            if let window = container?.window {
                alert.beginSheetModal(for: window) { response in
                    if response == .alertFirstButtonReturn {
                        DispatchQueue.main.async { self.parent.onDelete?(selectedOption) }
                    }
                }
            } else {
                if alert.runModal() == .alertFirstButtonReturn {
                    DispatchQueue.main.async { self.parent.onDelete?(selectedOption) }
                }
            }
        }

        @objc func addNewOption(_ sender: NSMenuItem) {
            DispatchQueue.main.async { self.parent.onAddNew?() }
        }
    }
}

// MARK: - SSO Profile Tab

struct SSOProfileTab: View {
    let onClose: () -> Void

    @State private var region = "-----"
    @State private var startUrl = ""
    @State private var accountId = ""
    @State private var selectedPermissionSet = "-----"
    @State private var output = "json"
    @State private var errorMessage: String?
    @State private var showAddPermissionSetSheet = false
    @State private var permissionSets: [PermissionSet] = []
    @State private var permissionSetToDelete: String?
    @State private var showDeleteConfirmation = false
    @FocusState private var focusedField: Field?

    enum Field { case startUrl, accountId }

    private let regions = SSOProfile.commonRegions

    var body: some View {
        VStack(spacing: 16) {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                GridRow {
                    Text("Permission Set")
                        .gridColumnAlignment(.trailing)
                        .foregroundStyle(.secondary)
                        .frame(width: 100, alignment: .trailing)

                    NativePopUpButton(
                        selection: $selectedPermissionSet,
                        options: ["-----"] + permissionSets.map { $0.displayName },
                        onDelete: { itemToDelete in
                            if itemToDelete != "-----" {
                                permissionSetToDelete = itemToDelete
                                showDeleteConfirmation = true
                            }
                        },
                        onAddNew: { showAddPermissionSetSheet = true },
                        addNewText: "Add new permission set..."
                    )
                    .frame(width: 300, height: 26)
                }

                GridRow {
                    Text("Region")
                        .gridColumnAlignment(.trailing)
                        .foregroundStyle(.secondary)
                        .frame(width: 100, alignment: .trailing)

                    NativePopUpButton(selection: $region, options: regions)
                        .frame(width: 300, height: 26)
                }

                GridRow {
                    Text("Start URL")
                        .gridColumnAlignment(.trailing)
                        .foregroundStyle(.secondary)
                        .frame(width: 100, alignment: .trailing)

                    TextField("https://example.awsapps.com/start", text: $startUrl)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .startUrl)
                        .frame(width: 300)
                }

                GridRow {
                    Text("Account ID")
                        .gridColumnAlignment(.trailing)
                        .foregroundStyle(.secondary)
                        .frame(width: 100, alignment: .trailing)

                    TextField("123456789012", text: $accountId)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .accountId)
                        .frame(width: 300)
                }

                GridRow {
                    Text("Output")
                        .gridColumnAlignment(.trailing)
                        .foregroundStyle(.secondary)
                        .frame(width: 100, alignment: .trailing)

                    NativePopUpButton(selection: $output, options: Constants.AWS.outputFormats)
                        .frame(width: 300, height: 26)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            if let errorMessage = errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.caption)
                    Spacer()
                }
                .padding(.horizontal, 20)
            }

            Spacer()

            HStack(spacing: 12) {
                Button("Cancel") { onClose() }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Create Profile") { saveProfile() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isValid)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .onAppear { loadPermissionSets() }
        .sheet(isPresented: $showAddPermissionSetSheet, onDismiss: { loadPermissionSets() }) {
            AddPermissionSetView { loadPermissionSets() }
        }
        .alert(isPresented: $showDeleteConfirmation) {
            Alert(
                title: Text("Delete Permission Set"),
                message: Text("Are you sure you want to delete this permission set?"),
                primaryButton: .destructive(Text("Delete")) {
                    if let setToDelete = permissionSetToDelete {
                        PermissionSetManager.shared.deletePermissionSet(named: setToDelete)
                        loadPermissionSets()
                        if selectedPermissionSet == setToDelete { selectedPermissionSet = "-----" }
                    }
                },
                secondaryButton: .cancel()
            )
        }
    }

    private var isValid: Bool {
        !startUrl.isEmpty && !accountId.isEmpty && region != "-----" && selectedPermissionSet != "-----"
    }

    private func loadPermissionSets() {
        permissionSets = PermissionSetManager.shared.getPermissionSets()
    }

    private func saveProfile() {
        guard let permissionSet = permissionSets.first(where: { $0.displayName == selectedPermissionSet }) else {
            errorMessage = "Invalid permission set selection"
            return
        }

        let profile = SSOProfile(
            name: permissionSet.displayName,
            startUrl: startUrl,
            region: region,
            accountId: accountId,
            roleName: permissionSet.permissionSetName,
            output: output
        )

        if !profile.validate() {
            errorMessage = Constants.ErrorMessages.profileValidation
            return
        }

        do {
            try ConfigManager.shared.saveProfile(profile)
            NotificationCenter.default.post(
                name: Notification.Name(Constants.Notifications.profilesUpdated),
                object: nil
            )
            onClose()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - IAM Role Tab

struct IAMRoleTab: View {
    let onClose: () -> Void

    @State private var sourceProfile = "-----"
    @State private var selectedRole = "-----"
    @State private var output = "json"
    @State private var errorMessage: String?
    @State private var showAddRoleSheet = false
    @State private var roleToDelete: String?
    @State private var showDeleteConfirmation = false
    @State private var availableProfiles: [String] = []
    @State private var availableRoles: [Role] = []

    var body: some View {
        VStack(spacing: 16) {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                GridRow {
                    Text("Assume Role")
                        .gridColumnAlignment(.trailing)
                        .foregroundStyle(.secondary)
                        .frame(width: 100, alignment: .trailing)

                    NativePopUpButton(
                        selection: $selectedRole,
                        options: ["-----"] + availableRoles.map { $0.name },
                        onDelete: { itemToDelete in
                            if itemToDelete != "-----" {
                                roleToDelete = itemToDelete
                                showDeleteConfirmation = true
                            }
                        },
                        onAddNew: { showAddRoleSheet = true },
                        addNewText: "Add new role..."
                    )
                    .frame(width: 300, height: 26)
                }

                GridRow {
                    Text("Source Profile")
                        .gridColumnAlignment(.trailing)
                        .foregroundStyle(.secondary)
                        .frame(width: 100, alignment: .trailing)

                    NativePopUpButton(selection: $sourceProfile, options: availableProfiles)
                        .frame(width: 300, height: 26)
                }

                GridRow {
                    Text("Output")
                        .gridColumnAlignment(.trailing)
                        .foregroundStyle(.secondary)
                        .frame(width: 100, alignment: .trailing)

                    NativePopUpButton(selection: $output, options: Constants.AWS.outputFormats)
                        .frame(width: 300, height: 26)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            if let errorMessage = errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.caption)
                    Spacer()
                }
                .padding(.horizontal, 20)
            }

            Spacer()

            HStack(spacing: 12) {
                Button("Cancel") { onClose() }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Create Profile") { saveIAMProfile() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isValid)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .onAppear {
            loadAvailableProfiles()
            loadAvailableRoles()
        }
        .sheet(isPresented: $showAddRoleSheet, onDismiss: { loadAvailableRoles() }) {
            AddRoleView { loadAvailableRoles() }
        }
        .alert(isPresented: $showDeleteConfirmation) {
            Alert(
                title: Text("Delete Role"),
                message: Text("Are you sure you want to delete this role?"),
                primaryButton: .destructive(Text("Delete")) {
                    if let roleToDelete = roleToDelete {
                        RoleManager.shared.deleteRole(named: roleToDelete)
                        loadAvailableRoles()
                        if selectedRole == roleToDelete { selectedRole = "-----" }
                    }
                },
                secondaryButton: .cancel()
            )
        }
    }

    private var isValid: Bool {
        sourceProfile != "-----" && selectedRole != "-----"
    }

    private func loadAvailableProfiles() {
        let profiles = ConfigManager.shared.getProfiles().compactMap { $0 as? SSOProfile }
        availableProfiles = ["-----"] + profiles.map { $0.name }
    }

    private func loadAvailableRoles() {
        availableRoles = RoleManager.shared.getRoles()
    }

    private func saveIAMProfile() {
        guard let role = availableRoles.first(where: { $0.name == selectedRole }) else {
            errorMessage = "Invalid role selection"
            return
        }

        guard let sourceProfileObject = ConfigManager.shared.getProfiles()
            .first(where: { $0.name == sourceProfile }) as? SSOProfile else {
            errorMessage = "Could not find the source profile"
            return
        }

        let iamProfile = IAMProfile(
            name: selectedRole,
            sourceProfile: sourceProfile,
            ssoSession: sourceProfile,
            roleArn: role.arn,
            region: sourceProfileObject.region,
            output: output
        )

        do {
            try ConfigManager.shared.saveIAMProfile(iamProfile)
            NotificationCenter.default.post(
                name: Notification.Name(Constants.Notifications.profilesUpdated),
                object: nil
            )
            onClose()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Add Role View

struct AddRoleView: View {
    let onDismiss: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var roleName = ""
    @State private var roleArn = ""
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

    enum Field { case roleName, roleArn }

    var body: some View {
        VStack(spacing: 24) {
            Text("Add New Role")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(spacing: 16) {
                TextField("Role Name", text: $roleName)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .roleName)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            focusedField = .roleName
                        }
                    }

                TextField("Role ARN", text: $roleArn)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .roleArn)

                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
            .padding(20)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))

            HStack(spacing: 12) {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Save") { saveRole() }
                    .buttonStyle(.borderedProminent)
                    .disabled(roleName.isEmpty || roleArn.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 450, height: 300)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func saveRole() {
        RoleManager.shared.addRole(Role(name: roleName, arn: roleArn))
        onDismiss()
        dismiss()
    }
}

// MARK: - Add Permission Set View

struct AddPermissionSetView: View {
    let onDismiss: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var displayName = ""
    @State private var permissionSetName = ""
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

    enum Field { case displayName, permissionSetName }

    var body: some View {
        VStack(spacing: 24) {
            Text("Add Permission Set")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(spacing: 16) {
                TextField("Display Name", text: $displayName)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .displayName)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            focusedField = .displayName
                        }
                    }

                TextField("Permission Set Name", text: $permissionSetName)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .permissionSetName)

                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
            .padding(20)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))

            HStack(spacing: 12) {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Save") { savePermissionSet() }
                    .buttonStyle(.borderedProminent)
                    .disabled(displayName.isEmpty || permissionSetName.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 450, height: 300)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func savePermissionSet() {
        PermissionSetManager.shared.addPermissionSet(PermissionSet(displayName: displayName, permissionSetName: permissionSetName))
        onDismiss()
        dismiss()
    }
}
