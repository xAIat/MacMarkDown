import SwiftUI

/// The editor's find/replace bar, shown by Edit > Find and driven by
/// `FindController`.
struct FindBar: View {
    @Bindable var find: FindController
    let onNext: () -> Void
    let onPrevious: () -> Void
    let onReplace: () -> Void
    let onReplaceAll: () -> Void
    let onClose: () -> Void

    @FocusState private var queryFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Find", text: $find.query)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)
                .focused($queryFocused)
                .onSubmit(onNext)

            Text(matchLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(minWidth: 60, alignment: .leading)

            Button { onPrevious() } label: {
                Image(systemName: "chevron.up")
            }
            .help("Find Previous")

            Button { onNext() } label: {
                Image(systemName: "chevron.down")
            }
            .help("Find Next")

            Toggle(isOn: $find.showsReplace) {
                Image(systemName: "arrow.2.squarepath")
            }
            .toggleStyle(.button)
            .help("Replace")

            if find.showsReplace {
                TextField("Replace", text: $find.replacement)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
                Button("Replace") { onReplace() }
                Button("All") { onReplaceAll() }
            }

            Toggle("Match Case", isOn: $find.caseSensitive)
                .toggleStyle(.checkbox)
                .font(.caption)

            Spacer()

            Button { onClose() } label: {
                Image(systemName: "xmark")
            }
            .help("Close Find Bar")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.bar)
        .onAppear { queryFocused = true }
    }

    private var matchLabel: String {
        guard !find.query.isEmpty else { return "" }
        if find.matches.isEmpty { return "No matches" }
        if let index = find.currentIndex {
            return "\(index + 1) of \(find.matches.count)"
        }
        return "\(find.matches.count)"
    }
}