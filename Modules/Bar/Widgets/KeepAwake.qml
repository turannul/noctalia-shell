import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Modules.Bar.Extras
import qs.Services.Power
import qs.Services.UI
import qs.Widgets

Item {
  id: root

  property ShellScreen screen

  // Widget properties passed from Bar.qml for per-instance settings
  property string widgetId: ""
  property string section: ""
  property int sectionWidgetIndex: -1
  property int sectionWidgetsCount: 0

  property var widgetMetadata: BarWidgetRegistry.widgetMetadata[widgetId]
  // Explicit screenName property ensures reactive binding when screen changes
  readonly property string screenName: screen ? screen.name : ""
  property var widgetSettings: {
    if (section && sectionWidgetIndex >= 0 && screenName) {
      var widgets = Settings.getBarWidgetsForScreen(screenName)[section];
      if (widgets && sectionWidgetIndex < widgets.length) {
        return widgets[sectionWidgetIndex];
      }
    }
    return {};
  }

  readonly property string barPosition: Settings.getBarPositionForScreen(screenName)
  readonly property bool isBarVertical: barPosition === "left" || barPosition === "right"
  readonly property string iconColorKey: widgetSettings.iconColor !== undefined ? widgetSettings.iconColor : widgetMetadata.iconColor
  readonly property string textColorKey: widgetSettings.textColor !== undefined ? widgetSettings.textColor : widgetMetadata.textColor

  implicitWidth: pill.width
  implicitHeight: pill.height

  readonly property string instanceId: "manual"

  BarPill {
    id: pill

    screen: root.screen
    text: {
      var timeout = IdleInhibitorService.timeouts[root.instanceId];
      return timeout == null ? "" : Time.formatVagueHumanReadableDuration(timeout);
    }
    oppositeDirection: BarService.getPillDirection(root)
    customIconColor: Color.resolveColorKeyOptional(root.iconColorKey)
    customTextColor: Color.resolveColorKeyOptional(root.textColorKey)
    icon: IdleInhibitorService.activeInhibitors.includes(root.instanceId) ? "keep-awake-on" : "keep-awake-off"
    tooltipText: IdleInhibitorService.getFormattedTooltip(root.instanceId)
    onClicked: IdleInhibitorService.manualToggle(root.instanceId)
    onRightClicked: {
      PanelService.showContextMenu(contextMenu, pill, screen);
    }
    forceOpen: IdleInhibitorService.timeouts[root.instanceId] !== undefined
    forceClose: IdleInhibitorService.timeouts[root.instanceId] === undefined
    onWheel: function (delta) {
      var sign = delta > 0 ? 1 : -1;
      var currentTimeout = IdleInhibitorService.timeouts[root.instanceId];
      var baseDelta = 60;

      if (currentTimeout === undefined || currentTimeout < 600) {
        baseDelta = 60; // <= 10m, increment at 1m interval
      } else if (currentTimeout >= 600 && currentTimeout < 1800) {
        baseDelta = 300; // >= 10m, increment at 5m interval
      } else if (currentTimeout >= 1800 && currentTimeout < 3600) {
        baseDelta = 600; // >= 30m, increment at 10m interval
      } else if (currentTimeout >= 3600) {
        baseDelta = 1800; // > 1h, increment at 30m interval
      }

      IdleInhibitorService.changeTimeout(root.instanceId, baseDelta * sign);
    }
  }

  NPopupContextMenu {
    id: contextMenu

    model: {
      var m = IdleInhibitorService.getMenuModel(root.instanceId, root.screen);
      m.push({
               "label": I18n.tr("actions.widget-settings"),
               "action": "widget-settings",
               "icon": "settings"
             });
      return m;
    }

    onTriggered: action => {
                   contextMenu.close();
                   PanelService.closeContextMenu(screen);
                   IdleInhibitorService.handleMenuAction(action, root.instanceId, root.screen, {
                                                           "section": section,
                                                           "sectionWidgetIndex": sectionWidgetIndex,
                                                           "widgetId": widgetId,
                                                           "widgetSettings": widgetSettings
                                                         });
                 }
  }
}
