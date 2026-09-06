import AppKit
import Observation
import OSLog
import SwiftUI

@MainActor
@Observable
final class Attention: NSObject, NSApplicationDelegate {
    private(set) var running = false

    @ObservationIgnored private var request: Int?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var sprite: Sprite?
    @ObservationIgnored private var started: TimeInterval?
    @ObservationIgnored private var count = 0
    @ObservationIgnored private var window: NSWindow?

    // Count the main jump once per recorded two-second cycle, not its rebounds.
    // AppKit exposes no bounce callback, so this remains a visual estimate.
    private let interval: TimeInterval = 2
    private let retry: TimeInterval = 0.05
    private static let log = Logger(subsystem: "local.forever.prototype", category: "attention")

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.log.info("Launch finished; preparing Dock icon")
        do {
            try prepare()
        } catch {
            NSAlert(error: error).runModal()
            NSApp.terminate(nil)
            return
        }
        // Install the transparent tile before making the app visible in the Dock.
        NSApp.setActivationPolicy(.regular)
        Self.log.info("Dock icon installed")
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
        let sprite = try Sprite(bundle: .main)
        self.sprite = sprite
        NSApp.applicationIconImage = sprite.frames.first
        // Keep our transparent artwork even while idle; the bundled icon gets
        // a system backplate on newer macOS versions.
        NSApp.dockTile.contentView = sprite
        NSApp.dockTile.display()
    }

    func start() {
        guard !running, sprite != nil else { return }
        running = true
        Self.log.info("Starting; active=\(NSApp.isActive, privacy: .public)")
        NSApp.hide(nil)
        Self.log.info("Hide returned; scheduling attention")
        schedule()
    }

    private func schedule(after delay: TimeInterval = 0) {
        guard running else { return }
        // Let Dock registration and activation changes reach the next event-loop
        // turn before sending the first request. An early request can be lost.
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(begin), object: nil)
        perform(#selector(begin), with: nil, afterDelay: delay)
    }

    @objc private func begin() {
        Self.log.debug("Attention attempt; active=\(NSApp.isActive, privacy: .public)")
        // Hiding can resign activation asynchronously; the delegate retries.
        guard running, request == nil, !NSApp.isActive, let sprite else { return }
        let identifier = NSApp.requestUserAttention(.criticalRequest)
        guard identifier >= 0 else {
            // Launch Services may still be registering the Dock tile.
            schedule(after: retry)
            return
        }
        request = identifier
        // Recovery keeps the same run clock; only Stop resets the estimate.
        if started == nil { started = ProcessInfo.processInfo.systemUptime }
        let timer = Timer(timeInterval: 1 / sprite.fps, target: self,
                          selector: #selector(tick), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        tick()
        Self.log.info("Attention requested: \(identifier, privacy: .public)")
    }

    @objc private func tick() {
        guard running, !NSApp.isActive, let sprite, let started else { return }
        let elapsed = ProcessInfo.processInfo.systemUptime - started
        // Derive both values from elapsed time so delayed ticks don't slow the loop.
        sprite.index = Int(elapsed * sprite.fps) % sprite.frames.count
        let next = 1 + Int(elapsed / interval)
        if next != count {
            let renew = count > 0
            count = next
            NSApp.dockTile.badgeLabel = String(count)
            // The Dock can silence a request without notifying us. Renew at a
            // cycle boundary, keeping only one request and leaving the spin alone.
            if renew {
                if let request { NSApp.cancelUserAttentionRequest(request) }
                let identifier = NSApp.requestUserAttention(.criticalRequest)
                guard identifier >= 0 else {
                    request = nil
                    suspend()
                    schedule(after: retry)
                    return
                }
                request = identifier
                Self.log.debug("Attention renewed for cycle \(next, privacy: .public)")
            }
        }
        NSApp.dockTile.display()
    }

    private func suspend() {
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(begin), object: nil)
        if let request {
            NSApp.cancelUserAttentionRequest(request)
            Self.log.info("Attention canceled: \(request, privacy: .public)")
        }
        request = nil
        timer?.invalidate()
        timer = nil
    }

    func stop() {
        running = false
        suspend()
        started = nil
        count = 0
        NSApp.dockTile.badgeLabel = nil
        sprite?.index = 0
        NSApp.dockTile.display()
    }

    func applicationDidResignActive(_ notification: Notification) {
        Self.log.info("Resigned active")
        schedule()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        Self.log.info("Became active")
        // Xcode may activate us after launch has finished. Keep a requested run
        // alive; opening controls is handled explicitly by the Dock reopen event.
        guard running else { return }
        suspend()
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
}
