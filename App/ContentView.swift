import SwiftUI

@main
struct FordWidgetApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup { ContentView(model: model) }
    }
}

struct ContentView: View {
    @Bindable var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if model.isSignedIn { MainTabs(model: model) } else { SignInView(model: model) }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active { Task { await model.refresh() } }
        }
    }
}

struct MainTabs: View {
    @Bindable var model: AppModel

    var body: some View {
        TabView(selection: $model.selectedTab) {
            Tab("Overview", systemImage: "car", value: AppTab.overview) {
                NavigationStack { OverviewView(model: model) }
            }
            Tab("Location", systemImage: "map", value: AppTab.location) {
                NavigationStack { LocationView(model: model) }
            }
            Tab("Health", systemImage: "stethoscope", value: AppTab.health) {
                NavigationStack { HealthView(model: model) }
            }
            Tab("Vehicle", systemImage: "info.circle", value: AppTab.vehicle) {
                NavigationStack { VehicleView(model: model) }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        #if DEBUG
        // scripts/screens.sh waits for this marker instead of guessing how long a cold launch takes.
        .task {
            guard model.isDemo else { return }
            try? await Task.sleep(for: .seconds(1))
            try? Data().write(to: URL.documentsDirectory.appending(path: "demo/ready"))
        }
        #endif
    }
}

/// Both refresh actions, on every tab. "Refresh" only reads Ford's cloud; "Update from car" wakes the car.
struct CarToolbar: ToolbarContent {
    let model: AppModel
    @State private var confirmingUpdate = false

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button { Task { await model.refresh() } } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(model.isBusy)
            Button { confirmingUpdate = true } label: {
                Label("Update from car", systemImage: "antenna.radiowaves.left.and.right")
            }
            .disabled(model.isBusy)
            .confirmationDialog("Wake the car?", isPresented: $confirmingUpdate, titleVisibility: .visible) {
                if model.updateCooldownRemaining() == 0 {
                    Button("Update from car") { Task { await model.perform(.statusRefresh) } }
                }
            } message: {
                let wait = model.updateCooldownRemaining()
                if wait == 0 {
                    Text("This wakes the car to report fresh data. If it is in power-saving mode, doing this often can drain its 12V battery. Refresh only reads what Ford already has.")
                } else {
                    Text("The car was asked a moment ago. To protect its 12V battery, wait \(Int((wait / 60).rounded(.up))) more min before asking again. Refresh still works.")
                }
            }
        }
    }
}
