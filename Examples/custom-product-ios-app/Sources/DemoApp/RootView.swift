import SwiftUI

struct RootView: View {
    @Bindable var model: AppModel

    var body: some View {
        TabView(selection: $model.selectedTab) {
            NavigationStack {
                OverviewView(sample: model.sample) {
                    model.presentedSheet = .about
                }
            }
            .tabItem { Label("Overview", systemImage: "shippingbox.fill") }
            .tag(AppModel.Tab.overview)

            NavigationStack {
                SettingsView(notificationsEnabled: $model.notificationsEnabled)
            }
            .tabItem { Label("Settings", systemImage: "gearshape.fill") }
            .tag(AppModel.Tab.settings)
        }
        .sheet(item: $model.presentedSheet) { sheet in
            switch sheet {
            case .about:
                AboutView()
            }
        }
    }
}

private struct OverviewView: View {
    let sample: SampleContent
    let showAbout: () -> Void

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(sample.headline)
                        .font(.title2.bold())
                    Text(sample.summary)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }

            Section("What the demo proves") {
                ForEach(sample.features) { feature in
                    Label {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(feature.title)
                            Text(feature.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: feature.systemImage)
                            .foregroundStyle(.tint)
                    }
                }
            }
        }
        .navigationTitle("SwiftPM IPA")
        .toolbar {
            Button("About", systemImage: "info.circle", action: showAbout)
        }
    }
}

private struct SettingsView: View {
    @Binding var notificationsEnabled: Bool

    var body: some View {
        Form {
            Section("Example capability") {
                Toggle("Demo notifications", isOn: $notificationsEnabled)
                Text("This switch is intentionally local; it keeps the sample focused on packaging.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Build") {
                LabeledContent("Product", value: "IOSDemoIPA")
                LabeledContent("Minimum iOS", value: "17.0")
                LabeledContent("Architecture", value: "arm64")
            }
        }
        .navigationTitle("Settings")
    }
}

private struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Built without an Xcode project",
                systemImage: "hammer.fill",
                description: Text("A custom SwiftPM product builder generated the archive and IPA wrapper.")
            )
            .navigationTitle("About")
            .toolbar {
                Button("Done") { dismiss() }
            }
        }
    }
}
