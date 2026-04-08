import Foundation
import Sparkle
import Combine

final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false

    let updater: SPUUpdater
    private var cancellable: AnyCancellable?

    init() {
        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        self.updater = controller.updater

        cancellable = updater.publisher(for: \.canCheckForUpdates)
            .assign(to: \.canCheckForUpdates, on: self)
    }

    func checkForUpdates() {
        updater.checkForUpdates()
    }
}
