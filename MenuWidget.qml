import QtQuick
import QtQuick.Layouts
import qs.Commons
import Quickshell
import qs.Ui

// Logo/menu launcher with customizable branding, shipping with the bar
// plugin. Settings live inline on the bar layout entry in shell.json, e.g.:
//   { "id": "skal.bar", "logo": "󰣇", "logoFont": "Symbols Nerd Font" }
//   { "id": "skal.bar", "logoImage": "~/.config/omarchy/logo.png" }
// Settings: logo (text/glyph), logoFont (family), logoColor (#hex),
// logoSize (px), logoImage (path — shown instead of text).
// Left-click opens the quick action panel; right-click the Omarchy menu;
// middle-click a terminal. The panel's IPC target is skal.bar.controls.
BarWidget {
  id: root

  property string logoText: String(setting("logo", "\ue900"))
  property string logoFont: String(setting("logoFont", "omarchy"))
  property string logoColor: String(setting("logoColor", ""))
  property string logoImage: String(setting("logoImage", ""))
  property real logoPixelSize: Math.max(8, Number(setting("logoSize", 12)) || 12)
  property string logoMode: String(setting("logoMode", "glyph")) === "image" ? "image" : "glyph"
  // logoColor accepts theme tokens (accent/foreground/urgent/muted/background)
  // resolved live through the Color singleton so the logo follows theme
  // changes, or a literal #rrggbb for full manual control.
  readonly property color resolvedLogoColor: {
    var token = root.logoColor
    if (token === "accent") return Color.accent
    if (token === "foreground") return Color.foreground
    if (token === "urgent") return Color.urgent
    if (token === "muted") return Color.muted
    if (token === "background") return Color.background
    if (/^#[0-9A-Fa-f]{6}$/.test(token)) return token
    return Color.foreground
  }
  readonly property bool useImage: logoMode === "image"

  // Live services backing the indicator controls.
  readonly property var notificationsService: bar && bar.shell ? bar.shell.firstPartyServiceFor("omarchy.notifications") : null
  readonly property var nightlightService: bar && bar.shell ? bar.shell.firstPartyServiceFor("omarchy.nightlight") : null
  readonly property var idleService: bar && bar.shell ? bar.shell.firstPartyServiceFor("omarchy.idle") : null

  // The dropdown lives in a Panel so the bar's popup machinery (tab order,
  // one-popout-at-a-time, summon) applies, with its own IPC target for the
  // hotkey. The widget root proxies open/close so the bar can address it.
  function open() { controlsPanel.open() }
  function close() { controlsPanel.close() }
  function toggleControls() { controlsPanel.opened ? controlsPanel.close() : controlsPanel.open() }
  readonly property bool opened: controlsPanel.opened
  readonly property url logoSource: {
    if (!logoImage) return ""
    var path = logoImage
    if (path.indexOf("~/") === 0) path = Quickshell.env("HOME") + path.substring(1)
    return "file://" + path
  }

  implicitWidth: root.useImage && root.logoSource.toString() !== ""
    ? logoImageItem.width + Style.space(9)
    : (root.styledText ? styledLabel.implicitWidth + Style.space(15) : button.implicitWidth)
  implicitHeight: button.implicitHeight

  readonly property bool styledText: String(setting("logoWeight", "normal")) === "bold"
    || String(setting("logoStyle", "normal")) === "italic"

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // Styled glyphs render through the sibling below (WidgetButton's label
    // supports neither bold nor italic); plain ones use the stock label.
    text: (root.useImage && root.logoSource.toString() !== "") || root.styledText ? "" : root.logoText
    fontFamily: root.logoFont
    fontSize: root.logoPixelSize
    foreground: root.resolvedLogoColor
    horizontalMargin: 7.5
    keepSpace: true

    onPressed: function(button) {
      if (!root.bar) return
      if (button === Qt.RightButton) root.bar.run("omarchy-shell shell toggle omarchy.menu '{\"menu\":\"root\"}'")
      else if (button === Qt.MiddleButton) root.bar.run("xdg-terminal-exec")
      else root.toggleControls()
    }
  }

  Text {
    id: styledLabel
    visible: !root.useImage && root.styledText
    anchors.centerIn: parent
    text: root.logoText
    color: root.resolvedLogoColor
    font.family: root.logoFont
    font.pixelSize: root.logoPixelSize
    font.bold: String(setting("logoWeight", "normal")) === "bold"
    font.italic: String(setting("logoStyle", "normal")) === "italic"
    renderType: Text.NativeRendering
  }

  // Sibling, not child: a textless WidgetButton forces its whole subtree to
  // opacity zero, which would swallow the image. The effective source is a
  // tinted copy of the SVG (fills rewritten by the settings panel into
  // ~/.cache/skal-bar) when a color is set; otherwise the original.
  readonly property url effectiveLogoSource: {
    // The tinted copy's presence is the gate: the foreground default clears
    // logoColor but still tints, so keying on logoColor would skip it.
    var tinted = root.logoImage !== "" ? String(setting("logoImageTinted", "")) : ""
    if (tinted !== "") {
      if (tinted.indexOf("~/") === 0) tinted = Quickshell.env("HOME") + tinted.substring(1)
      return "file://" + tinted
    }
    return root.logoSource
  }

  Item {
    id: logoImageItem
    visible: root.useImage && root.logoSource.toString() !== ""
    anchors.centerIn: parent
    width: Math.min(parent.height - Style.space(2), root.logoPixelSize * 1.8)
    height: width

    Image {
      anchors.fill: parent
      source: logoImageItem.visible ? root.effectiveLogoSource : ""
      sourceSize: Qt.size(96, 96)
      fillMode: Image.PreserveAspectFit
      smooth: true
      mipmap: true
    }
  }

  Panel {
    id: controlsPanel
    bar: root.bar
    moduleName: "skal.bar.controls"
    ipcTarget: "skal.bar.controls"

    property int cursorIndex: 0
    readonly property var rowCount: 4
    onOpenedChanged: {
      cursorIndex = 0
      if (opened) controlsKeyCatcher.forceActiveFocus()
    }

    function activateRow(index) {
      if (index === 0) {
        if (root.notificationsService) root.notificationsService.setDoNotDisturb(!root.notificationsService.doNotDisturb)
      } else if (index === 1) {
        if (root.nightlightService) root.nightlightService.setNightlight(!root.nightlightService.enabled)
      } else if (index === 2) {
        if (root.idleService) root.idleService.setIdleEnabled(root.idleService.stayAwake)
      } else if (index === 3) {
        if (root.bar) root.bar.run("voxtype record toggle")
      }
    }

    PopupCard {
      id: controlsCard
      anchorItem: root
      bar: root.bar
      owner: controlsPanel
      open: controlsPanel.opened
      triggerMode: "click"
      // The kit card never asks for keyboard focus; grabFocus is the
      // PopupWindow keyboard mechanism — without it no keys reach the popup.
      grabFocus: controlsPanel.opened
      contentWidth: Style.space(150)
      contentHeight: Style.space(146)

      Item {
        id: controlsKeyCatcher
        anchors.fill: parent
        focus: controlsPanel.opened

        Keys.onEscapePressed: controlsPanel.close()
        // 2x2 grid navigation: sideways steps one, vertical steps a row.
        Keys.onLeftPressed: {
          controlsPanel.cursorIndex = (controlsPanel.cursorIndex + 3) % 4
          event.accepted = true
        }
        Keys.onRightPressed: {
          controlsPanel.cursorIndex = (controlsPanel.cursorIndex + 1) % 4
          event.accepted = true
        }
        Keys.onUpPressed: {
          controlsPanel.cursorIndex = (controlsPanel.cursorIndex + 2) % 4
          event.accepted = true
        }
        Keys.onDownPressed: {
          controlsPanel.cursorIndex = (controlsPanel.cursorIndex + 2) % 4
          event.accepted = true
        }
        Keys.onReturnPressed: {
          controlsPanel.activateRow(controlsPanel.cursorIndex)
          event.accepted = true
        }
        Keys.onSpacePressed: {
          controlsPanel.activateRow(controlsPanel.cursorIndex)
          event.accepted = true
        }

        GridLayout {
          id: controlsGrid
          // Natural size, dead-centered: slack splits evenly on every side,
          // so the margins read even regardless of the card's frame metrics.
          anchors.centerIn: parent
          columns: 2
          rowSpacing: Style.space(6)
          columnSpacing: Style.space(6)

          ControlTile {
            glyph: "󰂛"
            name: "Silence Notifications"
            active: root.notificationsService ? root.notificationsService.doNotDisturb : false
            hasCursor: controlsPanel.cursorIndex === 0
            foreground: root.bar ? root.bar.foreground : Color.foreground
            onActivated: controlsPanel.activateRow(0)
          }

          ControlTile {
            glyph: "󰔎"
            name: "Night Light"
            active: root.nightlightService ? root.nightlightService.enabled : false
            hasCursor: controlsPanel.cursorIndex === 1
            foreground: root.bar ? root.bar.foreground : Color.foreground
            onActivated: controlsPanel.activateRow(1)
          }

          ControlTile {
            glyph: "󰅶"
            name: "Stay Awake"
            active: root.idleService ? root.idleService.stayAwake : false
            hasCursor: controlsPanel.cursorIndex === 2
            foreground: root.bar ? root.bar.foreground : Color.foreground
            onActivated: controlsPanel.activateRow(2)
          }

          ControlTile {
            glyph: "󰍬"
            name: "Dictation"
            active: false
            hasCursor: controlsPanel.cursorIndex === 3
            foreground: root.bar ? root.bar.foreground : Color.foreground
            onActivated: controlsPanel.activateRow(3)
          }
        }
      }
    }
  }


// Quick-settings square: icon centered, tile reverse-fills with the accent
// when active (icon swaps to the background color for contrast).
  component ControlTile: Item {
    id: tile

    property string glyph: ""
    property string name: ""
    property bool active: false
    property bool hasCursor: false
    property color foreground: Color.foreground
    signal activated()

    Layout.preferredWidth: Style.space(56)
    Layout.preferredHeight: Style.space(56)

    BorderSurface {
      id: tileSurface
      anchors.fill: parent
      radius: Math.min(Style.cornerRadius, Style.space(6))
      color: tile.active ? Color.accent
        : (tile.hasCursor || tileMouse.containsMouse
           ? Qt.rgba(tile.foreground.r, tile.foreground.g, tile.foreground.b, 0.08)
           : Qt.rgba(tile.foreground.r, tile.foreground.g, tile.foreground.b, 0.04))
      borderSpec: Border.flat(tile.active ? Color.accent : (tile.hasCursor ? Color.accent : Qt.rgba(tile.foreground.r, tile.foreground.g, tile.foreground.b, 0.15)), 1)

      Text {
        anchors.centerIn: parent
        text: tile.glyph
        color: tile.active ? Color.background : tile.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.iconLarge
      }
    }

    MouseArea {
      id: tileMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: tile.activated()
    }
  }
  }
