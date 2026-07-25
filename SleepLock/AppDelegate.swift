import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, @unchecked Sendable {
    // static: this path never varies per instance.
    private static let stateFile = "/Library/Application Support/com.jibeex.sleeplock/state"

    func applicationDidFinishLaunching(_ notification: Notification) {
        // DistributedNotificationCenter is user-scoped and accepts Swift closures directly,
        // replacing two near-identical CFNotificationCenterAddObserver blocks that required
        // unsafe Unmanaged pointer boilerplate.
        let nc = DistributedNotificationCenter.default()
        nc.addObserver(forName: .init(SleepLockState.didEnable),  object: nil, queue: .main) { [weak self] _ in
            self?.setDisableSleep(true)
        }
        nc.addObserver(forName: .init(SleepLockState.didDisable), object: nil, queue: .main) { [weak self] _ in
            self?.setDisableSleep(false)
        }

        if SleepLockState.isSleepDisabled {
            setDisableSleep(true)
        }

        // Log registration failures instead of silently swallowing them.
        do {
            try SMAppService.mainApp.register()
        } catch {
            NSLog("SleepLock: failed to register login item: %@", error.localizedDescription)
        }
    }

    func setDisableSleep(_ disable: Bool) {
        let value = disable ? "1" : "0"
        do {
            try value.write(toFile: Self.stateFile, atomically: true, encoding: .utf8)
            NSLog("SleepLock: wrote state=%@ to %@", value, Self.stateFile)
        } catch {
            NSLog("SleepLock: failed to write state file: %@", error.localizedDescription)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        setDisableSleep(false)
    }
}
