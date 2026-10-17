import SwiftUI
import UIKit

/// The ledger's MCP server: where assistants reach it, whether it answers, how to connect one, and every
/// tool it offers. No secret is shown: the bearer token stays on the server. Without `LedgerMCPURL` (an optional
/// extra, docs/extras.md) it says so and still lists the tools.
struct McpView: View {
    @State private var status: Status = .checking
    @State private var tools: Loadable<[ToolInfo]> = .loading
    @State private var expanded: Set<String> = []
    @State private var copied: String?

    private enum Status {
        case checking
        case online(Int)
        case offline
        case notSetUp
    }

    /// The published MCP endpoint, or what to do when there's none.
    private var mcpText: String {
        ServerConfig.mcpURL?.absoluteString ?? String(localized: "Not published from this server yet (see docs/extras.md).")
    }

    private var claudeCodeCommand: String {
        "claude mcp add --transport http finance \(ServerConfig.mcpURL?.absoluteString ?? "<your MCP URL>") --header \"Authorization: Bearer <token>\""
    }

    var body: some View {
        KitScreen(String(localized: "MCP server"), showsBack: true) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    serverCard
                    connectCard
                    toolsSection
                }
                .padding(.horizontal, KitMetrics.margin)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .refreshable { await load() }
        }
        .task { await load() }
        .sensoryFeedback(.success, trigger: copied)
    }

    // MARK: Server

    private var serverCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(KitColor.accent.color.gradient)
                    Image(systemName: "server.rack").font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
                }
                .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ledger MCP").font(.kitSubtitle)
                    Text("Streamable HTTP · read and write").font(.kitSmall).foregroundStyle(KitColor.secondary.color)
                }
                Spacer()
                statusPill
            }
            Text(mcpText)
                .font(.system(.footnote, design: .monospaced))
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(KitColor.background.color, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            if let url = ServerConfig.mcpURL {
                copyButton(String(localized: "Copy URL"), text: url.absoluteString)
            }
        }
        .padding(16)
        .background(KitColor.surface.color, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    @ViewBuilder
    private var statusPill: some View {
        switch status {
        case .checking:
            ProgressView().controlSize(.small)
        case .online(let code):
            pill(code == 401 || code == 403 ? "Online · sign-in" : "Online", color: KitColor.positive.color)
        case .offline:
            pill("Unreachable", color: KitColor.destructive.color)
        case .notSetUp:
            pill("Not set up", color: KitColor.secondary.color)
        }
    }

    private func pill(_ text: LocalizedStringKey, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).font(.kitCaption)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(color.opacity(0.14), in: .capsule)
    }

    // MARK: Connect

    private var connectCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Connect an assistant").font(.kitSubtitle)
            connectRow(
                symbol: "person.badge.key.fill", title: "claude.ai, ChatGPT, Claude Desktop",
                detail: String(localized: "Add a custom connector with the URL above, behind the sign-in you put in front of it. Then the assistant can read and log transactions."))
            connectRow(
                symbol: "terminal.fill", title: "Claude Code",
                detail: String(localized: "Add it with a bearer token in the Authorization header. The token stays on your server; it is never shown here."))
            Text(claudeCodeCommand)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(KitColor.background.color, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            copyButton(String(localized: "Copy command"), text: claudeCodeCommand)
            connectRow(
                symbol: "iphone", title: "This app",
                detail: String(localized: "Ledger talks to the same ledger through its own API on your server, over Tailscale only."))
        }
        .padding(16)
        .background(KitColor.surface.color, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func connectRow(symbol: String, title: LocalizedStringKey, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(KitColor.accent.color)
                .frame(width: 28, height: 28)
                .background(KitColor.accent.color.opacity(0.12), in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.kitBodyMedium)
                Text(detail).font(.kitSmall).foregroundStyle(KitColor.secondary.color)
            }
        }
    }

    private func copyButton(_ title: String, text: String) -> some View {
        Button {
            UIPasteboard.general.string = text
            copied = text
        } label: {
            Label(copied == text ? String(localized: "Copied") : title, systemImage: copied == text ? "checkmark" : "doc.on.doc")
                .font(.kitSmallMedium)
        }
        .buttonStyle(.bordered)
        .tint(KitColor.accent.color)
    }

    // MARK: Tools

    @ViewBuilder
    private var toolsSection: some View {
        switch tools {
        case .loading:
            ProgressView().frame(maxWidth: .infinity).padding(.top, 20)
        case .failed(let error):
            InlineError(error: error)
        case .loaded(let all):
            let mcp = all.filter(\.isMCP)
            let writes = mcp.filter(\.isWrite).count
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Tools").font(.kitSubtitle)
                    Spacer()
                    Text("\(mcp.count) tools · \(writes) write")
                        .font(.kitSmall)
                        .foregroundStyle(KitColor.secondary.color)
                }
                ForEach(mcp) { tool in toolRow(tool) }
                let extras = all.filter { !$0.isMCP }
                if !extras.isEmpty {
                    Text("App only").font(.kitSubtitle).padding(.top, 10)
                    ForEach(extras) { tool in toolRow(tool) }
                }
            }
        }
    }

    private func toolRow(_ tool: ToolInfo) -> some View {
        let isOpen = expanded.contains(tool.name)
        return Button {
            withAnimation(.snappy) {
                if isOpen { expanded.remove(tool.name) } else { expanded.insert(tool.name) }
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: tool.isWrite ? "pencil.circle.fill" : "eye.circle.fill")
                        .foregroundStyle(tool.isWrite ? KitColor.warning.color : KitColor.accent.color)
                    Text(tool.name).font(.system(.subheadline, design: .monospaced).weight(.medium))
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                        .foregroundStyle(KitColor.secondary.color)
                }
                if let description = tool.description {
                    Text(description)
                        .font(.kitSmall)
                        .foregroundStyle(KitColor.secondary.color)
                        .lineLimit(isOpen ? nil : 2)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(KitColor.surface.color, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(KitColor.label.color)
    }

    // MARK: Loading

    private func load() async {
        async let code = LedgerAPI.mcpStatusCode()
        async let catalog = Loadable.capture { try await LedgerAPI.toolCatalog() }
        let (statusCode, toolList) = await (code, catalog)
        status = ServerConfig.mcpURL == nil ? .notSetUp : statusCode.map(Status.online) ?? .offline
        tools = toolList
    }
}
