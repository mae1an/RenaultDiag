import DiagCore
import SwiftUI

struct DiscoveryView: View {
    @Environment(AppModel.self) private var model

    /// Moving values first: those are the ones worth looking at.
    private var sortedValues: [ECUValue] {
        model.explorerValues.sorted { $0.changingBytes > $1.changingBytes }
    }

    var body: some View {
        List {
            searchSection
            if !model.explorerValues.isEmpty {
                watchSection
                Section("\(model.explorerValues.count) valeur(s) trouvée(s)") {
                    ForEach(sortedValues) { ValueRow(value: $0) }
                }
            }
        }
        .navigationTitle("Valeurs Renault")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !model.explorerValues.isEmpty, !model.isBusy, let url = model.explorerFile() {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: url) { Label("Partager les résultats", systemImage: "square.and.arrow.up") }
                }
            }
        }
    }

    @ViewBuilder
    private var searchSection: some View {
        Section {
            if let progress = model.explorerProgress {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
                    Text("\(progress.done) sur \(progress.total), \(model.explorerValues.count) trouvée(s)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Button("Arrêter", role: .cancel) { model.stopExplorer() }
            } else {
                Button {
                    model.startExplorerSearch()
                } label: {
                    Label("Lancer la recherche", systemImage: "magnifyingglass")
                }
                .disabled(model.isBusy)
            }
        } header: {
            Text("1. Trouver les valeurs")
        } footer: {
            Text("Voiture à l'arrêt, contact mis, moteur coupé, iPhone en charge. Compte plusieurs minutes. L'app ne fait que lire : elle n'envoie aucune commande d'écriture.")
        }
    }

    private var watchSection: some View {
        Section {
            if model.isWatching {
                Label("\(model.explorerRounds) relevés enregistrés", systemImage: "waveform.path.ecg")
                Button("Arrêter", role: .cancel) { model.stopExplorer() }
            } else {
                Button {
                    model.startExplorerWatch()
                } label: {
                    Label("Surveiller les valeurs", systemImage: "play.circle")
                }
                .disabled(model.isBusy)
            }
        } header: {
            Text("2. Voir ce qui bouge")
        } footer: {
            Text("Voiture à l'arrêt, frein de parking serré, au point mort. Démarre d'abord le moteur, puis touche Surveiller et fais quelques accélérations courtes. Touche Arrêter, puis partage les résultats avec le bouton en haut.")
        }
    }
}

private struct ValueRow: View {
    let value: ECUValue

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(value.id)
                    .font(.headline)
                    .monospaced()
                Spacer()
                if value.changingBytes > 0 {
                    Label("Bouge", systemImage: "waveform.path")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.green)
                }
            }
            Text(hexString(value.latest))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
    }
}
