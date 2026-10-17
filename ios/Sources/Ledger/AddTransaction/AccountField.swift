import SwiftUI

/// An account picker; a text field when the account list couldn't load, since an unknown name
/// simply creates that account on the server.
struct AccountField: View {
    let title: LocalizedStringResource
    @Binding var selection: String
    let accounts: [AccountBalance]

    var body: some View {
        if accounts.isEmpty {
            TextField(text: $selection) {
                Text(title)
            }
            .textInputAutocapitalization(.words)
        } else {
            Picker(selection: $selection) {
                if !accounts.contains(where: { $0.name == selection }) {
                    Text("Choose").tag(selection)
                }
                ForEach(accounts) { account in
                    Text(account.name).tag(account.name)
                }
            } label: {
                Text(title)
            }
        }
    }
}
