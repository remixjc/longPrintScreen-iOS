import SwiftUI

@main
struct LongShotApp: App {
    @StateObject private var workspace = WorkspaceModel()
    @StateObject private var purchases = PurchaseStore()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(workspace)
                .environmentObject(purchases)
                .preferredColorScheme(.dark)
                .tint(Theme.green)
                .onChange(of: phase) { _, value in
                    if value == .active {
                        workspace.scanInbox()
                        Task { await purchases.refreshEntitlements() }
                    }
                }
        }
    }
}
