import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, @unchecked Sendable {

    func applicationDidFinishLaunching(_ notification: Notification) {
        // DistributedNotificationCenter is user-scoped and accepts Swift closures directly,
        // replacing two near-identical CFNotificationCenterAddObserver blocks that required
        // unsafe Unmanaged pointer boilerplate.
        let nc = DistributedNotificationCenter.default()
        nc.addObserver(forName: .init(Constant.notificationDidEnable),  object: nil, queue: .main) { [weak self] _ in
            self?.setDisableSleep(true)
        }
        nc.addObserver(forName: .init(Constant.notificationDidDisable), object: nil, queue: .main) { [weak self] _ in
            self?.setDisableSleep(false)
        }

        // Always sync the state file to UserDefaults on startup.
        // If the app was killed while the lock was active, the widget may have
        // already persisted isSleepDisabled=false to UserDefaults, but the main
        // process never received notificationDidDisable and never wrote "0" to
        // the state file.  The daemon would then hold SleepDisabled=1 forever.
        setDisableSleep(SleepLockState.isSleepDisabled)

        // Log registration failures instead of silently swallowing them.
        do {
            try SMAppService.mainApp.register()
        } catch {
            NSLog("SleepLock: failed to register login item: %@", error.localizedDescription)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        setDisableSleep(false)
    }

    private func setDisableSleep(_ disable: Bool) {
        let value = disable ? "1" : "0"
        do {
            try value.write(toFile: Constant.stateFilePath, atomically: true, encoding: .utf8)
            NSLog("SleepLock: wrote state=%@ to %@", value, Constant.stateFilePath)
        } catch {
            NSLog("SleepLock: failed to write state file: %@", error.localizedDescription)
        }
    }
}
