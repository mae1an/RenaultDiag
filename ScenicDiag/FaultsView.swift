import DiagCore
import SwiftUI

struct FaultsView: View {
    @Environment(AppModel.self) private var model
    @State private var isClearAllConfirmShown = false

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Group {
                if model.isConnected {
                    list
                } else {
                    NotConnectedView()
                }
            }
            .navigationTitle("Défauts")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        HistoryView()
                    } label: {
                        Label("Historique", systemImage: "clock.arrow.circlepath")
                    }
                }
                if !model.reports.isEmpty, let url = model.reportFile() {
                    ToolbarItem(placement: .topBarTrailing) {
                        ShareLink(item: url) { Label("Partager le rapport", systemImage: "square.and.arrow.up") }
                    }
                }
            }
            .confirmationDialog("Effacer tous les défauts ?", isPresented: $isClearAllConfirmShown, titleVisibility: .visible) {
                Button("Effacer \(model.totalFaults) défaut(s)", role: .destructive) {
                    model.clear(model.reports.filter { !$0.dtcs.isEmpty })
                }
            } message: {
                Text(ClearWarning.general)
            }
        }
    }

    private var list: some View {
        @Bindable var model = model
        return List {
            scanSection
            if model.isDemo {
                Section {
                    Toggle("Moteur tournant (démo)", isOn: $model.demoEngineRunning)
                } footer: {
                    Text("Sur une vraie voiture, l'effacement est refusé tant que le moteur tourne.")
                }
            }
            if !model.reports.isEmpty {
                Section {
                    ForEach(model.reports) { report in
                        NavigationLink {
                            ECUDetailView(reportID: report.id)
                        } label: {
                            ECURow(report: report, outcome: model.outcomes[report.id])
                        }
                    }
                } header: {
                    Text("\(model.reports.count) calculateur(s) trouvé(s)")
                }
                if model.totalFaults > 0 {
                    Section {
                        Button(role: .destructive) {
                            isClearAllConfirmShown = true
                        } label: {
                            Label(model.isClearing ? "Effacement en cours…" : "Tout effacer", systemImage: "trash")
                        }
                        .disabled(model.isBusy)
                    }
                }
            } else if model.hasScanned {
                Section {
                    Label("Aucun calculateur n'a répondu. Vérifie que le contact est mis.", systemImage: "questionmark.circle")
                }
            }
        }
    }

    @ViewBuilder
    private var scanSection: some View {
        Section {
            if let progress = model.scanProgress {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
                    Text("Interrogation : \(progress.name)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Button("Arrêter", role: .cancel) { model.cancelScan() }
            } else {
                Button {
                    model.scan(ecus: RenaultNetwork.allECUs)
                } label: {
                    Label("Scanner tous les calculateurs", systemImage: "magnifyingglass")
                }
                .disabled(model.isBusy)
                Button {
                    model.scan(ecus: RenaultNetwork.mainECUs)
                } label: {
                    Label("Scan rapide (principaux)", systemImage: "hare")
                }
                .disabled(model.isBusy)
                Button {
                    model.scan(ecus: RenaultNetwork.kLineECUs)
                } label: {
                    Label("Scan K-Line (modèles anciens)", systemImage: "cable.connector")
                }
                .disabled(model.isBusy)
            }
        } footer: {
            if model.scanProgress == nil {
                Text("Contact mis. Moteur, ABS, airbag, habitacle, tableau de bord : chaque calculateur est interrogé directement.")
            }
        }
    }
}

enum ClearWarning {
    static let general = "L'effacement retire les défauts de la mémoire, il ne répare rien. Si la panne est toujours là, le voyant reviendra. L'historique est sauvegardé avant d'effacer."
    static let airbag = "Attention : un défaut airbag peut signifier que les airbags ne se déclencheront pas en cas de choc. Si le voyant revient, fais contrôler le système par un professionnel avant de rouler."
    static let brakes = "Attention : un défaut ABS ou ESP touche le freinage. Si le voyant revient, fais contrôler le système avant de rouler."

    static func text(for address: String) -> String {
        switch address {
        case "2C": return airbag + "\n\n" + general
        case "01": return brakes + "\n\n" + general
        default: return general
        }
    }
}

private struct ECURow: View {
    let report: ECUReport
    let outcome: ClearOutcome?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(report.name)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var icon: String {
        if report.readError != nil { return "questionmark.circle" }
        return report.dtcs.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
    }

    private var color: Color {
        if report.readError != nil { return .secondary }
        return report.dtcs.isEmpty ? .green : .orange
    }

    private var subtitle: String {
        if let error = report.readError { return error }
        if report.dtcs.isEmpty { return outcome?.accepted == true ? "Effacé, aucun défaut" : "Aucun défaut" }
        return "\(report.dtcs.count) défaut(s)"
    }
}

private struct ECUDetailView: View {
    @Environment(AppModel.self) private var model
    let reportID: String
    @State private var isConfirmShown = false

    private var report: ECUReport? { model.reports.first { $0.id == reportID } }

    var body: some View {
        Group {
            if let report {
                content(report)
                    .navigationTitle(report.name)
                    .navigationBarTitleDisplayMode(.inline)
                    .confirmationDialog("Effacer les défauts de ce calculateur ?", isPresented: $isConfirmShown, titleVisibility: .visible) {
                        Button("Effacer", role: .destructive) { model.clear([report]) }
                    } message: {
                        Text(ClearWarning.text(for: report.address))
                    }
            }
        }
    }

    private func content(_ report: ECUReport) -> some View {
        List {
            if let outcome = model.outcomes[report.id] {
                Section {
                    Label(outcome.message, systemImage: outcome.accepted && outcome.remaining.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(outcome.accepted && outcome.remaining.isEmpty ? .green : .orange)
                }
            }
            Section("Défauts") {
                if report.dtcs.isEmpty {
                    Text(report.readError ?? "Aucun défaut en mémoire")
                        .foregroundStyle(.secondary)
                }
                ForEach(report.dtcs) { DTCRow(dtc: $0) }
            }
            if !report.dtcs.isEmpty {
                Section {
                    Button(role: .destructive) {
                        isConfirmShown = true
                    } label: {
                        Label(model.isClearing ? "Effacement en cours…" : "Effacer ce calculateur", systemImage: "trash")
                    }
                    .disabled(model.isBusy)
                }
            }
            Section("Calculateur") {
                LabeledContent("Adresse", value: report.address)
                if let identification = report.identification {
                    LabeledContent("Référence", value: identification)
                }
                if let method = report.method {
                    LabeledContent("Lecture", value: method.rawValue)
                }
                LabeledContent("Bus", value: report.isKLine ? "K-Line" : "CAN")
            }
        }
    }
}

struct DTCRow: View {
    let dtc: DTC

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(dtc.code)
                    .font(.headline)
                    .monospaced()
                Spacer()
                if let present = dtc.isPresent {
                    Text(present ? "Présent" : "Mémorisé")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(present ? .red : .secondary)
                }
            }
            Text(dtc.description)
                .font(.subheadline)
            if let failure = dtc.failureDescription {
                Text(failure)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Text("Code brut \(dtc.raw)" + (dtc.status.map { String(format: ", statut %02X", $0) } ?? ""))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

private struct HistoryView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            if model.savedHistory.isEmpty {
                ContentUnavailableView(
                    "Pas encore d'historique",
                    systemImage: "clock",
                    description: Text("Les défauts sont sauvegardés ici juste avant chaque effacement.")
                )
            }
            ForEach(model.savedHistory) { entry in
                Section {
                    ForEach(entry.reports.filter { !$0.dtcs.isEmpty }) { report in
                        Text(report.name).font(.headline)
                        ForEach(report.dtcs) { DTCRow(dtc: $0) }
                    }
                } header: {
                    Text("\(entry.date.formatted(date: .abbreviated, time: .shortened)) · \(entry.title)")
                }
            }
        }
        .navigationTitle("Historique")
        .navigationBarTitleDisplayMode(.inline)
    }
}
