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
        ScrollView {
            VStack(spacing: 22) {
                if model.isSignedIn { signedIn } else { signedOut }
                if !model.errorText.isEmpty {
                    Text(model.errorText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .textSelection(.enabled)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active { Task { await model.refresh() } }
        }
    }

    private var signedOut: some View {
        VStack(spacing: 22) {
            Text("My Ford").font(.largeTitle)
            Picker("Region", selection: $model.regionId) {
                ForEach(FordRegion.all, id: \.id) { Text($0.displayName).tag($0.id) }
            }
            .pickerStyle(.menu)
            signInButton("Sign in with Ford")
        }
    }

    private var signedIn: some View {
        VStack(spacing: 22) {
            if let snapshot = model.snapshot {
                // Laid out at medium-widget size and scaled up, so the app shows exactly what the widget shows.
                GeometryReader { geo in
                    VehicleCardView(snapshot: snapshot, carImage: model.carImage, now: Date())
                        .padding(16)
                        .frame(width: 338, height: 158)
                        .background(CardStyle.background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .scaleEffect(geo.size.width / 338, anchor: .topLeading)
                }
                .aspectRatio(338 / 158, contentMode: .fit)
            } else {
                Text("No data yet").foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 158)
            }

            Button { Task { await model.refresh() } } label: {
                Text("Refresh").font(.title2).padding(.horizontal, 24)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .disabled(model.isBusy)

            Button("Ask car to refresh") { Task { await model.askCarToRefresh() } }
                .font(.title2)
                .disabled(model.isBusy)

            Button("Sign out", role: .destructive) { model.signOut() }
                .font(.title2)

            if model.needsReauth { signInButton("Sign in again") }
        }
    }

    private func signInButton(_ title: LocalizedStringKey) -> some View {
        Button { Task { await model.signIn() } } label: {
            Text(title).font(.title3).padding(.horizontal, 16)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .disabled(model.isBusy)
    }
}
