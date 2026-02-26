import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Services.Power
import qs.Widgets

ColumnLayout {
  id: root

  spacing: Style.marginL
  Layout.fillWidth: true

  NBox {
    Layout.fillWidth: true
    Layout.preferredHeight: headerRow.implicitHeight + Style.margin2M

    RowLayout {
      id: headerRow
      anchors.fill: parent
      anchors.margins: Style.marginM
      spacing: Style.marginM

      NIcon {
        icon: IdleInhibitorService.activeInhibitors.includes("manual") ? "keep-awake-on" : "keep-awake-off"
        pointSize: Style.fontSizeXXL
        color: IdleInhibitorService.activeInhibitors.includes("manual") ? Color.mPrimary : Color.mOnSurfaceVariant
      }

      NLabel {
        label: I18n.tr("tooltips.keep-awake")
        Layout.fillWidth: true
      }

      NToggle {
        checked: IdleInhibitorService.activeInhibitors.includes("manual")
        onToggled: checked => IdleInhibitorService.manualToggle("manual")
        baseSize: Style.baseWidgetSize * 0.65
      }
    }
  }

  NTextInput {
    Layout.fillWidth: true
    label: I18n.tr("panels.session-menu.keep-awake-intervals-label")
    description: I18n.tr("panels.session-menu.keep-awake-intervals-description")
    placeholderText: "5, 15, 30, 60, 120, 240"

    text: {
      if (!Settings.isLoaded || !Settings.data.sessionMenu)
        return "";
      var intervals = Settings.data.sessionMenu.keepAwakeIntervals;
      var mins = [];
      if (intervals) {
        for (var i = 0; i < intervals.length; i++) {
          mins.push(Math.round(intervals[i] / 60));
        }
      }
      return mins.join(", ");
    }

    onAccepted: {
      if (!Settings.data.sessionMenu)
        return;

      var parts = text.split(/[\s,]+/);
      var newIntervals = [];
      for (var i = 0; i < parts.length; i++) {
        var val = parseInt(parts[i].trim());
        if (!isNaN(val) && val > 0)
          newIntervals.push(val * 60);
      }
      // Sort intervals and remove duplicates
      newIntervals = Array.from(new Set(newIntervals)).sort((a, b) => a - b);

      if (newIntervals.length > 0)
        Settings.data.sessionMenu.keepAwakeIntervals = newIntervals;
    }
  }

  Item {
    Layout.fillHeight: true
  }
}
