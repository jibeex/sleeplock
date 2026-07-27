import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, @unchecked Sendable {

    // Holds the drift-correction timer alive for the lifetime of the app.
    private var syncTimer: Timer?

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

        // Periodic drift correction — catches the edge case where a distributed
        // notification was delivered but the state file write failed (full disk,
        // permissions), or where the widget updated UserDefaults while the app
        // was briefly suspended and the notification was silently dropped.
        syncTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.syncIfDrifted()
        }

        // Launch-at-login and KeepAlive are managed by the LaunchAgent installed at
        // /Library/LaunchAgents/com.jibeex.sleeplock.app.plist.  launchd restarts
        // this process automatically on crash or OS-initiated kill (e.g. sleep/wake
        // memory pressure) — no SMAppService registration needed here.

        // Upgrade cleanup (pre-v1.0.12): the app used to register itself as a Login
        // Item via SMAppService.mainApp.  The LaunchAgent handles that now.  If the
        // old registration is still present it would launch the app a second time on
        // every login — unregister it silently on first launch after upgrading.
        let legacyService = SMAppService.mainApp
        if legacyService.status == .enabled || legacyService.status == .requiresApproval {
            try? legacyService.unregister()
            NSLog("SleepLock: removed legacy SMAppService login-item registration")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        syncTimer?.invalidate()
        setDisableSleep(false)
    }

    // MARK: - State file

    private func setDisableSleep(_ disable: Bool) {
        let value = disable ? "1" : "0"
        do {
            try value.write(toFile: Constant.stateFilePath, atomically: true, encoding: .utf8)
            NSLog("SleepLock: wrote state=%@ to %@", value, Constant.stateFilePath)
        } catch {
            NSLog("SleepLock: failed to write state file: %@", error.localizedDescription)
        }
    }

    /// Reads the on-disk state file and compares it to UserDefaults.
    /// Re-writes if they differ, bringing the daemon back in sync.
    private func syncIfDrifted() {
        let intended = SleepLockState.isSleepDisabled
        let onDisk = (try? String(contentsOfFile: Constant.stateFilePath, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)) == "1"
        guard intended != onDisk else { return }
        NSLog("SleepLock: drift detected (intended=%d onDisk=%d) — correcting",
              intended ? 1 : 0, onDisk ? 1 : 0)
        setDisableSleep(intended)
    }
}
