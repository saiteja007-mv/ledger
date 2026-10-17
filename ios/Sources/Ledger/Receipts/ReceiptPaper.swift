import SwiftUI

/// A receipt drawn the way the till printed it: the itemised receipt the ledger holds (from a photo read on
/// the server, or written out by an assistant), in a monospaced type on paper with a torn edge. `compact` is the
/// list card: the first few lines and the total.
struct ReceiptPaper: View {
    let receipt: Receipt
    var compact = false

    private static let ink = Color(kitRGB: 0x1C1C1E)
    private static let paper = Color(kitRGB: 0xFFFDF7)
    private static let shownInCompact = 4

    private var items: [LineItem] {
        compact ? Array(receipt.items.prefix(Self.shownInCompact)) : receipt.items
    }

    private var when: String? {
        guard let text = receipt.purchasedAt else { return nil }
        guard let date = LedgerDate.parse(text) else { return text }
        return text.count > 10
            ? date.formatted(date: .abbreviated, time: .shortened)
            : date.formatted(date: .abbreviated, time: .omitted)
    }

    var body: some View {
        VStack(spacing: 10) {
            header
            ReceiptRule()
            lines
            ReceiptRule()
            totals
            if !compact { footer }
        }
        .font(.system(size: compact ? 12 : 13, design: .monospaced))
        .foregroundStyle(Self.ink)
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 18 + ReceiptEdge.tooth)
        .background {
            ReceiptEdge()
                .fill(Self.paper)
                .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Parts

    private var header: some View {
        VStack(spacing: 3) {
            Text(receipt.title.uppercased())
                .font(.system(size: compact ? 15 : 17, weight: .bold, design: .monospaced))
                .multilineTextAlignment(.center)
                .lineLimit(2)
            if !compact, let address = receipt.bill?.storeAddress {
                Text(address).font(.system(size: 11, design: .monospaced)).multilineTextAlignment(.center)
            }
            if let when {
                Text(when).font(.system(size: 11, design: .monospaced)).opacity(0.7)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var lines: some View {
        if receipt.items.isEmpty {
            Text(receipt.isReading ? "READING THE PHOTO…" : "NO ITEMS ON THIS RECEIPT")
                .opacity(0.6)
                .frame(maxWidth: .infinity)
        } else {
            VStack(spacing: 7) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    line(item)
                }
                if compact, receipt.items.count > items.count {
                    Text("+ \(receipt.items.count - items.count) MORE")
                        .opacity(0.6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func line(_ item: LineItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name.uppercased()).lineLimit(compact ? 1 : 3)
                if !compact {
                    if let qty = item.qty, let unitPrice = item.unitPrice {
                        Text("  \(qty.formatted()) \(item.unit ?? "") @ \(Money.dollars(unitPrice, currency: receipt.currency))")
                            .font(.system(size: 11, design: .monospaced)).opacity(0.65)
                    } else if let qty = item.qty, qty != 1 {
                        Text("  × \(qty.formatted())").font(.system(size: 11, design: .monospaced)).opacity(0.65)
                    }
                }
            }
            Spacer(minLength: 8)
            if let price = item.price {
                Text(Money.dollars(price, currency: receipt.currency)).monospacedDigit()
            }
        }
    }

    private var totals: some View {
        VStack(spacing: 5) {
            if !compact {
                if let subtotal = receipt.bill?.subtotal { amountRow("SUBTOTAL", Money.dollars(subtotal, currency: receipt.currency)) }
                if let tax = receipt.tax ?? receipt.bill?.tax { amountRow("TAX", Money.dollars(tax, currency: receipt.currency)) }
            }
            if let total = receipt.totalCents {
                amountRow("TOTAL", Money.text(total, currency: receipt.currency))
                    .font(.system(size: compact ? 14 : 16, weight: .bold, design: .monospaced))
            }
        }
    }

    private func amountRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).monospacedDigit()
        }
    }

    private var footer: some View {
        VStack(spacing: 6) {
            if let payment = receipt.bill?.payment {
                amountRow("PAID WITH", payment.uppercased())
            }
            if let notes = receipt.bill?.notes {
                Text(notes).font(.system(size: 11, design: .monospaced)).opacity(0.7).frame(maxWidth: .infinity, alignment: .leading)
            } else if let error = receipt.billError {
                Text(error).font(.system(size: 11, design: .monospaced)).foregroundStyle(KitColor.destructive.color)
            }
            ReceiptRule().padding(.top, 4)
            Text("RECEIPT #\(receipt.id)  ·  \(receipt.source?.uppercased() ?? "LEDGER")")
                .font(.system(size: 10, design: .monospaced))
                .opacity(0.55)
                .padding(.top, 2)
        }
    }
}

/// A dashed rule across the paper.
struct ReceiptRule: View {
    var body: some View {
        HorizontalLine()
            .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            .frame(height: 1)
            .opacity(0.35)
    }

    private struct HorizontalLine: Shape {
        func path(in rect: CGRect) -> Path {
            Path { path in
                path.move(to: CGPoint(x: rect.minX, y: rect.midY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            }
        }
    }
}

/// Paper with a straight top and a torn (zig-zag) bottom edge.
struct ReceiptEdge: Shape {
    static let tooth: CGFloat = 7

    func path(in rect: CGRect) -> Path {
        let tooth = Self.tooth
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - tooth))
        var x = rect.maxX
        var low = true
        while x > rect.minX {
            x = max(rect.minX, x - tooth)
            path.addLine(to: CGPoint(x: x, y: low ? rect.maxY : rect.maxY - tooth))
            low.toggle()
        }
        path.closeSubpath()
        return path
    }
}
