import SwiftUI

struct VehicleView: View {
    @Bindable var model: AppModel
    @Environment(\.locale) private var locale
    @State private var confirmingSignOut = false

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    var body: some View {
        List {
            header
            details
            freshness
            account
            Section {
                LabeledContent("Version", value: version)
            }
        }
        .refreshable { await model.refresh() }
        .navigationTitle("Vehicle")
        .toolbar { CarToolbar(model: model) }
        .confirmationDialog("Sign out of My Ford?", isPresented: $confirmingSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) { model.signOut() }
        } message: {
            Text("Your car data is removed from this iPhone and the widget.")
        }
    }

    private var header: some View {
        Section {
            VStack(spacing: 8) {
                if let image = model.carImage {
                    image.resizable().scaledToFit().frame(maxHeight: 140)
                } else {
                    Image(systemName: "car.side.fill").font(.system(size: 64)).foregroundStyle(.secondary).frame(height: 100)
                }
                Text(model.profile?.name ?? model.snapshot?.name ?? "Ford").font(.title2.bold())
                if let subtitle {
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)
        }
    }

    private var subtitle: String? {
        guard let profile = model.profile else { return nil }
        return [profile.model, profile.year.map { String($0) }].compactMap { $0 }.joined(separator: " · ")
    }

    private var details: some View {
        Section("Details") {
            row("Model", model.profile?.model)
            row("Year", model.profile?.year.map { String($0) })
            row("Color", model.profile?.color?.capitalized)
            row("License plate", model.profile?.licensePlate)
            row("VIN", (model.profile?.vin ?? model.snapshot?.vin).map(Format.maskedVIN))
            row("Region", model.session.flatMap { FordRegion.byId[$0.regionId]?.displayName })
        }
    }

    private func row(_ title: LocalizedStringKey, _ value: String?) -> some View {
        LabeledContent(title, value: value ?? String(localized: "Unknown"))
    }

    private var freshness: some View {
        Section("Data") {
            LabeledContent("Last update from car") {
                dateText(model.snapshot?.updatedAt)
            }
            LabeledContent("Last fetched") {
                dateText(model.snapshot?.fetchedAt)
            }
        }
    }

    @ViewBuilder private func dateText(_ date: Date?) -> some View {
        if let date {
            VStack(alignment: .trailing) {
                Text(date.formatted(date: .abbreviated, time: .shortened))
                Text(Format.ago(date, locale: locale)).font(.footnote).foregroundStyle(.secondary)
            }
        } else {
            Text("Unknown")
        }
    }

    private var account: some View {
        Section("Account") {
            if model.needsReauth {
                Button("Sign in again") { Task { await model.signIn() } }.disabled(model.isBusy)
            }
            Button("Sign out", role: .destructive) { confirmingSignOut = true }
        }
    }
}
