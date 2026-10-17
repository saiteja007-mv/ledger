import SwiftUI

/// How a category looks: an SF Symbol on a coloured circle. Names are the ledger's plain category names
/// ("Food", "Transport", "Interest & fees"); anything else is matched by keyword, and what matches nothing
/// gets the grid. Account kinds ("checking", "credit", "cash", "people") have looks too, for the wallet.
struct KitCategory: Sendable {
    let symbol: String
    let tint: Color

    private struct Look {
        let names: [String]
        let keywords: [String]
        let symbol: String
        let tint: UInt32
    }

    private static let looks: [Look] = [
        Look(names: ["food"], keywords: ["restaurant", "dining", "coffee", "cafe", "takeout", "lunch", "dinner", "breakfast"],
             symbol: "fork.knife", tint: 0xF97316),
        Look(names: ["groceries"], keywords: ["grocer", "supermarket", "market", "pantry"], symbol: "cart.fill", tint: 0x16A34A),
        Look(names: ["transport"], keywords: ["transport", "fuel", "gas", "uber", "lyft", "taxi", "transit", "parking", "travel"],
             symbol: "car.fill", tint: 0x365FF1),
        Look(names: ["subscriptions"], keywords: ["subscription", "stream", "netflix", "spotify"], symbol: "play.rectangle.fill", tint: 0x8B5CF6),
        Look(names: ["utilities"], keywords: ["utilit", "electric", "internet", "phone", "water"], symbol: "bolt.fill", tint: 0xEAB308),
        Look(names: ["rent"], keywords: ["rent", "housing", "mortgage", "lease"], symbol: "house.fill", tint: 0xFF5A5F),
        Look(names: ["household"], keywords: ["household", "furnitur", "home"], symbol: "sofa.fill", tint: 0x0D9488),
        Look(names: ["education loan"], keywords: ["loan"], symbol: "graduationcap.fill", tint: 0x4F46E5),
        Look(names: ["education"], keywords: ["education", "tuition", "course", "book"], symbol: "book.fill", tint: 0x0891B2),
        Look(names: ["health"], keywords: ["health", "medic", "pharmacy", "doctor", "dental", "clinic", "gym"],
             symbol: "cross.case.fill", tint: 0xE53D60),
        Look(names: ["beauty"], keywords: ["beauty", "salon", "hair", "cosmetic"], symbol: "sparkles", tint: 0xEC4899),
        Look(names: ["apparel"], keywords: ["apparel", "cloth", "shoe"], symbol: "tshirt.fill", tint: 0xDB2777),
        Look(names: ["electronics"], keywords: ["electronic", "gadget", "computer"], symbol: "laptopcomputer", tint: 0x475569),
        Look(names: ["culture"], keywords: ["culture", "entertain", "movie", "cinema", "museum", "concert", "game"],
             symbol: "theatermasks.fill", tint: 0x7C3AED),
        Look(names: ["poker"], keywords: ["poker", "casino"], symbol: "suit.spade.fill", tint: 0x1F2937),
        Look(names: ["gift"], keywords: ["gift", "donation"], symbol: "gift.fill", tint: 0xDC2626),
        Look(names: ["interest & fees"], keywords: ["fee", "interest", "charge"], symbol: "percent", tint: 0x6B7280),
        Look(names: ["refund"], keywords: ["refund", "cashback", "reimburse"], symbol: "arrow.uturn.backward", tint: 0x4AA879),
        Look(names: ["friends", "people"], keywords: ["friend", "split"], symbol: "person.2.fill", tint: 0x0EA5E9),
        Look(names: ["income"], keywords: ["salary", "income", "paycheck", "payroll", "wage", "bonus", "deposit", "saving"],
             symbol: "dollarsign", tint: 0x4AA879),
        Look(names: ["adjustment", "balance adjustment"], keywords: [], symbol: "slider.horizontal.3", tint: 0x6B7280),
        Look(names: ["credit card bill", "credit card payment", "credit"], keywords: ["credit card"],
             symbol: "creditcard.fill", tint: 0x334155),
        Look(names: ["transfers", "transfer"], keywords: [], symbol: "arrow.left.arrow.right", tint: 0x6B7280),
        Look(names: ["checking"], keywords: ["bank"], symbol: "building.columns.fill", tint: 0x365FF1),
        Look(names: ["cash"], keywords: [], symbol: "banknote.fill", tint: 0x16A34A),
        Look(names: ["total", "all spending"], keywords: [], symbol: "chart.pie.fill", tint: 0x365FF1),
        Look(names: ["(uncategorized)", "uncategorized"], keywords: [], symbol: "questionmark", tint: 0x71717A),
    ]

    private static let other = Look(names: ["other"], keywords: [], symbol: "square.grid.2x2.fill", tint: 0x52525B)

    init(name: String) {
        let key = CategoryName.display(name).lowercased()
        let raw = name.lowercased()
        let look = Self.looks.first { $0.names.contains(key) || $0.names.contains(raw) }
            ?? Self.looks.first { look in look.keywords.contains { key.contains($0) } }
            ?? Self.other
        symbol = look.symbol
        tint = Color(kitRGB: look.tint)
    }

    /// The circle and the glyph on it.
    var avatar: (background: Color, glyph: Color) {
        (tint, KitColor.white)
    }
}

/// A round avatar for a category or merchant: the category's symbol on its colour, or, when `merchant` is a
/// brand ledger-api has a logo for, that logo on white. Nothing is shown until the logo arrives, and a merchant
/// with none keeps the category look.
struct KitAvatar: View {
    let category: String
    /// The transaction's merchant text, as the bank wrote it.
    var merchant: String?
    /// A transfer between the user's own accounts: a neutral arrows icon, never a brand or a category.
    var isTransfer = false
    var size: CGFloat = 40

    @State private var logo: UIImage?

    var body: some View {
        let style = KitCategory(name: category)
        ZStack {
            if isTransfer {
                Circle().fill(KitColor.surface.color)
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: size * 0.38, weight: .semibold))
                    .foregroundStyle(KitColor.label.color)
            } else if let logo {
                Circle().fill(.white)
                Image(uiImage: logo)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .padding(size * 0.2)
                Circle().strokeBorder(KitColor.separator.color, lineWidth: 0.5)
            } else {
                Circle().fill(style.tint.gradient)
                Image(systemName: style.symbol)
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundStyle(style.avatar.glyph)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .task(id: merchant) {
            guard let merchant, let data = await LogoStore.shared.logo(for: merchant) else {
                logo = nil
                return
            }
            logo = UIImage(data: data)
        }
    }
}
