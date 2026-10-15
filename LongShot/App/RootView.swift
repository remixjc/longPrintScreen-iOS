import SwiftUI

struct RootView: View {
    @EnvironmentObject private var workspace: WorkspaceModel
    @State private var tab = 0
    var body: some View {
        TabView(selection: $tab) {
            HomeView().tabItem { Label("拼接", systemImage: "rectangle.stack") }.tag(0)
            RecordingView().tabItem { Label("录屏", systemImage: "record.circle") }.tag(1)
            SettingsView().tabItem { Label("我的", systemImage: "person.crop.circle") }.tag(2)
        }
        .toolbarBackground(Theme.background, for: .tabBar)
        .fullScreenCover(isPresented: $workspace.showEditor) { EditorView() }
        .overlay {
            if workspace.busy {
                ZStack {
                    Color.black.opacity(0.45).ignoresSafeArea()
                    VStack(spacing: 16) {
                        ProgressView().tint(Theme.green).scaleEffect(1.2)
                        Text(workspace.progress).font(.subheadline).foregroundStyle(.white)
                    }.padding(28).background(Theme.card, in: RoundedRectangle(cornerRadius: 22))
                }.accessibilityIdentifier("processingOverlay")
            }
        }
        .alert("长卷", isPresented: Binding(get: { workspace.message != nil && !workspace.showEditor },
                                          set: { if !$0 { workspace.message = nil } })) {
            Button("好的") { workspace.message = nil }
        } message: { Text(workspace.message ?? "") }
    }
}
