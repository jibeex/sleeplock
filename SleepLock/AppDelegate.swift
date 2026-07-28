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

        // Bootstrap from the state file, not UserDefaults.
        //
        // UserDefaults can be empty after a fresh install, after the sandboxed
        // extension fails to persist a write (ad-hoc signing, no real team ID),
        // or when the group container hasn't been provisioned yet.  The state
        // file is written by this process (non-sandboxed) and survives restarts,
        // so it is the more reliable source of truth on startup.
        //
        // setDisableSleep() writes BOTH the state file AND UserDefaults, so after
        // this call syncIfDrifted() will always have a valid UserDefaults baseline.
        let bootState = (try? String(contentsOfFile: Constant.stateFilePath, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)) == "1"
        setDisableSleep(bootState)

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
        // Do NOT write "0" here. The state file encodes desired state, not app
        // presence. Writing "0" on every exit causes permanent lock loss when
        // launchd doesn't restart us (KeepAlive/SuccessfulExit=false means clean
        // exits are not restarted). On the next launch, applicationDidFinishLaunching
        // restores the correct state from UserDefaults.
    }

    // MARK: - State file

    private func setDisableSleep(_ disable: Bool) {
        // Write UserDefaults first.  The main app is non-sandboxed, so its writes
        // always land in the group container — unlike the sandboxed extension whose
        // UserDefaults writes may be silently redirected with ad-hoc signing.
        // syncIfDrifted() reads UserDefaults as its source of truth, so keeping it
        // in sync here prevents the 30-second timer from resetting state to 0.
        SleepLockState.isSleepDisabled = disable
        SleepLockState.synchronize()

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
