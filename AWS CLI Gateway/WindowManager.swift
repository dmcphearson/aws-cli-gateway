import SwiftUI
import Cocoa

// MARK: - Liquid Glass Container for Windows
struct LiquidGlassContainer<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.regularMaterial)
    }
}

class WindowManager {
    static let shared = WindowManager()
    
    private var windows: [String: NSWindow] = [:]
    
    private init() {}
    
    func showWindow<Content: View>(
        id: String,
        title: String,
        size: NSSize,
        style: NSWindow.StyleMask = [.titled, .closable],
        content: Content
    ) where Content: View {
        // If there's already a window with the same ID, bring it to front instead of making a new one
        if let existingWindow = windows[id] {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // Create and configure the window with Liquid Glass styling
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: size.width, height: size.height),
            styleMask: style,
            backing: .buffered,
            defer: false
        )

        window.title = title
        window.center()
        window.isReleasedWhenClosed = false

        // Apply Liquid Glass window styling
        window.titlebarAppearsTransparent = true
        window.backgroundColor = .windowBackgroundColor
        window.hasShadow = true

        // Wrap content with Liquid Glass container
        let liquidGlassContent = LiquidGlassContainer {
            content
        }

        window.contentView = NSHostingView(rootView: liquidGlassContent)

        // Keep a reference so we can clean up later
        let delegate = WindowDelegate(id: id)
        window.delegate = delegate

        // Associate the delegate with the window
        objc_setAssociatedObject(
            window,
            "delegateKey",
            delegate,
            .OBJC_ASSOCIATION_RETAIN
        )

        windows[id] = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func closeWindow(id: String) {
        windows[id]?.close()
        windows.removeValue(forKey: id)
    }
    
    // MARK: - Show Settings Window
    func showSettingsWindow() {
        showWindow(
            id: "settings",
            title: "AWS CLI Gateway Settings",
            size: NSSize(width: 580, height: 450),
            style: [.titled, .closable, .resizable, .fullSizeContentView],
            content: SettingsView(onClose: {
                self.closeWindow(id: "settings")
            })
        )
    }

    // MARK: - Show Add Profile Window
    func showAddProfileWindow() {
        showSettingsWindow()
    }

    // MARK: - Show Profiles Window
    func showProfilesWindow() {
        showSettingsWindow()
    }
}

private class WindowDelegate: NSObject, NSWindowDelegate {
    let windowId: String
    
    init(id: String) {
        self.windowId = id
        super.init()
    }
    
}
