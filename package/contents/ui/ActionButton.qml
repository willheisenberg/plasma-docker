import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

PlasmaComponents.ToolButton {
    property string tip: ""

    PlasmaComponents.ToolTip.text: tip
    PlasmaComponents.ToolTip.visible: hovered && tip !== ""
    PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
}
