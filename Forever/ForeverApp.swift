import AppKit

@main
struct ForeverApp {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let attention = Attention()
        app.delegate = attention
        app.run()
        withExtendedLifetime(attention) {}
    }
}
