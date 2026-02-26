pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Modules.Panels.Settings
import qs.Services.UI

Singleton {
  id: root

  property bool isInhibited: false
  property string reason: I18n.tr("system.user-requested")
  property var activeInhibitors: []
  // Mapping of inhibitor ID to remaining timeout in seconds
  property var timeouts: ({})

  // True when the native Wayland IdleInhibitor is handling inhibition
  // (set by the IdleInhibitor element in MainScreen via the nativeInhibitor property)
  property bool nativeInhibitorAvailable: false

  // Mode of inhibition:
  // Always prevent both screen turn off and system suspend.
  readonly property string what: "idle:sleep"

  function init() {
    Logger.i("IdleInhibitor", "Service started");
  }

  // Add an inhibitor
  function addInhibitor(id, reason = "Application request") {
    if (activeInhibitors.includes(id)) {
      return false;
    }

    var newInhibitors = activeInhibitors.slice();
    newInhibitors.push(id);
    activeInhibitors = newInhibitors;

    updateInhibition(reason);
    return true;
  }

  // Remove an inhibitor
  function removeInhibitor(id) {
    const index = activeInhibitors.indexOf(id);
    if (index === -1) {
      return false;
    }

    var newInhibitors = activeInhibitors.slice();
    newInhibitors.splice(index, 1);
    activeInhibitors = newInhibitors;

    if (timeouts[id] !== undefined) {
      var newTimeouts = Object.assign({}, timeouts);
      delete newTimeouts[id];
      timeouts = newTimeouts;
    }

    updateInhibition();
    return true;
  }

  // Update the actual system inhibition
  function updateInhibition(newReason = reason) {
    const shouldInhibit = activeInhibitors.length > 0;

    if (shouldInhibit === isInhibited) {
      return;
    }

    if (shouldInhibit) {
      startInhibition(newReason);
    } else {
      stopInhibition();
    }
  }

  // Start system inhibition
  function startInhibition(newReason) {
    reason = newReason;

    if (nativeInhibitorAvailable) {
      // Native IdleInhibitor in MainScreen handles it via isInhibited binding
      Logger.d("IdleInhibitor", "Native inhibitor active");
    } else {
      startSystemdInhibition();
    }

    isInhibited = true;
    Logger.i("IdleInhibitor", "Started inhibition:", reason, "mode:", root.what);
  }

  // Stop system inhibition
  function stopInhibition() {
    if (!isInhibited)
      return;

    isInhibited = false;

    if (!nativeInhibitorAvailable && inhibitorProcess.running) {
      // Gracefully stop by closing stdin (read will exit on EOF)
      inhibitorProcess.stdinEnabled = false;
      // Ensure it exits if stdin close doesn't work or isn't fast enough
      forceStopTimer.start();
    }

    Logger.i("IdleInhibitor", "Stopped inhibition");
  }

  // Systemd inhibition using systemd-inhibit
  function startSystemdInhibition() {
    inhibitorProcess.stdinEnabled = true;
    inhibitorProcess.command = ["systemd-inhibit", "--what=" + root.what, "--why=" + reason, "--mode=block", "sh", "-c", "read _"];
    inhibitorProcess.running = true;
  }

  Timer {
    id: forceStopTimer
    interval: 200
    repeat: false
    onTriggered: {
      if (inhibitorProcess.running) {
        inhibitorProcess.running = false;
      }
    }
  }

  // Helper for manual toggle (usually from UI)
  function manualToggle(id = "manual") {
    if (activeInhibitors.includes(id)) {
      removeManualInhibitor(id);
      return false;
    } else {
      addManualInhibitor(id, null);
      return true;
    }
  }

  function changeTimeout(id, delta) {
    var currentTimeout = timeouts[id];

    if (currentTimeout === undefined && delta < 0) {
      return;
    }

    if (currentTimeout === undefined && delta > 0) {
      addManualInhibitor(id, delta);
      return;
    }

    var newTimeout = currentTimeout + delta;
    if (newTimeout <= 0) {
      removeManualInhibitor(id);
    } else {
      addManualInhibitor(id, newTimeout);
    }
  }

  function addManualInhibitor(id, timeoutSec) {
    if (!activeInhibitors.includes(id)) {
      addInhibitor(id, "Manually activated by user");
      ToastService.showNotice(I18n.tr("tooltips.keep-awake"), I18n.tr("common.enabled"), "keep-awake-on");
    }

    var newTimeouts = Object.assign({}, timeouts);
    if (timeoutSec === null) {
      delete newTimeouts[id];
    } else {
      newTimeouts[id] = timeoutSec;
    }
    timeouts = newTimeouts;

    if (timeoutSec !== null && !inhibitorTimer.running) {
      inhibitorTimer.start();
    }
  }

  function removeManualInhibitor(id) {
    if (activeInhibitors.includes(id)) {
      removeInhibitor(id);
      ToastService.showNotice(I18n.tr("tooltips.keep-awake"), I18n.tr("common.disabled"), "keep-awake-off");
    }
  }

  function getFormattedTooltip(id) {
    const active = activeInhibitors.includes(id);
    const timeout = timeouts[id];

    let base = I18n.tr("tooltips.keep-awake");
    if (!active) {
      return base;
    }

    let mode = I18n.tr("system.inhibit-both");
    let suffix = "";

    if (timeout !== undefined && timeout !== null) {
      suffix = "\n" + I18n.tr("common.remaining", {
                                "time": Time.formatVagueHumanReadableDuration(timeout)
                              });
    }

    return mode + suffix;
  }

  function getMenuModel(id, screen) {
    var m = [];
    m.push({
             "label": I18n.tr("common.indefinitely"),
             "action": "timeout-none",
             "icon": "infinity"
           });

    if (Settings.isLoaded && Settings.data.sessionMenu) {
      var intervals = Settings.data.sessionMenu.keepAwakeIntervals;
      if (intervals && intervals.length > 0) {
        for (var i = 0; i < intervals.length; i++) {
          var secs = intervals[i];
          m.push({
                   "label": Time.formatVagueHumanReadableDuration(secs),
                   "action": "timeout-" + secs,
                   "icon": "clock"
                 });
        }
      }
    }

    m.push({
             "label": I18n.tr("common.settings"),
             "action": "settings",
             "icon": "settings"
           });

    return m;
  }

  function handleMenuAction(action, id, screen, widgetInfo) {
    if (action === "settings") {
      SettingsPanelService.openToTab(SettingsPanel.Tab.SessionMenu, 2, screen);
    } else if (action === "widget-settings") {
      if (widgetInfo) {
        BarService.openWidgetSettings(screen, widgetInfo.section, widgetInfo.sectionWidgetIndex, widgetInfo.widgetId, widgetInfo.widgetSettings);
      }
    } else if (action === "timeout-none") {
      addManualInhibitor(id, null);
    } else if (action.startsWith("timeout-")) {
      var secs = parseInt(action.substring(8));
      addManualInhibitor(id, secs);
    }
  }

  Timer {
    id: inhibitorTimer
    repeat: true
    interval: 1000
    onTriggered: {
      var activeTimeouts = Object.keys(timeouts);
      if (activeTimeouts.length === 0) {
        inhibitorTimer.stop();
        return;
      }

      var newTimeouts = Object.assign({}, timeouts);
      var changed = false;
      var expired = [];

      for (var i = 0; i < activeTimeouts.length; i++) {
        var id = activeTimeouts[i];
        newTimeouts[id] -= 1;
        if (newTimeouts[id] <= 0) {
          delete newTimeouts[id];
          expired.push(id);
        }
        changed = true;
      }

      if (changed) {
        timeouts = newTimeouts;
        for (var j = 0; j < expired.length; j++) {
          removeInhibitor(expired[j]);
        }
      }
    }
  }

  // Process for maintaining the inhibition
  Process {
    id: inhibitorProcess
    running: false
    stdinEnabled: false

    onExited: (exitCode, exitStatus) => {
      forceStopTimer.stop();
      if (isInhibited) {
        Logger.w("IdleInhibitor", "Inhibitor process exited unexpectedly:", exitCode);
        isInhibited = false;
      }
    }

    onStarted: {
      Logger.d("IdleInhibitor", "Inhibitor process started successfully");
    }
  }

  // Clean up on shutdown
  Component.onDestruction: {
    stopInhibition();
  }
}
