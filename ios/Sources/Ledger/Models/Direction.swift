import Foundation

/// Which way money moved. Transfers are between your own accounts and never count as spending.
enum Direction: String, Codable, CaseIterable, Identifiable, Sendable {
    case expense
    case income
    case transferOut = "transfer_out"
    case transferIn = "transfer_in"

    var id: Self { self }

    var label: LocalizedStringResource {
        switch self {
        case .expense: "Expense"
        case .income: "Income"
        case .transferOut: "Transfer out"
        case .transferIn: "Transfer in"
        }
    }

    var systemImage: String {
        switch self {
        case .expense: "arrow.up.right"
        case .income: "arrow.down.left"
        case .transferOut, .transferIn: "arrow.left.arrow.right"
        }
    }

    /// The effect on the account's balance.
    var sign: Int {
        switch self {
        case .income, .transferIn: 1
        case .expense, .transferOut: -1
        }
    }

    var isTransfer: Bool {
        self == .transferIn || self == .transferOut
    }
}
