import SwiftUI

struct ConsoleView: View {
    @Environment(AppModel.self) private var model
    @State private var input = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    List(model.console) { line in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("> \(line.sent)")
                                .foregroundStyle(Color.accentColor)
                            Text(line.received)
                                .foregroundStyle(.secondary)
                        }
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                        .id(line.id)
                    }
                    .listStyle(.plain)
                    .onChange(of: model.console.count) {
                        if let last = model.console.last { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
                Divider()
                HStack {
                    TextField("Commande (ATI, 0100…)", text: $input)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                        .submitLabel(.send)
                        .onSubmit(send)
                    Button("Envoyer", systemImage: "paperplane.fill", action: send)
                        .labelStyle(.iconOnly)
                        .frame(minWidth: 44, minHeight: 44)
                        .disabled(!model.isConnected || model.isBusy || input.isEmpty)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
            .navigationTitle("Console")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !model.console.isEmpty, let url = model.consoleFile() {
                    ToolbarItem(placement: .topBarTrailing) {
                        ShareLink(item: url) { Label("Partager le journal", systemImage: "square.and.arrow.up") }
                    }
                }
            }
        }
    }

    private func send() {
        model.sendRaw(input)
        input = ""
    }
}
