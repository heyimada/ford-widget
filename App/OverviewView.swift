import SwiftUI

struct OverviewView: View {
    @Bindable var model: AppModel

    var body: some View {
        ArrangementView {
            primary
        } secondary: {
            tiles
        }
        .arrangementViewStyle(.split)
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Overview")
        .toolbar { CarToolbar(model: model) }
    }

    private var primary: some View {
        ScrollView {
            VStack(spacing: 12) {
                if let snapshot = model.snapshot {
                    ScaledCard(snapshot: snapshot, carImage: model.carImage)
                } else {
                    ContentUnavailableView("No data yet", systemImage: "car.side", description: Text("Pull down or tap Refresh to load your car."))
                        .frame(minHeight: 158)
                }
                if model.canLockUnlock || model.canRemoteStart { ActionButtons(model: model) }
                status
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .refreshable { await model.refresh() }
    }

    @ViewBuilder private var status: some View {
        if let phase = model.commandPhases[.statusRefresh] {
            PhaseLine(command: .statusRefresh, phase: phase)
        }
        if !model.errorText.isEmpty {
            Text(model.errorText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
        }
        if model.needsReauth {
            Button { Task { await model.signIn() } } label: {
                Text("Sign in again").font(.title3).padding(.horizontal, 16)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .disabled(model.isBusy)
        }
    }

    private var tiles: some View {
        ScrollView {
            StatusTiles(details: model.snapshot?.details)
                .padding()
        }
        .refreshable { await model.refresh() }
    }
}

/// The widget's card, laid out at medium-widget size and scaled up so the app shows exactly what the widget shows.
struct ScaledCard: View {
    private static let designWidth: CGFloat = 338
    private static let designHeight: CGFloat = 158

    let snapshot: VehicleSnapshot
    let carImage: Image?

    var body: some View {
        GeometryReader { geo in
            VehicleCardView(snapshot: snapshot, carImage: carImage, now: Date())
                .padding(16)
                .frame(width: Self.designWidth, height: Self.designHeight)
                .background(CardStyle.background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .scaleEffect(geo.size.width / Self.designWidth, anchor: .topLeading)
        }
        .aspectRatio(Self.designWidth / Self.designHeight, contentMode: .fit)
        .frame(maxWidth: 560)
    }
}

struct PhaseLine: View {
    let command: CarCommand
    let phase: CommandPhase

    var body: some View {
        HStack(spacing: 8) {
            switch phase {
            case .sending, .waiting: ProgressView()
            case .succeeded: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .failed, .expired: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
            Text(command.phaseText(phase)).font(.callout).foregroundStyle(.secondary)
        }
    }
}

struct ActionButtons: View {
    let model: AppModel

    private var engineIsRunningRemotely: Bool {
        (model.snapshot?.details?.remoteStartEndsAt).map { $0 > Date() } ?? false
    }

    var body: some View {
        VStack(spacing: 10) {
            if model.canLockUnlock {
                HStack(spacing: 10) {
                    button(.lock)
                    button(.unlock)
                }
            }
            if model.canRemoteStart {
                button(engineIsRunningRemotely ? .cancelRemoteStart : .remoteStart)
            }
        }
        .frame(maxWidth: 560)
    }

    private func button(_ command: CarCommand) -> some View {
        let phase = model.commandPhases[command]
        return VStack(spacing: 6) {
            Button { Task { await model.perform(command) } } label: {
                HStack(spacing: 8) {
                    switch phase {
                    case .sending, .waiting: ProgressView()
                    case .succeeded: Image(systemName: "checkmark.circle.fill")
                    default: Image(systemName: command.symbol)
                    }
                    Text(command.buttonTitle(phase))
                }
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 24)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 14))
            .controlSize(.regular)
            .tint(command == .lock || command == .remoteStart ? .accentColor : .gray)
            .disabled(model.isBusy && phase == nil)
            if case .failed(let message) = phase {
                Text(message).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
            } else if phase == .expired {
                Text("The command expired.").font(.footnote).foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

extension CarCommand {
    var symbol: String {
        switch self {
        case .lock: "lock.fill"
        case .unlock: "lock.open.fill"
        case .remoteStart: "engine.combustion.fill"
        case .cancelRemoteStart: "stop.circle.fill"
        case .statusRefresh: "antenna.radiowaves.left.and.right"
        }
    }

    func buttonTitle(_ phase: CommandPhase?) -> LocalizedStringKey {
        switch phase {
        case .sending: return progressive
        case .waiting: return "Waiting for car…"
        case .succeeded: return done
        default: return idle
        }
    }

    func phaseText(_ phase: CommandPhase) -> LocalizedStringKey {
        switch phase {
        case .sending: return progressive
        case .waiting: return "Waiting for car…"
        case .succeeded: return done
        case .failed(let message): return LocalizedStringKey(message)
        case .expired: return "The command expired."
        }
    }

    private var idle: LocalizedStringKey {
        switch self {
        case .lock: "Lock"
        case .unlock: "Unlock"
        case .remoteStart: "Start engine"
        case .cancelRemoteStart: "Stop engine"
        case .statusRefresh: "Update from car"
        }
    }

    private var progressive: LocalizedStringKey {
        switch self {
        case .lock: "Locking…"
        case .unlock: "Unlocking…"
        case .remoteStart: "Starting…"
        case .cancelRemoteStart: "Stopping…"
        case .statusRefresh: "Asking the car…"
        }
    }

    private var done: LocalizedStringKey {
        switch self {
        case .lock: "Locked"
        case .unlock: "Unlocked"
        case .remoteStart: "Started"
        case .cancelRemoteStart: "Stopped"
        case .statusRefresh: "Updated"
        }
    }
}
