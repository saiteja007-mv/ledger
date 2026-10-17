import SwiftUI
import UIKit

/// Siri, Shortcuts and automations. Apple's own Siri actions (App Intents) can't be built without Xcode, so
/// Ledger takes a link instead: a Shortcut opens `ledger://add?...` and Log Spending appears filled in.
struct ShortcutsView: View {
    @Environment(\.openURL) private var openURL
    @State private var copied: String?

    private let example = "ledger://add?amount=12.50&merchant=Starbucks&category=Food&account=Checking%201234"

    private let parameters: [(name: String, meaning: LocalizedStringKey)] = [
        ("amount", "12.50"),
        ("merchant", "Where, or who"),
        ("category", "Food, Groceries, Transport…"),
        ("account", "An account's name"),
        ("note", "A comment"),
        ("type", "expense, income or transfer"),
        ("to", "A transfer's other account"),
        ("currency", "USD, INR…"),
        ("date", "YYYY-MM-DD"),
    ]

    var body: some View {
        KitScreen(String(localized: "Siri & Shortcuts"), showsBack: true) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    card(symbol: "square.grid.2x2.fill", title: "Widget") {
                        Text("Add **Log Spending** from the widget gallery to your Home Screen or Lock Screen. One tap opens the form.")
                    }
                    card(symbol: "mic.fill", title: "Siri") {
                        VStack(alignment: .leading, spacing: 8) {
                            step(1, "In Shortcuts, tap + and add **Ask for Input** (Number): “How much?”")
                            step(2, "Add another **Ask for Input** (Text): “Where?”")
                            step(3, "Add **URL**: `ledger://add?amount=` then the first answer, `&merchant=` then the second.")
                            step(4, "Add **Open URLs**, and name the shortcut “Log spending”.")
                            Text("Then say “Hey Siri, log spending”. Ledger opens with the form filled in; you check it and tap Confirm.")
                                .foregroundStyle(KitColor.secondary.color)
                        }
                    }
                    card(symbol: "clock.arrow.circlepath", title: "Automations") {
                        Text("In Shortcuts → Automation, run the same shortcut (or a fixed link) when you tap an NFC tag, arrive somewhere, or at a time. A fixed link such as the one below logs the same thing every time, ready to confirm.")
                    }
                    linkReference
                }
                .padding(.horizontal, KitMetrics.margin)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
        }
        .sensoryFeedback(.success, trigger: copied)
    }

    private var linkReference: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("The link").font(.kitSubtitle)
            Text(example)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(KitColor.surface.color, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            HStack {
                Button {
                    UIPasteboard.general.string = example
                    copied = example
                } label: {
                    Label(copied == example ? "Copied" : "Copy", systemImage: copied == example ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.bordered)
                Button {
                    if let url = URL(string: example) { openURL(url) }
                } label: {
                    Label("Try it", systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(.borderedProminent)
            }
            .font(.kitSmallMedium)
            .tint(KitColor.accent.color)
            Text("Every part is optional; leave out what you'll fill in yourself.")
                .font(.kitSmall)
                .foregroundStyle(KitColor.secondary.color)
            VStack(spacing: 0) {
                ForEach(parameters, id: \.name) { parameter in
                    HStack {
                        Text(parameter.name).font(.system(.subheadline, design: .monospaced).weight(.medium))
                        Spacer()
                        Text(parameter.meaning).font(.kitSmall).foregroundStyle(KitColor.secondary.color)
                    }
                    .padding(.vertical, 9)
                    if parameter.name != parameters.last?.name { Divider() }
                }
            }
            .padding(.horizontal, 14)
            .background(KitColor.surface.color, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func card<Content: View>(symbol: String, title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(width: 32, height: 32)
                    .background(KitColor.hero.color, in: .circle)
                Text(title).font(.kitSubtitle)
            }
            content()
                .font(.kitSmall)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(KitColor.surface.color, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func step(_ number: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.kitCaption)
                .frame(width: 20, height: 20)
                .background(KitColor.accent.color.opacity(0.15), in: .circle)
            Text(text)
        }
    }
}
