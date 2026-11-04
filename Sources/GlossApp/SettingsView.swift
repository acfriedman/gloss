import SwiftUI

/// The Settings window: how big the detail pane sets its text, with a line of a type's page to judge it by.
struct SettingsView: View {
    @AppStorage(TextSize.key) private var textSize = 1.0

    var body: some View {
        Form {
            Picker("Detail text size", selection: $textSize) {
                ForEach(TextSize.steps, id: \.self) { step in
                    Text(step == 1 ? "\(TextSize.percent(step)), the system's" : TextSize.percent(step)).tag(step)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("public struct Cart").textStyle(.title3, design: .monospaced, weight: .semibold)
                Text("A cart of lines a shopper means to buy.").textStyle(.callout)
                Text("func total() -> Int").textStyle(.callout, design: .monospaced)
            }
            .environment(\.textScale, textSize)
            .padding(.vertical, 4)
            Text("⌥⌘+ and ⌥⌘− change it from the View menu too. The list and the map keep their sizes; ⌘+ and ⌘− zoom the map.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(width: 440)
    }
}
