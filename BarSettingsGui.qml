import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

// Bar settings GUI for skal.bar. Summoned as a panel plugin:
//   omarchy-shell shell toggle skal.bar
// Right-clicking blank bar space or pressing the SUPER+B hotkey also opens it.
// Every control writes through shell.mutateShellConfig, so changes apply to
// the live bar and persist to ~/.config/omarchy/shell.json immediately.
//
// Layout notes:
// - Form controls from qs.Ui do not self-size; they are built for Qt Quick
//   Layouts, which apply children's implicit sizes. Every container here is
//   a ColumnLayout/RowLayout — plain Column positioners collapse these
//   controls to zero height and rows overlap their headers.
// - Tab panes are sibling ColumnLayouts toggled by visibility; layouts skip
//   invisible items, so the implicit height always matches the active tab.
// - The card itself is anchored, never layout-driven, and no default
//   property aliases are used (they drop rows in inline components).
Item {
  id: root

  property var shell: null
  property var manifest: null
  // Injected by the host panel loader — maps widget ids to components, the
  // same registry the bar's own slots resolve through.
  property var barWidgetRegistry: null
  property bool opened: false
  property int currentTab: 0
  property string selectedWidget: ""

  // Chip drag state. The ghost is a grabToImage snapshot of the chip (the
  // same technique the bar uses for widget reordering), so the live widget
  // instances never move under the pointer.
  property bool chipDragging: false
  property string dragWidgetId: ""
  property url chipDragImage: ""
  property real chipDragX: 0
  property real chipDragY: 0
  // Ghost center in SCENE coordinates — hit tests map from scene into each
  // tray, while chipDragX/Y stay in dragLayer coordinates for the ghost.
  property real chipDragSceneX: -1
  property real chipDragSceneY: -1
  property real chipDragOffsetX: 0
  property real chipDragOffsetY: 0
  property real chipDragWidth: 0
  property real chipDragHeight: 0

  readonly property var cfg: shell && Util.isPlainObject(shell.barConfig) ? shell.barConfig : ({})
  readonly property int cardWidth: 900
  readonly property color text: Color.popups.text
  readonly property color textDim: Qt.darker(Color.popups.text, 1.4)

  function open(payloadJson) {
    root.opened = true
  }

  function close() {
    root.opened = false
  }

  function toggle() {
    root.opened = !root.opened
  }

  // ---- config helpers ----------------------------------------------------

  function mutate(fn) {
    if (!shell || typeof shell.mutateShellConfig !== "function") return
    shell.mutateShellConfig(fn)
  }

  function barObj(config) {
    if (!Util.isPlainObject(config.bar)) config.bar = {}
    return config.bar
  }

  function setBar(key, value) {
    mutate(function(config) {
      var bar = root.barObj(config)
      if (value === undefined || value === null) delete bar[key]
      else bar[key] = value
    })
  }

  function cfgNum(key, fallback) {
    var n = Number(root.cfg[key])
    return isFinite(n) ? n : fallback
  }

  function cfgStr(key, fallback) {
    var value = root.cfg[key]
    return value === undefined || value === null || String(value) === "" ? fallback : String(value)
  }

  // ---- layout entries (Bartender widget states) ---------------------------
  //
  // Per widget visibility, like Bartender on macOS:
  //   "shown"  — always on the bar
  //   "hover"  — hidden until the bar is hovered or the chevron is pinned
  //   "always" — hidden even during a reveal

  function hiddenStateOf(entry) {
    var value = typeof entry === "object" && entry !== null ? entry.hidden : undefined
    if (value === true || value === "hover") return "hover"
    if (value === "always") return "always"
    return "shown"
  }

  readonly property var layoutEntries: {
    var config = root.cfg
    var out = []
    if (!Util.isPlainObject(config.layout)) return out
    var regions = ["left", "center", "right"]
    for (var r = 0; r < regions.length; r++) {
      var entries = Array.isArray(config.layout[regions[r]]) ? config.layout[regions[r]] : []
      for (var i = 0; i < entries.length; i++) {
        var entry = entries[i]
        var id = typeof entry === "string" ? entry : (entry && entry.id ? String(entry.id) : "")
        if (id === "") continue
        var settings = {}
        if (typeof entry === "object" && entry !== null) {
          for (var key in entry) {
            if (key !== "id") settings[key] = entry[key]
          }
        }
        var state = root.hiddenStateOf(entry)
        out.push({ region: regions[r], id: id, state: state, stateRank: root.stateRank(state), settings: settings })
      }
    }
    return out
  }

  function regionEntries(region) {
    var entries = root.layoutEntries
    var out = []
    for (var i = 0; i < entries.length; i++) {
      if (entries[i].region === region) out.push(entries[i])
    }
    return out
  }

  // Bartender zone ranks: 0 = always hidden, 1 = hidden until reveal,
  // 2 = always visible. Rendering and drop resolution both order by this.
  function stateRank(state) {
    if (state === "always") return 0
    if (state === "hover") return 1
    return 2
  }

  function zoneEntries(region, rank) {
    var entries = root.regionEntries(region)
    var out = []
    for (var i = 0; i < entries.length; i++) {
      if (entries[i].stateRank === rank) out.push(entries[i])
    }
    return out
  }

  function entryRank(entry) {
    if (typeof entry !== "object" || entry === null) return 2
    return root.stateRank(root.hiddenStateOf(entry))
  }

  // Per-region reveal mode + indicator glyph (bar.hiddenRevealByRegion /
  // bar.revealIcons). Empty string = follow the global default.
  function regionMode(region) {
    var map = root.cfg.hiddenRevealByRegion
    var value = Util.isPlainObject(map) ? map[region] : undefined
    return value === "hover" || value === "click" ? value : ""
  }

  function setRegionMode(region, value) {
    mutate(function(config) {
      var bar = root.barObj(config)
      if (value === "" ) {
        if (Util.isPlainObject(bar.hiddenRevealByRegion)) delete bar.hiddenRevealByRegion[region]
        return
      }
      if (!Util.isPlainObject(bar.hiddenRevealByRegion)) bar.hiddenRevealByRegion = {}
      bar.hiddenRevealByRegion[region] = value
    })
  }

  function regionIcon(region) {
    var map = root.cfg.revealIcons
    var value = Util.isPlainObject(map) ? map[region] : undefined
    return value === undefined || value === null ? "" : String(value)
  }

  function setRegionIcon(region, value) {
    mutate(function(config) {
      var bar = root.barObj(config)
      if (value === "") {
        if (Util.isPlainObject(bar.revealIcons)) delete bar.revealIcons[region]
        return
      }
      if (!Util.isPlainObject(bar.revealIcons)) bar.revealIcons = {}
      bar.revealIcons[region] = value
    })
  }

  // Glyph for a widget's name tile, from the same nerd-font set the bar's
  // own widgets render with. Empty string = text-only tile.
  function glyphForWidget(id) {
    var name = String(id || "").toLowerCase()
    if (name.indexOf("clock") !== -1 || name.indexOf("time") !== -1) return "󰥔"
    if (name.indexOf("audio") !== -1 || name.indexOf("volume") !== -1) return "󰕾"
    if (name.indexOf("network") !== -1) return "󰖩"
    if (name.indexOf("ethernet") !== -1 || name.indexOf("lan") !== -1) return "󰈀"
    if (name.indexOf("wifi") !== -1) return "󰤨"
    if (name.indexOf("bluetooth") !== -1) return "󰂯"
    if (name.indexOf("power") !== -1 || name.indexOf("battery") !== -1) return "󰁹"
    if (name.indexOf("weather") !== -1) return "󰖙"
    if (name.indexOf("menu") !== -1 || name.indexOf("launcher") !== -1) return "󰣇"
    if (name.indexOf("workspace") !== -1) return "󰘵"
    if (name.indexOf("tray") !== -1) return "󰂲"
    if (name.indexOf("keyboard") !== -1) return "󰌌"
    if (name.indexOf("media") !== -1 || name.indexOf("music") !== -1) return "󰝚"
    if (name.indexOf("microphone") !== -1) return "󰍬"
    if (name.indexOf("monitor") !== -1 || name.indexOf("display") !== -1 || name.indexOf("brightness") !== -1) return "󰍹"
    if (name.indexOf("update") !== -1) return "󰚰"
    if (name.indexOf("agent") !== -1 || name.indexOf("copilot") !== -1) return "󰚩"
    if (name.indexOf("tailscale") !== -1 || name.indexOf("vpn") !== -1) return "󰖂"
    if (name.indexOf("notification") !== -1) return "󰂞"
    if (name.indexOf("indicator") !== -1) return "󰀓"
    if (name.indexOf("update") !== -1 || name.indexOf("sync") !== -1) return "󰚰"
    if (name.indexOf("system") !== -1) return "󰘳"
    return ""
  }

  // Bare widget name for display: everything after the last namespace dot.
  function shortName(id) {
    var name = String(id || "")
    var sep = name.lastIndexOf(".")
    return sep === -1 ? name : name.substring(sep + 1)
  }

  // Move a widget between sections and Bartender zones in one action,
  // using the bar's own reorder semantics: resolve the drop to an
  // "insert before entry id" ("" = end of section) against the nearest
  // chip edge, then insert into the section's real array. Zones are purely
  // a rank-filtered VIEW — the config keeps the user's actual order, so
  // hidden widgets reveal in place on the bar instead of migrating.
  function moveWidgetZone(widgetId, toRegion, targetState, beforeId) {
    if (/\.tray$/.test(String(widgetId || ""))) return
    mutate(function(config) {
      var bar = root.barObj(config)
      if (!Util.isPlainObject(bar.layout)) bar.layout = {}
      var regions = ["left", "center", "right"]
      for (var r = 0; r < regions.length; r++) {
        if (!Array.isArray(bar.layout[regions[r]])) bar.layout[regions[r]] = []
      }
      if (regions.indexOf(toRegion) === -1) return

      var moved = null
      for (var g = 0; g < regions.length && !moved; g++) {
        var source = bar.layout[regions[g]]
        for (var i = 0; i < source.length; i++) {
          var entry = source[i]
          var matches = typeof entry === "string" ? entry === widgetId : (entry && entry.id === widgetId)
          if (!matches) continue
          moved = entry
          source.splice(i, 1)
          break
        }
      }
      if (!moved) return

      if (typeof moved === "string") moved = { id: moved }
      if (targetState === "shown") delete moved.hidden
      else moved.hidden = targetState

      var target = bar.layout[toRegion]
      var toIndex = target.length
      if (beforeId) {
        for (var f = 0; f < target.length; f++) {
          var candidate = target[f]
          var hit = typeof candidate === "string" ? candidate === beforeId : (candidate && candidate.id === beforeId)
          if (hit) { toIndex = f; break }
        }
      }
      target.splice(toIndex, 0, moved)
    })
  }

  // ---- chip drag lifecycle -------------------------------------------------

  function beginChipDrag(chip, widgetId, scenePoint) {
    if (root.chipDragging) return
    root.chipDragging = true
    root.dragWidgetId = widgetId
    root.chipDragImage = ""
    root.chipDragWidth = chip.width
    root.chipDragHeight = chip.height
    var chipPoint = dragLayer.mapFromItem(chip, 0, 0)
    var layerPoint = dragLayer.mapFromItem(null, scenePoint.x, scenePoint.y)
    root.chipDragOffsetX = layerPoint.x - chipPoint.x
    root.chipDragOffsetY = layerPoint.y - chipPoint.y
    root.updateChipDrag(scenePoint)
    chip.grabToImage(function(result) {
      if (root.chipDragging && result && result.url) root.chipDragImage = result.url
    }, Qt.size(Math.max(1, Math.ceil(chip.width)), Math.max(1, Math.ceil(chip.height))))
  }

  function updateChipDrag(scenePoint) {
    var layerPoint = dragLayer.mapFromItem(null, scenePoint.x, scenePoint.y)
    root.chipDragX = layerPoint.x - root.chipDragOffsetX
    root.chipDragY = layerPoint.y - root.chipDragOffsetY
    root.chipDragSceneX = scenePoint.x
    root.chipDragSceneY = scenePoint.y
  }

  function endChipDrag() {
    if (!root.chipDragging) return
    root.chipDragging = false

    var sceneX = root.chipDragSceneX
    var sceneY = root.chipDragSceneY
    var rows = [rowLeft, rowCenter, rowRight]
    for (var i = 0; i < rows.length; i++) {
      var row = rows[i]
      if (!row) continue
      var zone = row.zoneAt(sceneX, sceneY)
      if (!zone) continue
      root.moveWidgetZone(root.dragWidgetId, row.region, zone.state, zone.dropBeforeId(sceneX, sceneY))
      break
    }

    root.chipDragImage = ""
    root.dragWidgetId = ""
    root.chipDragSceneX = -1
    root.chipDragSceneY = -1
  }

  // ---- logo (the menu widget entry) ---------------------------------------

  readonly property string menuEntryId: {
    var entries = root.layoutEntries
    for (var i = 0; i < entries.length; i++) {
      if (entries[i].id === "omarchy.menu" || /\.menu$/.test(entries[i].id)) return entries[i].id
    }
    return ""
  }

  readonly property var menuEntry: {
    var config = root.cfg
    var id = root.menuEntryId
    if (id === "" || !Util.isPlainObject(config.layout)) return null
    var regions = ["left", "center", "right"]
    for (var r = 0; r < regions.length; r++) {
      var entries = Array.isArray(config.layout[regions[r]]) ? config.layout[regions[r]] : []
      for (var i = 0; i < entries.length; i++) {
        var entry = entries[i]
        if (typeof entry === "object" && entry !== null && entry.id === id) return entry
      }
    }
    return null
  }

  function logoVal(key, fallback) {
    var entry = root.menuEntry
    var value = entry ? entry[key] : undefined
    return value === undefined || value === null ? fallback : String(value)
  }

  function setLogo(key, value) {
    var id = root.menuEntryId
    if (id === "") return
    mutate(function(config) {
      var bar = root.barObj(config)
      if (!Util.isPlainObject(bar.layout)) return
      var regions = ["left", "center", "right"]
      for (var r = 0; r < regions.length; r++) {
        var entries = Array.isArray(bar.layout[regions[r]]) ? bar.layout[regions[r]] : []
        for (var i = 0; i < entries.length; i++) {
          var entry = entries[i]
          if (typeof entry !== "object" || entry === null || entry.id !== id) continue
          if (value === undefined || value === null || String(value) === "") delete entry[key]
          else entry[key] = value
          return
        }
      }
    })
  }

  function resetAppearance() {
    mutate(function(config) {
      var bar = root.barObj(config)
      var keys = ["height", "margin", "radius", "backgroundColor", "backgroundOpacity", "widgetSpacing", "edgePadding", "hiddenReveal"]
      for (var i = 0; i < keys.length; i++) delete bar[keys[i]]
    })
  }

  // ---- window -------------------------------------------------------------

  PanelWindow {
    id: panel

    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "skal-bar-settings"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: Color.menu.scrim

      MouseArea {
        anchors.fill: parent
        onClicked: root.close()
      }
    }

    BorderSurface {
      id: card

      width: root.cardWidth
      // One height for every tab: the tallest pane keeps the card from
      // resizing on tab switches; shorter panes just leave scroll-free
      // space above the Flickable's bottom edge.
      height: Math.min(
        Style.space(20) + headerRow.implicitHeight + tabRow.implicitHeight + Style.space(6)
        + Math.max(appearancePane.implicitHeight, widgetsPane.implicitHeight, logoPane.implicitHeight),
        panel.height - Style.gapsOut * 2
      )
      anchors.centerIn: parent
      radius: Style.cornerRadius
      color: Color.popups.background
      borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))

      MouseArea { anchors.fill: parent; onClicked: {} }

      // Ghost overlay for chip drags. Sits above all card content and is
      // input-transparent so it never steals the pointer from the chip
      // MouseArea driving the drag.
      Item {
        id: dragLayer
        anchors.fill: parent
        z: 100
        visible: root.chipDragging

        Rectangle {
          x: root.chipDragX
          y: root.chipDragY
          width: root.chipDragWidth
          height: root.chipDragHeight
          radius: Math.min(Style.cornerRadius, height / 2)
          color: Color.background
          border.color: Color.accent
          border.width: 1
          opacity: 0.9
        }

        Image {
          x: root.chipDragX
          y: root.chipDragY
          width: root.chipDragWidth
          height: root.chipDragHeight
          source: root.chipDragImage
          fillMode: Image.Stretch
          smooth: true
        }
      }

      Item {
        anchors.fill: parent
        anchors.margins: Style.space(14)

        // ---- header ----

        RowLayout {
          id: headerRow

          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          spacing: Style.space(4)

          Text {
            Layout.fillWidth: true
            text: "Bar"
            color: root.text
            font.family: Style.font.family
            font.pixelSize: Style.font.title
            font.bold: true
          }

          Button {
            text: "Reset"
            fontSize: Style.font.bodySmall
            tooltipText: "Reset all appearance values to theme defaults"
            onClicked: root.resetAppearance()
          }

          Button {
            text: "✕"
            fontSize: Style.font.bodySmall
            onClicked: root.close()
          }
        }

        // ---- tab row ----

        Row {
          id: tabRow

          anchors.top: headerRow.bottom
          anchors.topMargin: Style.space(2)
          anchors.left: parent.left
          anchors.right: parent.right
          spacing: Style.space(2)

          TabButton {
            label: "Appearance"
            active: root.currentTab === 0
            onClicked: root.currentTab = 0
          }

          TabButton {
            label: "Widgets"
            active: root.currentTab === 1
            onClicked: root.currentTab = 1
          }

          TabButton {
            label: "Logo"
            active: root.currentTab === 2
            onClicked: root.currentTab = 2
          }
        }

        PanelSeparator {
          id: tabDivider
          anchors.top: tabRow.bottom
          anchors.left: parent.left
          anchors.right: parent.right
          foreground: root.text
        }

        // ---- tabbed content ----

        Flickable {
          id: scroll

          anchors.top: tabDivider.bottom
          anchors.topMargin: Style.space(6)
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          contentWidth: width
          contentHeight: tabContent.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds

          ColumnLayout {
            id: tabContent

            width: scroll.width
            height: implicitHeight
            spacing: 0

            // =============== Appearance ===============

            ColumnLayout {
              id: appearancePane
              visible: root.currentTab === 0
              Layout.fillWidth: true
              spacing: Style.space(16)

              SectionHeader {
                title: "SIZE"
                hint: root.cfgNum("height", 0) === 0 ? "theme default" : root.cfgNum("height", 0) + " px"
              }

              FormRow {
                label: "Position"

                Dropdown {
                  value: root.cfgStr("position", "top")
                  options: [
                    { value: "top", label: "Top" },
                    { value: "bottom", label: "Bottom" },
                    { value: "left", label: "Left" },
                    { value: "right", label: "Right" }
                  ]
                  showLabel: false
                  foreground: root.text
                  onChanged: function(value) { root.setBar("position", value) }
                }
              }

              FormRow {
                label: "Tray"

                Dropdown {
                  value: root.cfgStr("traySection", "right")
                  options: [
                    { value: "right", label: "Right edge" },
                    { value: "left", label: "Left edge" },
                    { value: "none", label: "Hidden" }
                  ]
                  showLabel: false
                  foreground: root.text
                  onChanged: function(value) { root.setBar("traySection", value) }
                }
              }

              FormRow {
                label: "Height"

                NumberField {
                  value: root.cfgNum("height", 0)
                  from: 0
                  to: 80
                  foreground: root.text
                  onModified: function(value) { root.setBar("height", value) }
                }
              }

              FormRow {
                label: "Float margin"
                hint: "offsets the bar from the screen edge"

                NumberField {
                  value: root.cfgNum("margin", 0)
                  from: 0
                  to: 64
                  foreground: root.text
                  onModified: function(value) { root.setBar("margin", value) }
                }
              }

              FormRow {
                label: "Corner radius"

                NumberField {
                  value: root.cfgNum("radius", 0)
                  from: 0
                  to: 32
                  foreground: root.text
                  onModified: function(value) { root.setBar("radius", value) }
                }
              }

              SectionHeader {
                title: "COLORS"
              }

              FormRow {
                label: "Background"

                TextField {
                  width: Style.space(26)
                  text: root.cfgStr("backgroundColor", "")
                  placeholderText: "theme"
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  color: root.text
                  foreground: root.text
                  onEditingFinished: {
                    var value = String(text).trim()
                    root.setBar("backgroundColor", /^#[0-9A-Fa-f]{6}$/.test(value) ? value : null)
                  }
                }
              }

              FormRow {
                label: "Opacity"
                hint: Math.round(root.cfgNum("backgroundOpacity", 1) * 100) + "%"

                NumberField {
                  value: Math.round(root.cfgNum("backgroundOpacity", 1) * 100)
                  from: 0
                  to: 100
                  foreground: root.text
                  onModified: function(value) { root.setBar("backgroundOpacity", value / 100) }
                }
              }

              Toggle {
                Layout.fillWidth: true
                label: "Fully transparent"
                description: "Removes the bar background entirely"
                foreground: root.text
                checked: root.cfg.transparent === true
                onClicked: root.setBar("transparent", root.cfg.transparent === true ? null : true)
              }

              SectionHeader {
                title: "SPACING"
              }

              FormRow {
                label: "Widget gap"

                NumberField {
                  value: root.cfgNum("widgetSpacing", 0)
                  from: 0
                  to: 32
                  foreground: root.text
                  onModified: function(value) { root.setBar("widgetSpacing", value) }
                }
              }

              FormRow {
                label: "Edge padding"
                hint: root.cfgNum("edgePadding", -1) < 0 ? "theme default" : ""

                NumberField {
                  value: Math.max(0, root.cfgNum("edgePadding", 0))
                  from: 0
                  to: 64
                  foreground: root.text
                  onModified: function(value) { root.setBar("edgePadding", value) }
                }
              }
            }

            // =============== Widgets ===============

            ColumnLayout {
              id: widgetsPane
              visible: root.currentTab === 1
              Layout.fillWidth: true
              spacing: Style.space(16)

              SectionHeader {
                title: "ARRANGEMENT"
                hint: "drag chips between sections"
              }

              Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: "Each chip is the live widget. Every section is a Bartender strip — drag chips between the three zones to set visibility, and between section rows to move them. Fine-order within a zone also works by dragging widgets directly on the bar."
                color: root.textDim
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }

              Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: "always hidden    │    hidden until reveal    │    always visible"
                color: root.textDim
                opacity: 0.75
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }

              // One board, three labeled rows: a single bordered surface
              // holding every section's chips, so drop logic resolves a row
              // and an index from one coordinate space.
              BorderSurface {
                id: board

                Layout.fillWidth: true
                height: boardContent.implicitHeight + Style.space(20)
                radius: Math.min(Style.cornerRadius, Style.space(4))
                color: "transparent"
                borderSpec: Border.flat(root.textDim, 1)

                ColumnLayout {
                  id: boardContent

                  anchors.fill: parent
                  anchors.margins: Style.space(10)
                  spacing: Style.space(10)

                  RegionRow {
                    id: rowLeft
                    region: "left"
                  }

                  RegionRow {
                    id: rowCenter
                    region: "center"
                  }

                  RegionRow {
                    id: rowRight
                    region: "right"
                  }
                }
              }

              SectionHeader {
                title: "REGIONS"
                hint: "reveal gesture + indicator icon"
              }

FormRow {
                label: "Left"

                Dropdown {
                  id: modeDDLeft
                  label: "Reveal"
                  showLabel: true
                  foreground: root.text
                  value: root.regionMode("left")
                  options: [
                    { value: "", label: "Hover" },
                    { value: "click", label: "Toggle" }
                  ]
                  onChanged: function(value) { root.setRegionMode("left", value) }
                  // The kit Dropdown assigns value internally on selection,
                  // breaking the declarative binding; a Binding element
                  // re-applies it whenever the config value changes.
                  Binding { target: modeDDLeft; property: "value"; value: root.regionMode("left") }
                }

                Dropdown {
                  id: iconDDLeft
                  label: "Icon"
                  showLabel: true
                  foreground: root.text
                  value: root.regionIcon("left")
                  options: [
                    { value: "", label: "› right" },
                    { value: "‹", label: "‹ left" },
                    { value: "❯", label: "❯ right" },
                    { value: "❮", label: "❮ left" },
                    { value: "▸", label: "▸ right" },
                    { value: "◂", label: "◂ left" },
                    { value: "▾", label: "▾ down" },
                    { value: "▴", label: "▴ up" },
                    { value: "⋯", label: "⋯ dots" },
                    { value: "≡", label: "≡ bars" }
                  ]
                  onChanged: function(value) { root.setRegionIcon("left", value) }
                  Binding { target: iconDDLeft; property: "value"; value: root.regionIcon("left") }
                }
              }

              FormRow {
                label: "Center"

                Dropdown {
                  id: modeDDCenter
                  label: "Reveal"
                  showLabel: true
                  foreground: root.text
                  value: root.regionMode("center")
                  options: [
                    { value: "", label: "Hover" },
                    { value: "click", label: "Toggle" }
                  ]
                  onChanged: function(value) { root.setRegionMode("center", value) }
                  // The kit Dropdown assigns value internally on selection,
                  // breaking the declarative binding; a Binding element
                  // re-applies it whenever the config value changes.
                  Binding { target: modeDDCenter; property: "value"; value: root.regionMode("center") }
                }

                Dropdown {
                  id: iconDDCenter
                  label: "Icon"
                  showLabel: true
                  foreground: root.text
                  value: root.regionIcon("center")
                  options: [
                    { value: "", label: "› right" },
                    { value: "‹", label: "‹ left" },
                    { value: "❯", label: "❯ right" },
                    { value: "❮", label: "❮ left" },
                    { value: "▸", label: "▸ right" },
                    { value: "◂", label: "◂ left" },
                    { value: "▾", label: "▾ down" },
                    { value: "▴", label: "▴ up" },
                    { value: "⋯", label: "⋯ dots" },
                    { value: "≡", label: "≡ bars" }
                  ]
                  onChanged: function(value) { root.setRegionIcon("center", value) }
                  Binding { target: iconDDCenter; property: "value"; value: root.regionIcon("center") }
                }
              }

              FormRow {
                label: "Right"

                Dropdown {
                  id: modeDDRight
                  label: "Reveal"
                  showLabel: true
                  foreground: root.text
                  value: root.regionMode("right")
                  options: [
                    { value: "", label: "Hover" },
                    { value: "click", label: "Toggle" }
                  ]
                  onChanged: function(value) { root.setRegionMode("right", value) }
                  // The kit Dropdown assigns value internally on selection,
                  // breaking the declarative binding; a Binding element
                  // re-applies it whenever the config value changes.
                  Binding { target: modeDDRight; property: "value"; value: root.regionMode("right") }
                }

                Dropdown {
                  id: iconDDRight
                  label: "Icon"
                  showLabel: true
                  foreground: root.text
                  value: root.regionIcon("right")
                  options: [
                    { value: "", label: "› right" },
                    { value: "‹", label: "‹ left" },
                    { value: "❯", label: "❯ right" },
                    { value: "❮", label: "❮ left" },
                    { value: "▸", label: "▸ right" },
                    { value: "◂", label: "◂ left" },
                    { value: "▾", label: "▾ down" },
                    { value: "▴", label: "▴ up" },
                    { value: "⋯", label: "⋯ dots" },
                    { value: "≡", label: "≡ bars" }
                  ]
                  onChanged: function(value) { root.setRegionIcon("right", value) }
                  Binding { target: iconDDRight; property: "value"; value: root.regionIcon("right") }
                }
              }
            }

            // =============== Logo ===============

            ColumnLayout {
              id: logoPane
              visible: root.currentTab === 2
              Layout.fillWidth: true
              spacing: Style.space(16)

              Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                visible: root.menuEntryId === ""
                text: "No menu widget found in the bar layout — add one to customize its logo."
                color: root.textDim
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }

              SectionHeader {
                title: "PREVIEW"
                visible: root.menuEntryId !== ""
              }

              // Live preview of the configured logo.
              BorderSurface {
                visible: root.menuEntryId !== ""
                Layout.fillWidth: true
                height: Style.space(22)
                radius: Math.min(Style.cornerRadius, height / 2)
                color: Color.background
                borderSpec: Border.flat(root.textDim, 1)

                Text {
                  visible: root.logoVal("logoImage", "") === ""
                  anchors.centerIn: parent
                  text: root.logoVal("logo", "") !== "" ? root.logoVal("logo", "") : "\ue900"
                  color: root.logoVal("logoColor", "") !== "" ? root.logoVal("logoColor", "") : root.text
                  font.family: root.logoVal("logoFont", "") !== "" ? root.logoVal("logoFont", "") : "omarchy"
                  font.pixelSize: Number(root.logoVal("logoSize", 12)) || 12
                }

                Image {
                  visible: root.logoVal("logoImage", "") !== ""
                  anchors.centerIn: parent
                  source: {
                    var path = root.logoVal("logoImage", "")
                    if (path === "") return ""
                    if (path.indexOf("~/") === 0) path = Quickshell.env("HOME") + path.substring(1)
                    return "file://" + path
                  }
                  width: 40
                  height: 40
                  fillMode: Image.PreserveAspectFit
                  smooth: true
                  mipmap: true
                }
              }

              SectionHeader {
                title: "GLYPH"
              }

              FormRow {
                label: "Text / icon"

                TextField {
                  width: Style.space(26)
                  text: root.logoVal("logo", "")
                  placeholderText: "default mark"
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  color: root.text
                  foreground: root.text
                  onEditingFinished: root.setLogo("logo", String(text).trim())
                }
              }

              FormRow {
                label: "Font"

                TextField {
                  width: Style.space(26)
                  text: root.logoVal("logoFont", "")
                  placeholderText: "omarchy"
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  color: root.text
                  foreground: root.text
                  onEditingFinished: root.setLogo("logoFont", String(text).trim())
                }
              }

              FormRow {
                label: "Size"

                NumberField {
                  value: Number(root.logoVal("logoSize", 12)) || 12
                  from: 8
                  to: 48
                  foreground: root.text
                  onModified: function(value) { root.setLogo("logoSize", value) }
                }
              }

              FormRow {
                label: "Color"

                TextField {
                  width: Style.space(26)
                  text: root.logoVal("logoColor", "")
                  placeholderText: "bar text"
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  color: root.text
                  foreground: root.text
                  onEditingFinished: {
                    var value = String(text).trim()
                    root.setLogo("logoColor", /^#[0-9A-Fa-f]{6}$/.test(value) ? value : null)
                  }
                }
              }

              SectionHeader {
                title: "IMAGE"
                hint: "shown instead of the glyph"
              }

              FormRow {
                label: "Path"

                TextField {
                  width: Style.space(26)
                  text: root.logoVal("logoImage", "")
                  placeholderText: "~/path/to/logo.png"
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  color: root.text
                  foreground: root.text
                  onEditingFinished: root.setLogo("logoImage", String(text).trim())
                }
              }
            }
          }
        }
      }
    }
  }

  // ---- building blocks ----------------------------------------------------

  // One bar section's drop tray: label, a rounded surface holding the
  // section's widget chips in a wrapping flow, and scene-space hit-testing
  // for drops. All geometry maps chips/pointer through the scene, the same
  // direction the bar's own drop code uses — mapping a pointer into items
  // under a Flickable is the fragile direction.
  // One bar section rendered as a Bartender strip: three visibility zones
  // (always hidden | hidden until reveal | always visible) separated by
  // divider lines. Dropping a chip into a zone both moves the widget to
  // this section and sets its visibility state.
  component RegionRow: ColumnLayout {
    id: regionRow

    property string region: ""
    readonly property var zones: [alwaysZone, revealZone, visibleZone]

    Layout.fillWidth: true
    spacing: Style.space(3)

    function zoneAt(sceneX, sceneY) {
      for (var i = 0; i < zones.length; i++) {
        if (zones[i] && zones[i].dropContains(sceneX, sceneY)) return zones[i]
      }
      return null
    }

    Text {
      Layout.fillWidth: true
      text: regionRow.region.toUpperCase()
      color: root.textDim
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.bold: true
      font.letterSpacing: 1.2
    }

    Rectangle {
      id: rowSurface

      Layout.fillWidth: true
      height: Math.max(Style.space(32), zoneRow.implicitHeight)
      radius: Math.min(Style.cornerRadius, Style.space(3))
      color: "transparent"

      RowLayout {
        id: zoneRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0

        Zone {
          id: alwaysZone
          region: regionRow.region
          state: "always"
          Layout.fillHeight: true
        }

        Rectangle {
          Layout.fillHeight: true
          width: 1
          color: Qt.rgba(root.text.r, root.text.g, root.text.b, 0.2)
        }

        Zone {
          id: revealZone
          region: regionRow.region
          state: "hover"
          Layout.fillHeight: true
        }

        Rectangle {
          Layout.fillHeight: true
          width: 1
          color: Qt.rgba(root.text.r, root.text.g, root.text.b, 0.2)
        }

        Zone {
          id: visibleZone
          region: regionRow.region
          state: "shown"
          Layout.fillWidth: true
          Layout.fillHeight: true
        }
      }
    }
  }

  // One visibility zone inside a section strip.
  component Zone: Item {
    id: zone

    property string region: ""
    property string state: ""
    readonly property bool dropHot: root.chipDragging
      && root.chipDragSceneX >= 0
      && zone.dropContains(root.chipDragSceneX, root.chipDragSceneY)

    function dropContains(sceneX, sceneY) {
      var origin = zone.mapToItem(null, 0, 0)
      return sceneX >= origin.x && sceneY >= origin.y
        && sceneX <= origin.x + zone.width && sceneY <= origin.y + zone.height
    }

    function chipItems() {
      var chips = []
      for (var i = 0; i < zoneFlow.children.length; i++) {
        var child = zoneFlow.children[i]
        if (child && child.isWidgetChip === true) chips.push(child)
      }
      return chips
    }

    // Bar-style drop resolution: the chip whose nearer edge is closest to
    // the pointer wins, with a before/after flag from edge distances; the
    // pointer's flow row only counts chips it overlaps vertically.
    function dropBeforeId(sceneX, sceneY) {
      var chips = zone.chipItems()
      var best = null
      var bestDistance = Infinity
      var bestIndex = -1
      for (var i = 0; i < chips.length; i++) {
        var chip = chips[i]
        var origin = chip.mapToItem(null, 0, 0)
        var rowOffset = Math.abs(sceneY - (origin.y + chip.height / 2))
        if (rowOffset > chip.height) continue
        var beforeDistance = Math.abs(sceneX - origin.x)
        var afterDistance = Math.abs(sceneX - (origin.x + chip.width))
        var after = afterDistance < beforeDistance
        var distance = (after ? afterDistance : beforeDistance) + rowOffset
        if (distance < bestDistance) {
          best = { after: after }
          bestDistance = distance
          bestIndex = i
        }
      }
      if (bestIndex === -1) return ""
      if (!best.after) return chips[bestIndex].entry.id
      var next = chips[bestIndex + 1]
      return next ? next.entry.id : ""
    }

    // Content-driven size. A Flow with an explicit width can never report
    // more than that width, so measuring through it locks a zone at its
    // current size forever. Instead, sum the chips' own widths — chips
    // always report their natural size — and let height follow the flow's
    // wrapped extent. Capped at half the row so a long list wraps and grows
    // taller instead of pushing sibling zones out; empty zones keep a
    // minimum strip so they still read — and work — as drop targets.
    function naturalWidth() {
      var total = 0
      var count = 0
      for (var i = 0; i < zoneFlow.children.length; i++) {
        var child = zoneFlow.children[i]
        if (child && child.isWidgetChip === true) {
          total += child.width
          count++
        }
      }
      return total + Math.max(0, count - 1) * zoneFlow.spacing
    }

    readonly property real measuredWidth: naturalWidth() + Style.space(12)
    implicitWidth: Math.max(Style.space(22),
      Math.min(measuredWidth, parent ? parent.width / 2 : measuredWidth))
    implicitHeight: Math.max(Style.space(24), zoneFlow.childrenRect.height + Style.space(2))

    Rectangle {
      anchors.fill: parent
      radius: Math.min(Style.cornerRadius, Style.space(3))
      color: zone.dropHot
        ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.16)
        : "transparent"
    }

    Flow {
      id: zoneFlow

      anchors.fill: parent
      anchors.leftMargin: Style.space(4)
      anchors.rightMargin: Style.space(4)
      anchors.topMargin: Style.space(1)
      anchors.bottomMargin: Style.space(1)
      spacing: Style.space(8)

      Repeater {
        model: root.zoneEntries(zone.region, root.stateRank(zone.state))

        WidgetChip {
          required property var modelData
          entry: modelData
        }
      }
    }
  }

  // A live widget rendered as a draggable chip. The widget itself comes
  // from the shared bar-widget registry and renders exactly as it does on
  // the bar (same bar object, same inline settings); a MouseArea on top
  // keeps its own interactions off while providing click-select and drag.
  // Chips carry no border — selection and hover read as soft fills so the
  // tray outline stays the only chrome in the arrangement area.
  component WidgetChip: Item {
    id: chip

    property var entry
    readonly property bool isWidgetChip: true
    readonly property bool isPinned: /^.*\.tray$/.test(chip.entry ? chip.entry.id : "")
    readonly property bool isSelected: root.selectedWidget === chip.entry.id
    readonly property bool dimmed: chip.entry.state !== "shown"
    readonly property var regComponent: {
      var widgets = root.barWidgetRegistry ? root.barWidgetRegistry.widgets : null
      if (!widgets) return null
      var found = widgets[chip.entry.id]
      return found ? found.component : null
    }
    readonly property string displayGlyph: root.glyphForWidget(chip.entry ? chip.entry.id : "")

    readonly property string displayName: {
      var widgets = root.barWidgetRegistry ? root.barWidgetRegistry.widgets : null
      var found = widgets ? widgets[chip.entry.id] : null
      if (found && found.displayName) {
        // Registry names still carry vendor prefixes sometimes; show the
        // bare name either way.
        var name = String(found.displayName)
        var dot = name.lastIndexOf(".")
        return dot === -1 ? name : name.substring(dot + 1)
      }
      return root.shortName(chip.entry.id)
    }
    // Some widgets legitimately render nothing (inactive states, adaptive
    // modes). Rather than a blank chip, fall back to a named tile whenever
    // the live widget has no measurable content.
    readonly property bool widgetHasContent: {
      if (!chip.regComponent) return false
      var item = chipLoader.item
      if (!item) return true
      if (item.visible === false) return false
      if ("hasVisualContent" in item) return item.hasVisualContent === true
      return item.implicitWidth > 1
    }
    // Live widgets render at bar height; scale them down into the chip.
    readonly property real chipScale: chipLoader.item
      ? Math.min(1, chip.height / Math.max(1, chipLoader.item.implicitHeight))
      : 1

    width: (widgetHasContent && chipLoader.item
      ? chipLoader.item.implicitWidth * chip.chipScale
      : fallbackLabel.implicitWidth) + Style.space(10)
    height: Style.space(30)

    Rectangle {
      id: chipFill
      anchors.fill: parent
      radius: Math.min(Style.cornerRadius, height / 3)
      color: chip.isSelected
        ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.22)
        : (chipArea.containsMouse
           ? Qt.rgba(root.text.r, root.text.g, root.text.b, 0.07)
           : (chip.widgetHasContent ? "transparent" : Qt.rgba(root.text.r, root.text.g, root.text.b, 0.05)))
      opacity: chip.entry && chip.entry.state === "always" ? 0.55 : (chip.entry && chip.entry.state === "hover" ? 0.8 : 1)
    }

    Rectangle {
      visible: chip.isPinned
      width: 2
      height: parent.height - Style.space(4)
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      color: Color.accent
      radius: 1
    }

    Loader {
      id: chipLoader
      active: root.opened && root.currentTab === 1 && chip.regComponent !== null
      sourceComponent: chip.regComponent
      anchors.centerIn: parent
      scale: chip.chipScale
      onLoaded: {
        if ("bar" in item) item.bar = root.shell ? root.shell.bar : null
        if ("moduleName" in item) item.moduleName = chip.entry.id
        if ("settings" in item) item.settings = chip.entry.settings
        Qt.callLater(function() {
          if (!item) return
          if ("bar" in item) item.bar = root.shell ? root.shell.bar : null
          if ("moduleName" in item) item.moduleName = chip.entry.id
          if ("settings" in item) item.settings = chip.entry.settings
        })
      }
    }

    Row {
      id: fallbackLabel
      visible: !chip.widgetHasContent
      anchors.centerIn: parent
      spacing: Style.space(3)

      Text {
        visible: chip.displayGlyph !== ""
        text: chip.displayGlyph
        color: root.text
        font.family: Style.font.family
        font.pixelSize: Style.font.subtitle
      }

      Text {
        text: chip.displayName
        color: root.textDim
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        font.letterSpacing: 0.5
      }
    }

    MouseArea {
      id: chipArea

      // A real drag target is required even though the visible ghost is
      // manual: MouseArea drag with a target makes the enclosing Flickable
      // defer the grab for the whole gesture. Without it the Flickable
      // steals vertical drags as scroll flicks, canceling the chip drag.
      drag.target: dragAnchor
      drag.axis: Drag.XAndYAxis
      drag.threshold: Style.space(3)

      property real pressX: 0
      property real pressY: 0

      anchors.fill: parent
      hoverEnabled: true
      cursorShape: chip.isPinned ? Qt.ArrowCursor
        : (root.chipDragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor)

      onPressed: function(mouse) {
        pressX = mouse.x
        pressY = mouse.y
        root.selectedWidget = chip.entry.id
      }

      onPositionChanged: function(mouse) {
        if (chip.isPinned) return
        if (!(mouse.buttons & Qt.LeftButton) || !pressed) return
        var scenePoint = chip.mapToItem(null, mouse.x, mouse.y)
        if (!root.chipDragging) {
          if (chipArea.drag.active) root.beginChipDrag(chip, chip.entry.id, scenePoint)
        } else if (root.dragWidgetId === chip.entry.id) {
          root.updateChipDrag(scenePoint)
        }
      }

      onReleased: {
        if (root.chipDragging && root.dragWidgetId === chip.entry.id) root.endChipDrag()
      }

      // Grab theft or teardown mid-drag: drop at the last known pointer
      // position rather than stranding ghost state.
      onCanceled: {
        if (root.chipDragging && root.dragWidgetId === chip.entry.id) root.endChipDrag()
      }
    }

    Item {
      id: dragAnchor
      width: 0
      height: 0
      visible: false
    }

    Component.onDestruction: {
      if (root.chipDragging && root.dragWidgetId === chip.entry.id) root.endChipDrag()
    }
  }

  // Tab pill with accent underline, matching the bar's open-panel indicator.
  // Sits in a plain Row, so it sizes itself from its own implicit sizes.
  component TabButton: Item {
    id: tabButton

    property string label: ""
    property bool active: false
    signal clicked()

    width: implicitWidth
    height: implicitHeight
    implicitWidth: tabLabel.implicitWidth + Style.space(12)
    implicitHeight: tabLabel.implicitHeight + Style.space(10)

    Text {
      id: tabLabel
      anchors.centerIn: parent
      text: tabButton.label
      color: tabButton.active ? root.text : root.textDim
      font.family: Style.font.family
      font.pixelSize: Style.font.subtitle
      font.bold: tabButton.active
    }

    Rectangle {
      anchors.bottom: parent.bottom
      anchors.horizontalCenter: parent.horizontalCenter
      width: tabLabel.implicitWidth
      height: 2
      radius: 1
      color: Color.accent
      visible: tabButton.active
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: tabButton.clicked()
    }
  }

  // Uppercase section title with an optional right-aligned dim hint and a
  // hairline separator underneath. Rows follow as flat siblings, like the
  // first-party panels do.
  component SectionHeader: Item {
    id: sectionHeader

    property string title: ""
    property string hint: ""

    Layout.fillWidth: true
    implicitHeight: headerLine.height + Style.space(5) + separatorLine.height

    Item {
      id: headerLine
      width: parent.width
      height: Math.max(sectionTitle.implicitHeight, sectionHint.implicitHeight)

      PanelSectionHeader {
        id: sectionTitle
        text: sectionHeader.title
        foreground: root.text
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        id: sectionHint
        visible: sectionHeader.hint !== ""
        text: sectionHeader.hint
        color: root.textDim
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    PanelSeparator {
      id: separatorLine
      anchors.top: headerLine.bottom
      anchors.topMargin: Style.space(5)
      width: parent.width
      foreground: root.text
    }
  }

  // Label on the left, control on the right, optional hint under the label.
  component FormRow: RowLayout {
    id: formRow

    property string label: ""
    property string hint: ""

    Layout.fillWidth: true
    spacing: Style.space(8)

    ColumnLayout {
      Layout.fillWidth: true
      Layout.alignment: Qt.AlignVCenter
      spacing: 3

      Text {
        Layout.fillWidth: true
        text: formRow.label
        color: root.text
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }

      Text {
        visible: formRow.hint !== ""
        Layout.fillWidth: true
        text: formRow.hint
        color: root.textDim
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }
  }
}
