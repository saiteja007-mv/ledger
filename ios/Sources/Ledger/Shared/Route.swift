/// Every pushed screen. Each tab's NavigationStack registers these once, with `ledgerDestinations()`.
enum Route: Hashable {
    case transaction(LedgerTransaction)
    case receipt(id: Int)
    case account(AccountBalance)
    case budgets
    case prices
    case priceHistory(PriceItem)
    case inventory
    case inventoryItem(InventoryItem)
    case shoppingList
    case audit
    /// A category's expenses over one month (what a budget or a chart slice adds up).
    case category(CategoryScope)
    // The screens More lists.
    case accounts
    case review
    case receipts
    /// The ledger's MCP server: URL, status, how to connect, tools.
    case mcp
    /// Siri, Shortcuts and the Log Spending widget.
    case shortcuts
    case server
}
