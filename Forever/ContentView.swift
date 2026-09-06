import SwiftUI

struct ContentView: View {
    let attention: Attention

    var body: some View {
        HStack(spacing: 12) {
            Button("Start", action: attention.start)
                .keyboardShortcut(.defaultAction)
                .disabled(attention.running)
                .help("Hide this window and start bouncing. Click the Dock icon to stop.")
            Button("Stop", action: attention.stop)
                .keyboardShortcut(.cancelAction)
                .disabled(!attention.running)
        }
        .controlSize(.large)
        .frame(width: 240, height: 112)
    }
}
