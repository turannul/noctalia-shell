import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Services.Power
import qs.Services.UI
import qs.Widgets

NIconButtonHot {
  id: root

  property string instanceId: "manual"

  icon: IdleInhibitorService.activeInhibitors.includes(instanceId) ? "keep-awake-on" : "keep-awake-off"

  hot: IdleInhibitorService.activeInhibitors.includes(instanceId)
  tooltipText: IdleInhibitorService.getFormattedTooltip(instanceId)
  onClicked: IdleInhibitorService.manualToggle(instanceId)
  onRightClicked: {
    PanelService.showContextMenu(contextMenu, root, screen);
  }

  NPopupContextMenu {
    id: contextMenu

    model: IdleInhibitorService.getMenuModel(instanceId, root.screen)

    onTriggered: action => {
                   contextMenu.close();
                   PanelService.closeContextMenu(screen);
                   IdleInhibitorService.handleMenuAction(action, instanceId, root.screen);
                 }
  }
}
