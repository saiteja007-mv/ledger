import SwiftUI
import WidgetKit

// Never name this "Bundle": it would shadow Foundation.Bundle.
@main
struct LedgerWidgetBundle: WidgetBundle {
    var body: some Widget {
        QuickAddWidget()
        SpendWidget()
        BudgetsWidget()
        RecentWidget()
    }
}
