import qs
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam
import "../../functions/FingerprintFeedback.js" as FingerprintFeedback

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
    property string fingerprintStatus: ""
    // pam_fprintd's max-tries bounds attempts per lock; only the next lock resets it.
    property bool fingerprintExhausted: false
    readonly property string fingerprintHint: FingerprintFeedback.message(fingerprintExhausted ? "exhausted" : fingerprintStatus)
    readonly property bool fingerprintError: FingerprintFeedback.isError(fingerprintExhausted ? "exhausted" : fingerprintStatus)
    property bool fingerprintAttemptFeedback: false
    property bool fingerprintStopping: false
    // A host can supply system-owned PAM profiles; portable defaults stay local.
    readonly property string pamConfigDirectory: Quickshell.env("II_PAM_CONFIG_DIRECTORY") || "pam"
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
        clearFingerprintFeedback();
        if (stopFingerprint) {
            root.fingerprintExhausted = false;
            fingerprintRetryTimer.stop();
            stopFingerPam();
        }
    }

    function clearFingerprintFeedback() {
        fingerprintFeedbackTimer.stop();
        root.fingerprintStatus = "";
    }

    function showFingerprintFeedback(code) {
        if (!FingerprintFeedback.message(code) || root.sleepInProgress || !GlobalStates.screenLocked) return;
        root.fingerprintAttemptFeedback = true;
        root.fingerprintStatus = code;
        fingerprintFeedbackTimer.restart();
    }

    Timer {
        id: fingerprintFeedbackTimer
        interval: 1000
        onTriggered: root.fingerprintStatus = ""
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
            clearFingerprintFeedback();
            showFailure = false;
            GlobalStates.screenUnlockFailed = false;
        }
        GlobalStates.screenLockContainsCharacters = currentText.length > 0;
        passwordClearTimer.restart();
    }

    function tryUnlock(alsoInhibitIdle = false) {
        clearFingerprintFeedback();
        root.alsoInhibitIdle = alsoInhibitIdle;
        root.unlockInProgress = true;
        pam.start();
    }

    function tryFingerUnlock() {
        if (!root.sleepInProgress && GlobalStates.screenLocked && root.fingerprintsConfigured
                && !root.fingerprintExhausted && !fingerPam.active) {
            root.fingerprintStopping = false;
            root.fingerprintAttemptFeedback = false;
            fingerPam.start();
        }
    }

    onSleepInProgressChanged: {
        if (root.sleepInProgress) {
            clearFingerprintFeedback();
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
        root.fingerprintStopping = true;
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
        configDirectory: root.pamConfigDirectory
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

        configDirectory: root.pamConfigDirectory
        config: "fprintd.conf"

        onPamMessage: {
            if (!root.fingerprintStopping && !this.responseRequired)
                root.showFingerprintFeedback(FingerprintFeedback.fromPamMessage(this.message, this.messageIsError));
        }

        onCompleted: result => {
            if (root.sleepInProgress || root.fingerprintStopping) return;
            if (result == PamResult.Success && GlobalStates.screenLocked) {
                fingerprintRetryTimer.stop();
                root.unlocked(root.targetAction);
                stopFingerPam();
            } else if (result == PamResult.MaxTries || result == PamResult.Failed) {
                // Restarting PAM would reset pam_fprintd's attempt limit.
                if (GlobalStates.screenLocked) root.fingerprintExhausted = true;
            } else if (GlobalStates.screenLocked) {
                if (!root.fingerprintAttemptFeedback) root.showFingerprintFeedback("unavailable");
                // Retry after timeouts and device errors.
                fingerprintRetryTimer.restart();
            }
        }
    }
}
