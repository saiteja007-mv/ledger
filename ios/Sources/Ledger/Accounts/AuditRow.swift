import SwiftUI

/// What was written, by whom, when.
struct AuditRow: View {
    let entry: AuditEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.tool)
                    .font(.body.monospaced())
                Spacer()
                if let affected = entry.affected {
                    Text("^[\(affected) row](inflect: true)")
                        .font(.kit(.regular, 14, relativeTo: .subheadline))
                        .foregroundStyle(.secondary)
                }
            }
            Text("\(entry.ts) UTC · \(entry.actor ?? "unknown")")
                .font(.kit(.regular, 14, relativeTo: .subheadline))
                .foregroundStyle(.secondary)
            if let detail = entry.detail {
                Text(detail)
                    .font(.kit(.regular, 14, relativeTo: .subheadline))
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
