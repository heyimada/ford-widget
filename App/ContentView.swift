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
        .onChange(of: scenePhase) { _, phase in
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
            Group {
                if let snapshot = model.snapshot {
                    VehicleCardView(snapshot: snapshot, carImage: model.carImage, now: Date())
                        .padding(16)
                        .frame(height: 170)
                } else {
                    Text("No data yet").foregroundStyle(.secondary).frame(height: 170)
                }
            }
            .frame(maxWidth: .infinity)
            .background(CardStyle.background, in: RoundedRectangle(cornerRadius: 28, style: .continuous))

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
