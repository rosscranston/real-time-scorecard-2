import SwiftUI
import ScorecardCore

let scoreGreen = Color(red: 0.33, green: 1, blue: 0.57)

@main
struct ScorecardApplication: App {
    @StateObject private var store = AppStore()
    var body: some Scene {
        WindowGroup("Live Scorecard 2") {
            ScorecardView().environmentObject(store).preferredColorScheme(.dark)
        }
        .defaultSize(width: 340, height: 850)
        .commands {
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") { store.undoFromKeyboard() }.keyboardShortcut("z")
                Button("Undo (Control-Z)") { store.undoFromKeyboard() }.keyboardShortcut("z", modifiers: .control)
            }
        }
        Settings { ConnectionSettings().environmentObject(store).preferredColorScheme(.dark) }
    }
}
