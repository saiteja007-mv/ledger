import SwiftUI

/// The kit's five tabs in its own tab bar, and the Face ID lock over all of it.
/// Deep links: `ledger://add` opens Log Spending (with `?amount=&merchant=...` filled in, see `QuickLog`);
/// `ledger://<tab>` selects a tab, and the old `review`, `receipts` and `accounts` open those screens
/// under Account.
///
/// A tab's screen is built the first time it's shown and then kept, so scroll position and what a tab
/// has pushed survive switching away.
struct RootView: View {
    @State private var store = LedgerStore()
    @State private var lock = AppLock()
    @State private var navigator = Navigator()
    @State private var visited: Set<AppTab> = [.home]
    @State private var isKeyboardUp = false
    /// No server address yet (none built in, none typed): Connect comes first.
    @State private var needsServer = ServerConfig.serverURL == nil
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var navigator = navigator
        // The bar is a sibling under the screens, not a safe-area inset: a screen's scroll view ends where
        // the bar begins, so nothing is ever scrolled under it.
        VStack(spacing: 0) {
            ZStack {
                ForEach(AppTab.allCases) { tab in
                    if visited.contains(tab) {
                        screen(for: tab)
                            .opacity(navigator.tab == tab ? 1 : 0)
                            .allowsHitTesting(navigator.tab == tab)
                            .accessibilityHidden(navigator.tab != tab)
                    }
                }
            }
            if !isKeyboardUp {
                KitNavBar(selection: $navigator.tab, badge: store.reviewCount)
            }
        }
        .background(KitColor.background.color.ignoresSafeArea())
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            isKeyboardUp = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isKeyboardUp = false
        }
        .sheet(isPresented: $navigator.isAdding, onDismiss: { navigator.addPrefill = nil }) {
            AddTransactionView(prefill: navigator.addPrefill)
        }
        .fullScreenCover(isPresented: $needsServer) {
            ConnectView { needsServer = false }
        }
        .lockCover()
        .environment(store)
        .environment(lock)
        .environment(navigator)
        .tint(KitColor.accent.color)
        .font(.kitBody)
        .task(id: store.revision) {
            await store.refresh()
        }
        .onOpenURL(perform: open)
        .onChange(of: navigator.tab, initial: true) { _, tab in
            visited.insert(tab)
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            scenePhaseChanged(to: phase)
        }
    }

    @ViewBuilder
    private func screen(for tab: AppTab) -> some View {
        switch tab {
        case .home: DashboardView()
        case .analysis: AnalysisView()
        case .activity: TransactionsView()
        case .categories: CategoriesView()
        case .more: MoreView()
        }
    }

    private func open(_ url: URL) {
        guard url.scheme == "ledger", let host = url.host() else { return }
        if host == "add" {
            // Siri and Shortcuts pass amount, merchant, category... in the link; the form opens filled in.
            navigator.addPrefill = QuickLog.draft(from: url)
            navigator.isAdding = true
        } else if let link = AppTab.link(host) {
            if let route = link.route {
                navigator.show(route)
            } else {
                navigator.tab = link.tab
            }
        }
    }

    private func scenePhaseChanged(to phase: ScenePhase) {
        Task { await lock.scenePhaseChanged(to: phase) }
    }
}
