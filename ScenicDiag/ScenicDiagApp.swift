import SwiftUI

@main
struct ScenicDiagApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView {
            ConnectionView()
                .tabItem { Label("Connexion", systemImage: "antenna.radiowaves.left.and.right") }
            LiveView()
                .tabItem { Label("Direct", systemImage: "gauge.with.dots.needle.67percent") }
            FaultsView()
                .tabItem { Label("Défauts", systemImage: "exclamationmark.triangle") }
                .badge(model.totalFaults)
            VehicleView()
                .tabItem { Label("Véhicule", systemImage: "car") }
            ConsoleView()
                .tabItem { Label("Console", systemImage: "terminal") }
        }
        .alert("Attention", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

/// Shown on tabs that need the car.
struct NotConnectedView: View {
    var body: some View {
        ContentUnavailableView(
            "Pas de voiture connectée",
            systemImage: "car.side",
            description: Text("Connecte le vLinker depuis l'onglet Connexion, ou essaie le mode démo.")
        )
    }
}
