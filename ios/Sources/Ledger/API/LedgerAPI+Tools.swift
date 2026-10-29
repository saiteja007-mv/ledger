import Foundation

/// One typed call per tool the app uses. Names and arguments match server/mcp.mjs (and the
/// three extras in api.cjs); `Ledger/API.md` lists them all.
extension LedgerAPI {
    // MARK: Overview

    static func netWorth() async throws(LedgerError) -> NetWorth {
        try await call("networth")
    }

    static func categories() async throws(LedgerError) -> [String] {
        try await call("categories")
    }

    /// The brand icon for a merchant as the bank wrote it; `domain` is nil when it has none.
    static func merchantLogo(_ merchant: String) async throws(LedgerError) -> MerchantLogo {
        try await call("merchant_logo", ["merchant": .string(merchant)])
    }

    static func status() async throws(LedgerError) -> LedgerStatus {
        try await call("get_status")
    }

    /// This month when no dates are given.
    static func spendingSummary() async throws(LedgerError) -> SpendingSummary {
        try await call("spending_summary")
    }

    /// Expense by category, largest first: this month, or `from` (inclusive) up to `to` (exclusive).
    static func categoryBreakdown(from: String? = nil, to: String? = nil) async throws(LedgerError) -> [CategoryTotal] {
        try await call("category_breakdown", [
            "from": from.map(JSONValue.string), "to": to.map(JSONValue.string), "limit": .int(20),
        ])
    }

    static func budgetStatus() async throws(LedgerError) -> [BudgetStatus] {
        try await call("budget_status")
    }

    static func setBudget(category: String, period: String, limitCents: Int) async throws(LedgerError) {
        let _: Ignored = try await call("set_budget", [
            "category": .string(category), "period": .string(period), "limit_cents": .int(limitCents),
        ])
    }

    // MARK: Transactions

    static func recentTransactions(limit: Int = 8) async throws(LedgerError) -> [LedgerTransaction] {
        try await call("list_transactions", ["limit": .int(limit)])
    }

    static func transactions(account: String, limit: Int = 30) async throws(LedgerError) -> [LedgerTransaction] {
        try await call("list_transactions", ["account": .string(account), "limit": .int(limit)])
    }

    /// Activity's list. A search is capped by search_transactions at 200 rows, which has no paging,
    /// so a full 200 is reported as truncated; a filtered list is read in pages (see `TransactionPaging`).
    static func transactions(matching filter: TransactionFilter) async throws(LedgerError) -> TransactionList {
        let query = filter.trimmedQuery
        if !query.isEmpty {
            let limit = 200
            let found: [LedgerTransaction] = try await call("search_transactions", ["q": .string(query), "limit": .int(limit)])
            return TransactionList(rows: found.filter(filter.matches), isTruncated: found.count >= limit)
        }
        let range = filter.period.range()
        return try await expenses(from: range.from, to: range.to, account: filter.account,
                                  category: filter.category, direction: filter.direction)
    }

    /// The rows behind one category total: its expenses over the month, newest first, every one of them.
    /// Sums to the budget's `spent` and the breakdown's `total` (both add up base_amount of expenses
    /// that aren't voided), because it is the same set: direction expense, the same category text, the
    /// same `[from, to)`.
    static func categoryTransactions(_ scope: CategoryScope) async throws(LedgerError) -> TransactionList {
        try await expenses(from: scope.period.from, to: scope.period.to, account: nil,
                           category: scope.category, direction: .expense)
    }

    /// Every row from `from` (inclusive) up to `to` (exclusive), any direction, newest first: Analysis's bars.
    static func transactions(from: String?, to: String?) async throws(LedgerError) -> TransactionList {
        try await expenses(from: from, to: to, account: nil, category: nil, direction: nil)
    }

    private static func expenses(
        from: String?, to: String?, account: String?, category: String?, direction: Direction?
    ) async throws(LedgerError) -> TransactionList {
        do {
            return try await TransactionPaging.collect(upper: to) { upper in
                let page: [LedgerTransaction] = try await call("list_transactions", [
                    "from": from.map(JSONValue.string),
                    "to": upper.map(JSONValue.string),
                    "account": account.map(JSONValue.string),
                    "category": category.map(JSONValue.string),
                    "direction": direction.map { .string($0.rawValue) },
                    "limit": .int(TransactionPaging.pageSize),
                ])
                return page
            }
        } catch {
            throw LedgerError(error)
        }
    }

    /// Writes the row, then marks it reviewed: you typed it yourself, the same as the web form.
    /// Returns the new transaction's id.
    @discardableResult
    static func add(_ draft: NewTransaction) async throws(LedgerError) -> Int? {
        let result: UpsertResult = try await call("upsert_transactions", [
            "source": "ledger-ios", "items": [draft.item],
        ])
        if let rowError = result.errors.first { throw .rejected(rowError.error) }
        if !result.ids.isEmpty { try await markReviewed(result.ids) }
        return result.ids.first
    }

    static func setCategory(id: Int, category: String) async throws(LedgerError) -> LedgerTransaction {
        try await call("set_category", ["id": .int(id), "category": .string(category)])
    }

    static func markReviewed(_ ids: [Int]) async throws(LedgerError) {
        let _: Ignored = try await call("mark_reviewed", ["ids": .array(ids.map(JSONValue.int))])
    }

    /// Soft delete: the row is hidden and kept, never destroyed.
    static func void(id: Int, reason: String) async throws(LedgerError) {
        let _: Ignored = try await call("void_transaction", ["id": .int(id), "reason": .string(reason)])
    }

    static func reviewQueue() async throws(LedgerError) -> [LedgerTransaction] {
        try await call("review_queue", ["limit": 500])
    }

    static func suggestions() async throws(LedgerError) -> [CategorySuggestion] {
        try await call("suggest_categories", ["limit": 500])
    }

    // MARK: Accounts

    static func balances(account: String) async throws(LedgerError) -> [BalanceSnapshot] {
        try await call("list_balances", ["account": .string(account)])
    }

    static func recordBalance(account: String, date: Date, cents: Int, currency: String) async throws(LedgerError) {
        let _: Ignored = try await call("record_balance", [
            "account": .string(account), "as_of_date": .string(LedgerDate.day(date)),
            "balance_cents": .int(cents), "currency": .string(currency),
        ])
    }

    static func reconcile(account: String, from: String, to: String) async throws(LedgerError) -> Reconciliation {
        try await call("reconcile_account", ["account": .string(account), "from": .string(from), "to": .string(to)])
    }

    static func audit(limit: Int = 100) async throws(LedgerError) -> [AuditEntry] {
        try await call("list_audit", ["limit": .int(limit)])
    }

    // MARK: Receipts

    static func receipts(limit: Int = 200) async throws(LedgerError) -> [Receipt] {
        try await call("list_receipts", ["limit": .int(limit)])
    }

    static func receipt(id: Int) async throws(LedgerError) -> Receipt {
        try await call("get_receipt", ["id": .int(id)])
    }

    static func receiptImage(id: Int) async throws(LedgerError) -> ReceiptImage {
        try await call("get_receipt_image", ["id": .int(id), "max_width": 1600], timeout: 60)
    }

    /// Stores the photo and queues it to be read into a bill. Blank fields are read off the photo.
    static func uploadReceipt(
        jpeg: Data, merchant: String?, total: Double?, purchasedAt: Date?, transactionID: Int?
    ) async throws(LedgerError) -> UploadResult {
        try await call("upload_receipt_photo", [
            "image_base64": .string(jpeg.base64EncodedString()),
            "ext": "jpg",
            "merchant": merchant.map(JSONValue.string),
            "total": total.map(JSONValue.double),
            "purchased_at": purchasedAt.map { .string(LedgerDate.day($0)) },
            "transaction_id": transactionID.map(JSONValue.int),
        ], timeout: 120)
    }

    static func priceItems(query: String) async throws(LedgerError) -> [PriceItem] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return try await call("item_prices", ["q": query.isEmpty ? nil : .string(query), "limit": 300])
    }

    static func priceHistory(for item: PriceItem) async throws(LedgerError) -> [PricePoint] {
        try await call("item_price_history", ["item_key": .string(item.itemKey), "unit": .string(item.unit)])
    }

    static func priceHistory(for item: InventoryItem) async throws(LedgerError) -> [PricePoint] {
        try await call("item_price_history", ["item_key": .string(item.itemKey), "unit": .string(item.unit)])
    }

    // MARK: Inventory and shopping list

    /// Tracked items; `includeUntracked` adds the ones switched off, bought once or lapsed.
    static func inventory(includeUntracked: Bool) async throws(LedgerError) -> [InventoryItem] {
        try await call("inventory", ["include_untracked": .bool(includeUntracked)])
    }

    /// Says an item ran out, which teaches the estimate how fast it goes. The server dates it today.
    static func markUsedUp(_ item: InventoryItem) async throws(LedgerError) {
        let _: Ignored = try await call("mark_used_up", ["item_key": .string(item.itemKey), "unit": .string(item.unit)])
    }

    /// `true` always tracks the item, `false` hides it, nil goes back to automatic (bought on 2+ days).
    static func setTracking(_ item: InventoryItem, tracked: Bool?) async throws(LedgerError) {
        let value: JSONValue = tracked.map(JSONValue.bool) ?? .null
        let _: Ignored = try await call("set_item_tracking", [
            "item_key": .string(item.itemKey), "unit": .string(item.unit), "tracked": value,
        ])
    }

    static func shoppingList() async throws(LedgerError) -> ShoppingList {
        try await call("shopping_list")
    }

    /// `bought` ticks rows off, `dismiss` closes rule and Claude rows, `remove` closes the owner's own;
    /// each list only touches rows it fits. Empty lists are left out.
    static func updateShopping(
        add: [NewShoppingItem] = [], bought: [Int] = [], dismiss: [Int] = [], remove: [Int] = []
    ) async throws(LedgerError) {
        func ids(_ list: [Int]) -> JSONValue? { list.isEmpty ? nil : .array(list.map(JSONValue.int)) }
        let _: Ignored = try await call("update_shopping_list", [
            "add": add.isEmpty ? nil : .array(add.map(\.json)),
            "bought": ids(bought), "dismiss": ids(dismiss), "remove": ids(remove),
        ])
    }

    /// Only queues the request: the server runs Claude within a minute, and `ai.pending` is true until then.
    static func refreshShopping() async throws(LedgerError) {
        let _: Ignored = try await call("refresh_shopping_list")
    }
}
