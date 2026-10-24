import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Bar entry for raul.chess: a knight that opens and closes the board.
// The board itself is the plugin's panel; this only routes the click
// through the shell so the shortcut and the bar share one open state.
BarWidget {
  id: root
  moduleName: Model.PLUGIN_ID

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function toggle() {
    if (bar && bar.shell && typeof bar.shell.toggle === "function")
      bar.shell.toggle(Model.PLUGIN_ID, "{}")
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: Model.BAR_GLYPH
    tooltipText: "Ajedrez"

    onPressed: function(b) { root.toggle() }
  }
}
