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
