import SwiftUI

/// The address of your Ledger server. Shown at launch when this copy of the app has none (no `LedgerServerURL`
/// in Info.plist and nothing typed yet), and from More to change it. The address is checked against
/// `/healthz` before it's kept, so a typo never becomes "Ledger API unreachable" on every screen.
struct ConnectView: View {
    /// From More there's a way back; at launch there isn't, because nothing works without a server.
    var canCancel = false
    /// At launch the caller closes the cover; from More, Connect goes back.
    var onConnected: (() -> Void)?

    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var address = ServerConfig.serverURL?.absoluteString ?? ""
    @State private var isChecking = false
    @State private var problem: String?

    var body: some View {
        KitScreen(String(localized: "Your server"), showsBack: canCancel) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Connect to your Ledger")
                        .font(.kitHeading)
                    Text("The address your setup printed, like https://myserver.your-tailnet.ts.net:8448. Turn Tailscale on on this iPhone, signed in to the same tailnet as the server.")
                        .font(.kitSmall)
                        .foregroundStyle(KitColor.secondary.color)
                    TextField("https://myserver.your-tailnet.ts.net:8448", text: $address)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.go)
                        .onSubmit(connect)
                        .kitUnderlinedField()
                    if let problem {
                        Text(problem)
                            .font(.kitSmall)
                            .foregroundStyle(KitColor.destructive.color)
                    }
                }
                .padding(.horizontal, KitMetrics.margin)
                .padding(.top, 24)
            }
        }
        .safeAreaInset(edge: .bottom) {
            Group {
                if isChecking {
                    ProgressView().frame(minHeight: 56)
                } else {
                    Button("Connect", action: connect)
                        .buttonStyle(KitPrimaryButtonStyle())
                        .disabled(ServerConfig.normalized(address) == nil)
                }
            }
            .padding(.horizontal, KitMetrics.margin)
            .padding(.vertical, 8)
            .background(KitColor.background.color)
        }
    }

    private func connect() {
        Task { await check() }
    }

    private func check() async {
        guard let url = ServerConfig.normalized(address) else { return }
        isChecking = true
        defer { isChecking = false }
        problem = nil
        do {
            // ledger-api answers /healthz with {"ok": true, "app": "ledger-api", ...}.
            let (data, response) = try await URLSession.shared.data(from: url.appending(path: "healthz"))
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard (response as? HTTPURLResponse)?.statusCode == 200, json?["app"] as? String == "ledger-api" else {
                problem = String(localized: "That address answered, but it isn't a Ledger API. Check the port (8448 by default).")
                return
            }
            UserDefaults.standard.set(url.absoluteString, forKey: ServerConfig.storedKey)
            store.didChange()
            if let onConnected { onConnected() } else { dismiss() }
        } catch {
            problem = String(localized: "No answer from \(url.host() ?? "there"). Is Tailscale on, and the server running?")
        }
    }
}
