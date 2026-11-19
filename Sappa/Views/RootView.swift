import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.onboardingDone {
            MainTabView()
        } else {
            OnboardingFlow()
        }
    }
}

struct MainTabView: View {
    @Environment(AppModel.self) private var model
    @State private var showAdd = false

    var body: some View {
        @Bindable var model = model
        let selection = Binding<AppTab>(
            get: { model.tab },
            set: { newValue in
                if newValue == .add { showAdd = true } else { model.tab = newValue }
            }
        )
        TabView(selection: selection) {
            Tab("Home", systemImage: "house.fill", value: AppTab.home) {
                HomeView()
            }
            Tab("Fines", systemImage: "doc.text", value: AppTab.fines) {
                FinesView()
            }
            .badge(model.newFinesCount)
            Tab("Settings", systemImage: "slider.horizontal.3", value: AppTab.settings) {
                SettingsView()
            }
            // The separate round glass "+" to the right of the tab bar.
            Tab("Add vehicle", systemImage: "plus", value: AppTab.add, role: .search) {
                Color.clear
            }
        }
        .sheet(isPresented: $showAdd) {
            NavigationStack {
                AddPlateView(mode: .add) { showAdd = false }
            }
        }
    }
}

struct OnboardingFlow: View {
    @State private var path: [OnboardingStep] = []

    enum OnboardingStep: Hashable { case permissions }

    var body: some View {
        NavigationStack(path: $path) {
            AddPlateView(mode: .onboarding) { path.append(.permissions) }
                .navigationDestination(for: OnboardingStep.self) { _ in PermissionsView() }
        }
    }
}
