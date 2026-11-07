import Charts
import DiagCore
import SwiftUI

struct LiveView: View {
    @Environment(AppModel.self) private var model
    @State private var isPickerShown = false

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 12, alignment: .top)]

    var body: some View {
        NavigationStack {
            Group {
                if model.isConnected {
                    dashboard
                } else {
                    NotConnectedView()
                }
            }
            .navigationTitle("Direct")
            .toolbar {
                if model.isConnected {
                    ToolbarItem(placement: .topBarLeading) { recordButton }
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink {
                            PowerView()
                        } label: {
                            Label("Puissance", systemImage: "bolt.fill")
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Mesures", systemImage: "slider.horizontal.3") { isPickerShown = true }
                    }
                }
            }
            .sheet(isPresented: $isPickerShown) { PIDPicker() }
            .onAppear { model.startLive() }
            .onDisappear { model.stopLive() }
            .onChange(of: model.isConnected) { _, connected in
                if connected { model.startLive() }
            }
        }
    }

    private var dashboard: some View {
        ScrollView {
            if model.isBusy {
                Label("Diagnostic en cours, mesures en pause.", systemImage: "pause.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(shownPIDs) { pid in
                    NavigationLink {
                        PIDDetailView(pid: pid)
                    } label: {
                        PIDTile(pid: pid)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)

            HStack {
                Text(String(format: "%.0f lectures par seconde", model.requestsPerSecond))
                if let url = model.recordedCSV {
                    Spacer()
                    ShareLink("Exporter l'enregistrement", item: url)
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
        }
        .background(Color(.systemGroupedBackground))
    }

    private var recordButton: some View {
        Button {
            model.toggleRecording()
        } label: {
            Label(model.isRecording ? "Arrêter" : "Enregistrer", systemImage: model.isRecording ? "stop.circle.fill" : "record.circle")
                .foregroundStyle(model.isRecording ? .red : Color.accentColor)
        }
    }

    private var shownPIDs: [PID] {
        model.selectedPIDs.compactMap(PIDCatalog.pid).filter { model.supportedPIDs.contains($0.request) }
    }
}

private struct PIDTile: View {
    @Environment(AppModel.self) private var model
    let pid: PID

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(pid.name)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2, reservesSpace: true)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(model.values[pid.id].map(formatted) ?? "–")
                    .font(.system(.title, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(pid.unit)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Chart(model.history[pid.id] ?? []) { sample in
                LineMark(x: .value("Temps", sample.time), y: .value(pid.name, sample.value))
                    .interpolationMethod(.monotone)
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: .automatic(includesZero: false))
            .frame(height: 36)
            .accessibilityHidden(true)
            if let label = model.stuckLabel(for: pid) {
                Label(label, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.orange)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private struct PIDDetailView: View {
    @Environment(AppModel.self) private var model
    let pid: PID

    private var samples: [Sample] { model.history[pid.id] ?? [] }

    var body: some View {
        List {
            Section {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(model.values[pid.id].map(formatted) ?? "–")
                        .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                    Text(pid.unit).foregroundStyle(.secondary)
                }
                Chart(samples) { sample in
                    LineMark(x: .value("Temps", sample.time), y: .value(pid.name, sample.value))
                        .interpolationMethod(.monotone)
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 220)
            }
            if let label = model.stuckLabel(for: pid) {
                Section {
                    Label(label, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                } footer: {
                    Text("Moteur coupé, c'est normal. Démarre le moteur et accélère un peu : un capteur qui fonctionne doit bouger.")
                }
            }
            if let low = samples.map(\.value).min(), let high = samples.map(\.value).max() {
                Section("Sur la période affichée") {
                    LabeledContent("Minimum", value: "\(formatted(low)) \(pid.unit)")
                    LabeledContent("Maximum", value: "\(formatted(high)) \(pid.unit)")
                }
            }
        }
        .navigationTitle(pid.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PIDPicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(PID.Group.allCases, id: \.self) { group in
                    // Exhaust sensors stay listed when missing, so their absence is visible.
                    let pids = PIDCatalog.all.filter { $0.group == group && (group == .exhaust || model.supportedPIDs.contains($0.request)) }
                    if !pids.isEmpty {
                        Section {
                            ForEach(pids) { pid in
                                let isSupported = model.supportedPIDs.contains(pid.request)
                                Button {
                                    model.togglePID(pid.id)
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text(pid.name).foregroundStyle(isSupported ? .primary : .secondary)
                                            if !isSupported {
                                                Text("Non fournie en OBD par cette voiture")
                                                    .font(.footnote)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        Spacer()
                                        if model.selectedPIDs.contains(pid.id) {
                                            Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                                        }
                                    }
                                }
                                .disabled(!isSupported)
                                .accessibilityAddTraits(model.selectedPIDs.contains(pid.id) ? .isSelected : [])
                            }
                        } header: {
                            Text(group.rawValue)
                        } footer: {
                            if group == .exhaust {
                                Text("Une mesure qui reste à « – » veut dire que la voiture n'a pas ce capteur ou ne le fournit pas en OBD.")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Mesures affichées")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
        }
    }
}
