import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.Commons
import Quickshell
import qs.Ui

// Logo/menu launcher with customizable branding, shipping with the bar
// plugin. Settings live inline on the bar layout entry in shell.json, e.g.:
//   { "id": "skal.bar", "logo": "󰣇", "logoFont": "Symbols Nerd Font" }
//   { "id": "skal.bar", "logoImage": "~/.config/omarchy/logo.png" }
// Settings: logo (text/glyph), logoFont (family), logoColor (#hex),
// logoSize (px), logoImage (path — shown instead of text).
// Left-click opens the quick menu (weather, quick actions, notifications);
// right-click the Omarchy menu; middle-click a terminal. The panel's IPC
// target is skal.bar.controls, owned by the bar (see Bar.qml) so the hotkey
// reaches the focused monitor's copy. Toggle state comes from the bar's
// file-watched ground truth — never from the host's scoped api, which
// Omarchy 4.0.3 can destroy mid-session.
BarWidget {
  id: root

  property string logoText: String(setting("logo", ""))
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

  // The dropdown lives in a Panel so the bar's popup machinery (tab order,
  // one-popout-at-a-time, summon) applies. The widget root proxies open/close
  // so the bar can address it — including from the bar-owned IPC handler for
  // the hotkey. This widget is instantiated once per bar surface (per
  // monitor), so its Panel cannot own the IPC target itself: only whichever
  // copy registered first would answer, popping the menu on the wrong screen.
  // The bar singleton registers skal.bar.controls instead.
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

  function relativeTime(ts) {
    var t = Number(ts)
    if (!isFinite(t) || t <= 0) return ""
    var s = Math.max(0, Math.floor((Date.now() - t) / 1000))
    if (s < 45) return "now"
    var m = Math.floor(s / 60)
    if (m < 60) return m + "m"
    var h = Math.floor(m / 60)
    if (h < 24) return h + "h"
    return Math.floor(h / 24) + "d"
  }

  function rebuildNotifModel() {
    notifListModel.clear()
    var rows = root.bar ? root.bar.notificationRows : []
    for (var i = 0; i < rows.length; i++) notifListModel.append(rows[i])
  }

  Connections {
    target: root.bar
    function onNotificationRowsChanged() { root.rebuildNotifModel() }
  }

  ListModel { id: notifListModel }

  Panel {
    id: controlsPanel
    bar: root.bar
    moduleName: "skal.bar.controls"
    ipcTarget: "skal.bar.controls"
    // The bar singleton owns this target (focused-monitor routing); a
    // per-instance handler here would race the other monitors' copies.
    manageIpc: false

    onOpenedChanged: {
      if (opened) {
        controlsKeyCatcher.forceActiveFocus()
        if (root.bar) {
          root.bar.probeQuickState()
          root.bar.refreshNotificationRows()
          if (!root.bar.weatherCurrent || Date.now() - root.bar.weatherAt > 5 * 60 * 1000)
            root.bar.probeWeather()
        }
      }
    }

    function activateRow(index) {
      if (!root.bar) return
      if (index === 0) root.bar.toggleQuickDnd()
      else if (index === 1) root.bar.toggleQuickNightlight()
      else if (index === 2) root.bar.toggleQuickStayAwake()
      else if (index === 3) root.bar.announceDictationToggle()
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

      // Even spacing by construction: the gap between tiles equals the
      // card's edge inset (padding + border), and every section uses the
      // same unit — the compact-menu padding the host's own tray menu uses,
      // with the standard space(10) content inset between everything else.
      padding: Style.space(8)
      readonly property int edge: padding + Border.top(borderSpec)
      readonly property int tileGap: edge
      readonly property int tilesPerRow: 4
      // All-integer tile geometry (Style.space rounds): the card is sized
      // FROM the row, so no fractional-cell rounding can steal pixels from
      // one side of the layout — every gap stays exactly `edge`.
      readonly property int tileWidth: Style.space(72)
      readonly property int rowWidth: tilesPerRow * tileWidth + (tilesPerRow - 1) * tileGap

      contentWidth: rowWidth + 2 * edge
      contentHeight: Math.round(menuColumn.implicitHeight + 2 * edge)


      
      Item {
        id: controlsKeyCatcher
        anchors.fill: parent
        focus: controlsPanel.opened

        Keys.onEscapePressed: controlsPanel.close()

        ColumnLayout {
          id: menuColumn
          anchors.fill: parent
          spacing: controlsCard.edge

          // ---- compact weather --------------------------------------
          Item {
            Layout.fillWidth: true
            implicitHeight: weatherRow.implicitHeight

            RowLayout {
              id: weatherRow
              anchors.fill: parent
              spacing: controlsCard.edge

              Text {
                text: root.bar && root.bar.weatherIcon ? root.bar.weatherIcon : "󰼰"
                color: root.bar ? root.bar.foreground : Color.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.display
              }

              ColumnLayout {
                spacing: 0
                RowLayout {
                  spacing: Style.space(6)
                  Layout.fillWidth: true
                  Text {
                    text: root.bar ? root.bar.weatherTemp : ""
                    color: root.bar ? root.bar.foreground : Color.foreground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.title
                  }
                  Text {
                    text: root.bar ? root.bar.weatherCondition : ""
                    color: Color.muted
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                  }
                  Text {
                    text: root.bar ? root.bar.weatherPlace : ""
                    color: Color.muted
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                    elide: Text.ElideRight
                    visible: text !== ""
                  }
                }
                Text {
                  text: [root.bar ? root.bar.weatherWind : ""].filter(function(part) { return part !== "" }).join("  ·  ")
                  color: Color.muted
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  visible: text !== ""
                }
              }
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: if (root.bar) root.bar.probeWeather()
            }
          }

          // ---- quick actions (1x4) ----------------------------------
          GridLayout {
            id: controlsGrid
            Layout.alignment: Qt.AlignHCenter
            columns: controlsCard.tilesPerRow
            columnSpacing: controlsCard.tileGap
            rowSpacing: controlsCard.tileGap

            ControlTile {
              tileSize: controlsCard.tileWidth
              glyph: "󰂛"
              name: "Silence Notifications"
              active: root.bar && root.bar.dndState
              foreground: root.bar ? root.bar.foreground : Color.foreground
              onActivated: controlsPanel.activateRow(0)
            }

            ControlTile {
              tileSize: controlsCard.tileWidth
              glyph: "󰔎"
              name: "Night Light"
              active: root.bar && root.bar.nightlightState
              foreground: root.bar ? root.bar.foreground : Color.foreground
              onActivated: controlsPanel.activateRow(1)
            }

            ControlTile {
              tileSize: controlsCard.tileWidth
              glyph: "󰅶"
              name: "Stay Awake"
              active: root.bar && root.bar.stayAwakeState
              foreground: root.bar ? root.bar.foreground : Color.foreground
              onActivated: controlsPanel.activateRow(2)
            }

            ControlTile {
              tileSize: controlsCard.tileWidth
              glyph: "󰍬"
              name: "Dictation"
              active: root.bar && root.bar.dictationActive
              foreground: root.bar ? root.bar.foreground : Color.foreground
              onActivated: controlsPanel.activateRow(3)
            }
          }

          // ---- notifications ----------------------------------------
          RowLayout {
            Layout.fillWidth: true
            spacing: controlsCard.edge

            Text {
              text: "Notifications"
              color: Color.muted
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
            }

            Item { Layout.fillWidth: true }

            Text {
              text: "Dismiss all"
              color: Color.accent
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
              visible: notifListModel.count > 0

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: if (root.bar) root.bar.dismissAllNotificationRows()
              }
            }
          }

          Item {
            Layout.fillWidth: true
            implicitHeight: Style.space(210)
            clip: true

            ListView {
              id: notifList
              anchors.fill: parent
              model: notifListModel
              spacing: 0
              boundsBehavior: Flickable.StopAtBounds
              clip: true
              ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

              // Host menu grammar: transparent rows that fill on hover, a
              // space(10) text inset, and 1px hairlines between rows.
              delegate: Column {
                width: notifList.width
                spacing: 0

                Item {
                  width: parent.width
                  implicitHeight: notifRowLayout.implicitHeight + 2 * Style.space(4)

                  Rectangle {
                    anchors.fill: parent
                    radius: Math.max(2, Style.cornerRadius)
                    color: notifRowMouse.containsMouse
                      ? Style.hoverFillFor(root.bar ? root.bar.foreground : Color.foreground,
                          root.bar ? root.bar.foreground : Color.foreground)
                      : "transparent"
                  }

                  MouseArea {
                    id: notifRowMouse
                    anchors.fill: parent
                    hoverEnabled: true
                  }

                  RowLayout {
                    id: notifRowLayout
                    anchors.fill: parent
                    anchors.leftMargin: Style.space(10)
                    anchors.rightMargin: Style.space(10)
                    spacing: Style.space(10)

                    Text {
                      text: model.glyph ? model.glyph : "󰂚"
                      color: model.live === true ? Color.accent
                        : (root.bar ? root.bar.foreground : Color.foreground)
                      font.family: Style.font.family
                      font.pixelSize: Style.font.icon
                      Layout.alignment: Qt.AlignTop
                    }

                    ColumnLayout {
                      spacing: 0
                      Layout.fillWidth: true

                      RowLayout {
                        spacing: Style.space(6)
                        Layout.fillWidth: true
                        Text {
                          text: model.summary || ""
                          color: root.bar ? root.bar.foreground : Color.foreground
                          font.family: Style.font.family
                          font.pixelSize: Style.font.body
                          elide: Text.ElideRight
                          Layout.fillWidth: true
                        }
                        Text {
                          text: root.relativeTime(model.timestamp)
                          color: Color.muted
                          font.family: Style.font.family
                          font.pixelSize: Style.font.caption
                        }
                      }

                      Text {
                        text: model.body || ""
                        color: Color.muted
                        font.family: Style.font.family
                        font.pixelSize: Style.font.bodySmall
                        wrapMode: Text.WrapAnywhere
                        elide: Text.ElideRight
                        maximumLineCount: 2
                        visible: text !== ""
                        Layout.fillWidth: true
                      }
                    }

                    Text {
                      text: "󰅖"
                      color: Color.muted
                      font.family: Style.font.family
                      font.pixelSize: Style.font.iconSmall
                      Layout.alignment: Qt.AlignTop

                      MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (root.bar) root.bar.dismissNotificationRow({
                          live: model.live === true,
                          file: model.file || "",
                          summary: model.summary || "",
                          originalId: model.originalId,
                          id: model.id,
                          app: model.app || "",
                          timestamp: model.timestamp
                        })
                      }
                    }
                  }

                }

                Item {
                  visible: index < notifListModel.count - 1
                  width: parent.width
                  implicitHeight: Style.space(11)

                  Rectangle {
                    anchors.left: parent.left
                    anchors.leftMargin: Style.space(10)
                    anchors.right: parent.right
                    anchors.rightMargin: Style.space(10)
                    anchors.verticalCenter: parent.verticalCenter
                    height: 1
                    color: Color.popups.border
                    opacity: 0.45
                  }
                }
              }
            }

            Text {
              anchors.centerIn: parent
              text: "No notifications"
              color: Color.muted
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
              visible: notifListModel.count === 0
            }
          }
        }
      }
    }
  }

  // Quick-settings square, strictly binary: off is the quiet surface, on is
  // a full accent fill with the icon reversed for contrast. The transition
  // animates; hover only lifts the fill slightly. There is no keyboard
  // cursor — tiles answer to direct clicks and the global hotkeys.
  component ControlTile: Item {
    id: tile

    property string glyph: ""
    property string name: ""
    property bool active: false
    property color foreground: Color.foreground
    property real tileSize: Style.space(56)
    signal activated()

    Layout.preferredWidth: tileSize
    Layout.preferredHeight: tileSize

    BorderSurface {
      id: tileSurface
      anchors.fill: parent
      radius: Math.min(Style.cornerRadius, Style.space(6))
      color: tile.active ? Color.accent
        : Qt.rgba(tile.foreground.r, tile.foreground.g, tile.foreground.b,
            tileMouse.containsMouse ? 0.08 : 0.04)
      borderSpec: Border.flat(tile.active ? Color.accent
        : Qt.rgba(tile.foreground.r, tile.foreground.g, tile.foreground.b, 0.15), 1)

      Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }

      Text {
        anchors.centerIn: parent
        text: tile.glyph
        color: tile.active ? Color.background : tile.foreground

        Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
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
