import AppKit
import Observation
import OSLog
import SwiftUI

@MainActor
@Observable
final class Attention: NSObject, NSApplicationDelegate {
    private(set) var running = false

    private var request: Int?
    private var timer: Timer?
    private var sprite: Sprite?
    private var started: TimeInterval = 0
    private var count = -1
    private var window: NSWindow?

    // Count the main jump once per recorded two-second cycle, not its rebounds.
    // AppKit exposes no bounce callback, so this remains a visual estimate.
    private let interval: TimeInterval = 2
    private static let log = Logger(subsystem: "local.forever.prototype", category: "attention")

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            try prepare()
        } catch {
            NSAlert(error: error).runModal()
            return
        }
        // Install the transparent tile before making the app visible in the Dock.
        NSApp.setActivationPolicy(.regular)
        let menu = NSMenu()
        let item = NSMenuItem()
        let application = NSMenu()
        application.addItem(withTitle: "Quit Forever", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = application
        menu.addItem(item)
        NSApp.mainMenu = menu
        start()
    }

    private func prepare() throws {
        if sprite == nil { sprite = try Sprite(bundle: .main) }
        NSApp.applicationIconImage = sprite?.frames.first
        // Keep our transparent artwork even while idle; the bundled icon gets
        // a system backplate on newer macOS versions.
        NSApp.dockTile.contentView = sprite
        NSApp.dockTile.display()
    }

    @objc func start() {
        guard !running else { return }
        do {
            try prepare()
        } catch {
            NSAlert(error: error).runModal()
            return
        }
        running = true
        NSApp.hide(nil)
        schedule()
    }

    private func schedule(after delay: TimeInterval = 0) {
        // Let Dock registration and activation changes reach the next event-loop
        // turn before sending the first request. An early request can be lost.
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(begin), object: nil)
        perform(#selector(begin), with: nil, afterDelay: delay)
    }

    @objc private func begin() {
        // Hiding can resign activation asynchronously; the delegate retries.
        guard running, request == nil, !NSApp.isActive, let sprite else { return }
        count = -1
        NSApp.dockTile.contentView = sprite
        let identifier = NSApp.requestUserAttention(.criticalRequest)
        guard identifier >= 0 else {
            // Launch Services may still be registering the Dock tile.
            schedule(after: 0.05)
            return
        }
        request = identifier
        started = ProcessInfo.processInfo.systemUptime
        tick()
        let timer = Timer(timeInterval: 1 / sprite.fps, target: self,
                          selector: #selector(tick), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        Self.log.info("Attention requested: \(self.request!, privacy: .public)")
    }

    @objc private func tick() {
        guard running, !NSApp.isActive, let sprite else { return }
        let elapsed = ProcessInfo.processInfo.systemUptime - started
        // Derive both values from elapsed time so delayed ticks don't slow the loop.
        sprite.index = Int(elapsed * sprite.fps) % sprite.frames.count
        let next = 1 + Int(elapsed / interval)
        if next != count {
            // The Dock can silence a request without notifying us. Renew at a
            // cycle boundary, keeping only one request and leaving the spin alone.
            if count >= 1 {
                if let request { NSApp.cancelUserAttentionRequest(request) }
                let identifier = NSApp.requestUserAttention(.criticalRequest)
                guard identifier >= 0 else {
                    request = nil
                    timer?.invalidate()
                    timer = nil
                    schedule(after: 0.05)
                    return
                }
                request = identifier
                Self.log.debug("Attention renewed for cycle \(next, privacy: .public)")
            }
            count = next
            NSApp.dockTile.badgeLabel = String(count)
        }
        NSApp.dockTile.display()
    }

    func stop() {
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(begin), object: nil)
        if let request {
            NSApp.cancelUserAttentionRequest(request)
            Self.log.info("Attention canceled: \(request, privacy: .public)")
        }
        request = nil
        timer?.invalidate()
        timer = nil
        running = false
        NSApp.dockTile.badgeLabel = nil
        sprite?.index = 0
        NSApp.dockTile.display()
    }

    func applicationDidResignActive(_ notification: Notification) {
        schedule()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // Xcode may activate us after launch has finished. Keep a requested run
        // alive; opening controls is handled explicitly by the Dock reopen event.
        guard running else { return }
        if let request { NSApp.cancelUserAttentionRequest(request) }
        request = nil
        timer?.invalidate()
        timer = nil
        NSApp.hide(nil)
        schedule()
    }

    private func show() {
        NSApp.unhide(nil)
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 240, height: 112),
                                  styleMask: [.titled, .closable, .miniaturizable],
                                  backing: .buffered, defer: false)
            window.title = "Forever"
            window.titleVisibility = .hidden
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: ContentView(attention: self))
            window.center()
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        stop()
        show()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
