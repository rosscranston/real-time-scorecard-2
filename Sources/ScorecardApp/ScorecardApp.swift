import SwiftUI
import ScorecardCore

@main
struct ScorecardApplication: App {
    var body: some Scene {
        WindowGroup("Live Scorecard 2") {
            VStack(alignment: .leading, spacing: 12) {
                Text("LIVE SCORECARD 2").foregroundStyle(.green)
                Text("Independent app foundation")
                Text("Cloud extraction and the live interface are being connected.")
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 12, design: .monospaced))
            .padding().frame(minWidth: 260, minHeight: 600, alignment: .topLeading)
            .preferredColorScheme(.dark)
        }
    }
}
