import SwiftUI
import SwiftData

@main
struct WhatFunApp: App {
    private let runtime: Result<AppRuntime, Error>

    init() {
        runtime = Result {
            AppRuntime(
                modelContainer: try AppModelContainer.make(),
                services: try AppServices.live()
            )
        }
    }

    var body: some Scene {
        WindowGroup {
            switch runtime {
            case let .success(runtime):
                RootView()
                    .modelContainer(runtime.modelContainer)
                    .environment(runtime.services)
            case let .failure(error):
                StartupFailureView(error: error)
            }
        }
    }
}

private struct AppRuntime {
    let modelContainer: ModelContainer
    let services: AppServices
}

private struct StartupFailureView: View {
    let error: Error

    var body: some View {
        ContentUnavailableView {
            Label("WhatFun couldn’t open", systemImage: "exclamationmark.triangle")
        } description: {
            Text("Your archive was left untouched. Quit and reopen the app; if the problem continues, preserve your WhatFun data before reinstalling.\n\n\(error.localizedDescription)")
        }
        .padding()
        .archiveBackground()
    }
}
