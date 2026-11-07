import Charts
import DiagCore
import SwiftUI

enum PowerMethod: String, Codable {
    case torque
    case acceleration

    var title: String {
        switch self {
        case .torque: return "Couple moteur"
        case .acceleration: return "Accélération, à la roue"
        }
    }
}

struct PowerPoint: Identifiable {
    let id = UUID()
    let rpm: Double
    let horsepower: Double
}

struct PowerRun: Identifiable, Codable {
    var id = UUID()
    var date: Date
    var method: PowerMethod
    var maxHP: Double
    var rpmAtMax: Double
    var massKg: Double?
}

struct PowerView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.isPowerRunning ? "En direct" : "Puissance max")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(headline.map { String(format: "%.0f", $0) } ?? "–")
                            .font(.system(size: 64, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        Text("ch").font(.title2).foregroundStyle(.secondary)
                    }
                    if let best = model.powerPoints.max(by: { $0.horsepower < $1.horsepower }) {
                        Text(String(format: "Max %.0f ch à %.0f tr/min", best.horsepower, best.rpm))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)

                if !model.powerPoints.isEmpty {
                    Chart(model.powerPoints) { point in
                        PointMark(x: .value("Régime", point.rpm), y: .value("Puissance", point.horsepower))
                            .symbolSize(16)
                    }
                    .chartXAxisLabel("tr/min")
                    .chartYAxisLabel("ch")
                    .frame(height: 200)
                }

                if model.isPowerRunning {
                    Button("Arrêter", systemImage: "stop.circle.fill", role: .destructive) { model.stopPowerRun() }
                } else {
                    Button("Démarrer l'enregistrement", systemImage: "record.circle") { model.startPowerRun() }
                        .disabled(model.isBusy)
                }
            } footer: {
                Text("Uniquement là où c'est autorisé et sans danger, sans dépasser la limitation. Ne regarde pas l'écran en accélérant : l'app enregistre, tu lis le résultat une fois arrêté.")
            }

            Section {
                LabeledContent("Méthode", value: model.availablePowerMethod.title)
                if model.availablePowerMethod == .acceleration {
                    Stepper(value: $model.vehicleMassKg, in: 1000...3000, step: 25) {
                        LabeledContent("Poids avec passagers", value: "\(Int(model.vehicleMassKg)) kg")
                    }
                    .disabled(model.isPowerRunning)
                }
            } footer: {
                Text(methodNote)
            }

            if !model.powerRuns.isEmpty {
                Section("Essais précédents") {
                    ForEach(model.powerRuns) { run in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(String(format: "%.0f ch à %.0f tr/min", run.maxHP, run.rpmAtMax))
                                Text(run.date.formatted(date: .abbreviated, time: .shortened) + " · " + run.method.title)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Puissance")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { model.stopPowerRun() }
    }

    private var headline: Double? {
        model.isPowerRunning ? model.currentHP : model.bestHP
    }

    private var methodNote: String {
        switch model.availablePowerMethod {
        case .torque:
            return "Calculé avec le couple que le calculateur moteur annonce. Ce n'est pas un passage au banc, mais c'est la méthode la plus fiable ici."
        case .acceleration:
            return "Ta voiture ne donne pas son couple : la puissance est estimée à la roue à partir de l'accélération. Elle est plus basse que la puissance moteur, à cause des pertes de transmission. Sur route plate, en 2e ou 3e, du bas au haut du compte-tours."
        }
    }
}
