import DiagCore
import SwiftUI

struct VehicleView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            Group {
                if model.isConnected {
                    list
                } else {
                    NotConnectedView()
                }
            }
            .navigationTitle("Véhicule")
        }
    }

    private var list: some View {
        List {
            Section {
                if let vin = model.vin {
                    LabeledContent("VIN", value: vin)
                }
                if let voltage = model.voltage {
                    LabeledContent("Tension batterie", value: voltage)
                }
                if let status = model.status {
                    LabeledContent("Voyant moteur", value: status.milOn ? "Allumé" : "Éteint")
                    LabeledContent("Défauts moteur OBD", value: "\(status.storedCount)")
                    if let fuel = status.fuelName {
                        LabeledContent("Carburant", value: fuel)
                    }
                }
                Button {
                    model.loadVehicle()
                } label: {
                    if model.isLoadingVehicle {
                        Label("Lecture en cours…", systemImage: "hourglass")
                    } else {
                        Label(model.status == nil ? "Lire les informations" : "Actualiser", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(model.isBusy)
            }

            Section {
                NavigationLink {
                    DiscoveryView()
                } label: {
                    Label("Recherche de valeurs Renault", systemImage: "binoculars")
                }
            } footer: {
                Text("Pour trouver des mesures que l'OBD standard ne donne pas, comme la pression du FAP. Lecture seule.")
            }

            if let status = model.status, !status.monitors.isEmpty {
                Section {
                    ForEach(status.monitors) { monitor in
                        HStack {
                            Text(monitor.name)
                            Spacer()
                            Label(monitor.complete ? "Prêt" : "Pas prêt", systemImage: monitor.complete ? "checkmark.circle.fill" : "clock")
                                .foregroundStyle(monitor.complete ? .green : .orange)
                                .labelStyle(.titleAndIcon)
                                .font(.subheadline)
                        }
                    }
                } header: {
                    Text("Tests antipollution")
                } footer: {
                    Text("Utile avant le contrôle technique. Un effacement remet ces tests à zéro : il faut ensuite rouler pour qu'ils se refassent.")
                }
            }

            if let frame = model.freezeFrame {
                Section {
                    if let cause = frame.cause {
                        LabeledContent("Défaut à l'origine", value: cause)
                    }
                    ForEach(frame.values, id: \.name) { item in
                        LabeledContent(item.name, value: item.value)
                    }
                } header: {
                    Text("Conditions au moment de la panne")
                }
            }

            if !model.pendingDTCs.isEmpty {
                Section("Défauts en attente de confirmation") {
                    ForEach(model.pendingDTCs) { DTCRow(dtc: $0) }
                }
            }
            if !model.permanentDTCs.isEmpty {
                Section {
                    ForEach(model.permanentDTCs) { DTCRow(dtc: $0) }
                } header: {
                    Text("Défauts permanents")
                } footer: {
                    Text("Impossibles à effacer : ils disparaissent seuls une fois la réparation validée par la voiture.")
                }
            }
        }
    }
}
