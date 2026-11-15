import SwiftUI

struct SignInView: View {
    @Bindable var model: AppModel

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "car.side.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.tint)
                    .padding(.top, 24)
                    .accessibilityHidden(true)

                VStack(spacing: 8) {
                    Text("My Ford").font(.largeTitle.bold())
                    Text("See your car's fuel, range, doors, tires and location, and lock, unlock or start it from your phone.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                HStack {
                    Text("Region")
                    Spacer()
                    Picker("Region", selection: $model.regionId) {
                        ForEach(FordRegion.all, id: \.id) { Text($0.displayName).tag($0.id) }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                Button { Task { await model.signIn() } } label: {
                    Text("Sign in with Ford").font(.title3.weight(.semibold)).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .disabled(model.isBusy)

                Label("You sign in on Ford's own login page. Your password never reaches this app.", systemImage: "lock.shield")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)

                if !model.errorText.isEmpty {
                    Text(model.errorText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .textSelection(.enabled)
                }
            }
            .padding(24)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Color(.systemGroupedBackground))
    }
}
