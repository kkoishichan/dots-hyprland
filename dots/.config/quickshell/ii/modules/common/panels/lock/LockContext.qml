import qs
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam

Scope {
    id: root

    enum ActionEnum { Unlock, Poweroff, Reboot }

    signal shouldReFocus()
    signal unlocked(targetAction: var)
    signal failed()

    // These properties are in the context and not individual lock surfaces
    // so all surfaces can share the same state.
    property string currentText: ""
    property bool unlockInProgress: false
    property bool showFailure: false
    property bool fingerprintsConfigured: false
    property bool sleepInProgress: false
    property var targetAction: LockContext.ActionEnum.Unlock
    property bool alsoInhibitIdle: false

    function resetTargetAction() {
        root.targetAction = LockContext.ActionEnum.Unlock;
    }

    function clearText() {
        root.currentText = "";
    }

    function resetClearTimer() {
        passwordClearTimer.restart();
    }

    function reset(stopFingerprint = true) {
        root.resetTargetAction();
        root.clearText();
        root.unlockInProgress = false;
        if (stopFingerprint) {
            fingerprintRetryTimer.stop();
            stopFingerPam();
        }
    }

    Timer {
        id: passwordClearTimer
        interval: 10000
        onTriggered: {
            // Clearing stale password input must not stop fingerprint scanning.
            root.reset(false);
        }
    }

    Timer {
        id: fingerprintRetryTimer
        interval: 2000
        repeat: false
        onTriggered: root.tryFingerUnlock()
    }

    onCurrentTextChanged: {
        if (currentText.length > 0) {
            showFailure = false;
            GlobalStates.screenUnlockFailed = false;
        }
        GlobalStates.screenLockContainsCharacters = currentText.length > 0;
        passwordClearTimer.restart();
    }

    function tryUnlock(alsoInhibitIdle = false) {
        root.alsoInhibitIdle = alsoInhibitIdle;
        root.unlockInProgress = true;
        pam.start();
    }

    function tryFingerUnlock() {
        if (!root.sleepInProgress && GlobalStates.screenLocked && root.fingerprintsConfigured
                && !fingerPam.active) {
            fingerPam.start();
        }
    }

    onSleepInProgressChanged: {
        if (root.sleepInProgress) {
            // fprintd must stop before sleep.target. Do not activate it again
            // while systemd is stopping it, including from a pending PAM retry.
            fingerprintRetryTimer.stop();
            stopFingerPam();
        } else if (GlobalStates.screenLocked && root.fingerprintsConfigured) {
            fingerprintRetryTimer.restart();
        }
    }

    onFingerprintsConfiguredChanged: {
        if (!root.sleepInProgress && root.fingerprintsConfigured && GlobalStates.screenLocked) {
            fingerprintRetryTimer.restart();
        }
    }

    function stopFingerPam() {
        if (fingerPam.active) {
            fingerPam.abort();
        }
    }

    Process {
        id: fingerprintCheckProc
        running: true
        command: ["bash", "-c", "fprintd-list $(whoami)"]
        stdout: StdioCollector {
            id: fingerprintOutputCollector
            onStreamFinished: {
                root.fingerprintsConfigured = fingerprintOutputCollector.text.includes("Fingerprints for user");
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                // console.warn("[LockContext] fprintd-list command exited with error:", exitCode, exitStatus);
                root.fingerprintsConfigured = false;
            }
        }
    }
    
    PamContext {
        id: pam

        // Keep password authentication separate from /etc/pam.d/login, which
        // also invokes pam_fprintd on this machine.
        configDirectory: "pam"
        config: "password.conf"

        // pam_unix will ask for a response for the password prompt
        onPamMessage: {
            if (this.responseRequired) {
                this.respond(root.currentText);
            }
        }

        // pam_unix won't send any important messages so all we need is the completion status.
        onCompleted: result => {
            if (result == PamResult.Success) {
                root.unlocked(root.targetAction);
                stopFingerPam();
            } else {
                root.clearText();
                root.unlockInProgress = false;
                GlobalStates.screenUnlockFailed = true;
                root.showFailure = true;
            }
        }
    }

    PamContext {
        id: fingerPam

        configDirectory: "pam"
        config: "fprintd.conf"

        onCompleted: result => {
            if (root.sleepInProgress) return;
            if (result == PamResult.Success && GlobalStates.screenLocked) {
                fingerprintRetryTimer.stop();
                root.unlocked(root.targetAction);
                stopFingerPam();
            } else if (GlobalStates.screenLocked) {
                // Retry after timeouts, mismatches, max tries, and device errors.
                fingerprintRetryTimer.restart();
            }
        }
    }
}
