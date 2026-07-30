import AppKit
import ServiceManagement
import WidgetKit

final class AppDelegate: NSObject, NSApplicationDelegate, @unchecked Sendable {

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Pre-warm: register the TCC app-group permission once at launch.
        // ⚠️  DO NOT REMOVE — see docs/adr/0003-prewarm-appgroup-at-launch.md
        // macOS grants the permission to whichever process first touches the App Group UserDefaults.
        // Without this read, the widget extension is the first requester on every toggle, which
        // causes the "SleepLock.app would like to access data from other apps" dialog to reappear
        // on every toggle even after the user clicks "Allow".
        _ = Constant.appGroupDefaults.bool(forKey: Constant.stateKey)

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

        // Bootstrap from the state file, not App Group UserDefaults.
        //
        // The state file at /Library/Application Support/ is written exclusively
        // by this non-sandboxed process and survives restarts, making it the most
        // reliable on-disk record of desired state.  App Group UserDefaults
        // may be empty on a fresh install before the first setDisableSleep() call.
        //
        // setDisableSleep() writes BOTH the launchd state file AND the App Group
        // container file (for the widget's currentValue()), so both are in sync
        // from boot onward.
        let bootState = (try? String(contentsOfFile: Constant.stateFilePath, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)) == "1"
        setDisableSleep(bootState)

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
        // Do NOT write "0" here. The state file encodes desired state, not app
        // presence. Writing "0" on every exit causes permanent lock loss when
        // launchd doesn't restart us (KeepAlive/SuccessfulExit=false means clean
        // exits are not restarted).
    }

    private func setDisableSleep(_ disable: Bool) {
        // 1. Write the state file.
        //    This is the launchd WatchPaths trigger: any write fires the privileged
        //    helper that runs `pmset -a disablesleep`. Only the non-sandboxed main
        //    app can write here; the sandboxed widget extension cannot.
        let value = disable ? "1" : "0"
        do {
            try value.write(toFile: Constant.stateFilePath, atomically: true, encoding: .utf8)
            NSLog("SleepLock: wrote state=%@ to %@", value, Constant.stateFilePath)
        } catch {
            NSLog("SleepLock: failed to write state file: %@", error.localizedDescription)
        }

        // 2. Write to App Group UserDefaults for the widget.
        //    The binary must carry a real TeamIdentifier (Apple Development cert) so
        //    cfprefsd backs this with a shared store. The cached singleton ensures the
        //    TCC grant is reused rather than re-requested on every access. See ADR-0001.
        Constant.appGroupDefaults.set(disable, forKey: Constant.stateKey)
        NSLog("SleepLock: wrote state=%@ to UserDefaults", value)

        // 3. Tell the widget to refresh.
        //    Triggers currentValue() on SleepLockValueProvider, which reads the
        //    UserDefaults value written above — guaranteed in sync.
        ControlCenter.shared.reloadControls(ofKind: Constant.controlKind)
    }

}
