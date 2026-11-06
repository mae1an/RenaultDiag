import DiagCore
import SwiftUI

struct ConnectionView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            List {
                switch model.connection {
                case .connected(let info):
                    connectedSection(info)
                case .connecting(let name):
                    Section {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Connexion à \(name)…")
                        }
                    } footer: {
                        Text("La recherche du protocole de la voiture peut prendre une dizaine de secondes.")
                    }
                case .disconnected:
                    devicesSection
                    demoSection
                    helpSection
                }
            }
            .navigationTitle("Connexion")
            .onAppear { model.startBluetooth() }
        }
    }

    private func connectedSection(_ info: AdapterInfo) -> some View {
        Section {
            Label(model.isDemo ? "Voiture de démo" : "Voiture connectée", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
            LabeledContent("Tension batterie", value: info.voltage)
            LabeledContent("Protocole", value: info.protocolName)
            LabeledContent("Adaptateur", value: info.firmware)
            LabeledContent("Mesures disponibles", value: "\(model.supportedPIDs.count)")
            Button("Déconnecter", role: .destructive) { model.disconnect() }
        }
    }

    private var devicesSection: some View {
        Section {
            if let message = model.bluetoothMessage {
                Label(message, systemImage: "exclamationmark.triangle")
            } else if model.devices.isEmpty {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Recherche du vLinker…")
                }
            }
            ForEach(model.devices) { device in
                Button {
                    model.connect(to: device)
                } label: {
                    HStack {
                        Image(systemName: device.isLikelyAdapter ? "car.fill" : "dot.radiowaves.left.and.right")
                            .foregroundStyle(device.isLikelyAdapter ? Color.accentColor : .secondary)
                            .frame(width: 28)
                        VStack(alignment: .leading) {
                            Text(device.name).foregroundStyle(.primary)
                            if device.isLikelyAdapter {
                                Text("Adaptateur OBD").font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text("\(device.rssi) dBm").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .accessibilityLabel("Se connecter à \(device.name)")
            }
        } header: {
            Text("Appareils à proximité")
        }
    }

    private var demoSection: some View {
        Section {
            Button {
                model.connectDemo()
            } label: {
                Label("Essayer le mode démo", systemImage: "play.circle")
            }
        } footer: {
            Text("Une voiture simulée avec de faux défauts, pour découvrir l'app sans le vLinker.")
        }
    }

    private var helpSection: some View {
        Section("Avant de commencer") {
            Label("Branche le vLinker sur la prise OBD, sous le tableau de bord.", systemImage: "1.circle")
            Label("Mets le contact. Pour effacer, laisse le moteur coupé.", systemImage: "2.circle")
            Label("Ne l'appaire pas dans les Réglages iPhone : choisis « vLinker MC-IOS » ici.", systemImage: "3.circle")
        }
        .font(.subheadline)
    }
}
