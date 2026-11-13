import QtQuick
import QtQuick.Shapes
import qs.Commons
import qs.Commons as Commons

// The reveal/collapse icons (› ‹ ❯ ❮ ▸ ◂ ▾ ▴ ⋯ ≡ ✕), drawn as vectors in a
// square box whose center is the ink's center. Font glyphs for these come
// from whatever fallback font has them, and their ink sits off the line box
// center by a different amount in each font — the arrows sat a couple of
// pixels high when closed and, rotated 180° about the box center, the same
// distance low when open. Drawn here, the ink is centered by construction,
// so every state and every rotation lands on the bar's midline.
// Anything outside the known set falls back to a centered text glyph.
Item {
  id: root

  property string glyph: "›"
  property color color: Commons.Color.foreground
  // Edge of the square the ink fits in; the bar's icon size by default.
  property real size: Style.bar.iconSize
  property string fontFamily: Style.font.family

  readonly property var spec: specFor(glyph)
  readonly property real s: size
  readonly property real stroke: Math.max(1.25, Math.round(size * 0.14 * 4) / 4)

  width: size
  height: size

  // Unit-square geometry, each centered on (0.5, 0.5).
  //   kind "line"  — open polyline, stroked
  //   kind "fill"  — closed polygon, filled
  //   kind "dots"  — three dots
  //   kind "bars"  — three bars
  function specFor(g) {
    switch (g) {
    case "›": return { kind: "line", w: 1.0, pts: [[0.36, 0.18], [0.64, 0.5], [0.36, 0.82]] }
    case "‹": return { kind: "line", w: 1.0, pts: [[0.64, 0.18], [0.36, 0.5], [0.64, 0.82]] }
    case "❯": return { kind: "line", w: 1.45, pts: [[0.33, 0.14], [0.67, 0.5], [0.33, 0.86]] }
    case "❮": return { kind: "line", w: 1.45, pts: [[0.67, 0.14], [0.33, 0.5], [0.67, 0.86]] }
    case "▸": return { kind: "fill", pts: [[0.3, 0.2], [0.7, 0.5], [0.3, 0.8]] }
    case "◂": return { kind: "fill", pts: [[0.7, 0.2], [0.3, 0.5], [0.7, 0.8]] }
    case "▾": return { kind: "fill", pts: [[0.2, 0.3], [0.8, 0.3], [0.5, 0.7]] }
    case "▴": return { kind: "fill", pts: [[0.2, 0.7], [0.8, 0.7], [0.5, 0.3]] }
    case "✕": return { kind: "cross" }
    case "⋯": return { kind: "dots" }
    case "≡": return { kind: "bars" }
    }
    return null
  }

  function pathFor(spec) {
    if (!spec || !spec.pts) return ""
    var p = spec.pts
    var d = "M " + (p[0][0] * s) + " " + (p[0][1] * s)
    for (var i = 1; i < p.length; i++) d += " L " + (p[i][0] * s) + " " + (p[i][1] * s)
    if (spec.kind === "fill") d += " Z"
    return d
  }

  Shape {
    anchors.fill: parent
    visible: root.spec !== null && (root.spec.kind === "line" || root.spec.kind === "fill")
    preferredRendererType: Shape.CurveRenderer
    antialiasing: true

    ShapePath {
      strokeColor: root.spec && root.spec.kind === "line" ? root.color : "transparent"
      strokeWidth: root.spec && root.spec.kind === "line" ? root.stroke * (root.spec.w || 1) : 0
      fillColor: root.spec && root.spec.kind === "fill" ? root.color : "transparent"
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin
      PathSvg { path: root.pathFor(root.spec) }
    }
  }

  Shape {
    anchors.fill: parent
    visible: root.spec !== null && root.spec.kind === "cross"
    preferredRendererType: Shape.CurveRenderer
    antialiasing: true

    ShapePath {
      strokeColor: root.color
      strokeWidth: root.stroke
      fillColor: "transparent"
      capStyle: ShapePath.RoundCap
      PathSvg {
        path: "M " + (0.24 * root.s) + " " + (0.24 * root.s) + " L " + (0.76 * root.s) + " " + (0.76 * root.s)
          + " M " + (0.76 * root.s) + " " + (0.24 * root.s) + " L " + (0.24 * root.s) + " " + (0.76 * root.s)
      }
    }
  }

  Row {
    anchors.centerIn: parent
    visible: root.spec !== null && root.spec.kind === "dots"
    spacing: Math.max(1, Math.round(root.s * 0.14))
    Repeater {
      model: 3
      Rectangle {
        width: Math.max(2, Math.round(root.s * 0.16))
        height: width
        radius: width / 2
        color: root.color
      }
    }
  }

  Column {
    anchors.centerIn: parent
    visible: root.spec !== null && root.spec.kind === "bars"
    spacing: Math.max(1, Math.round(root.s * 0.14))
    Repeater {
      model: 3
      Rectangle {
        width: Math.round(root.s * 0.7)
        height: Math.max(1, Math.round(root.stroke))
        radius: height / 2
        color: root.color
      }
    }
  }

  // Unknown glyphs: center the ink measured from the same font that paints.
  Text {
    id: fallback
    visible: root.spec === null && root.glyph !== ""
    textFormat: Text.PlainText
    text: root.glyph
    color: root.color
    font.family: root.fontFamily
    font.pixelSize: Math.round(root.size)
    x: root.width / 2 - (inkMetrics.tightBoundingRect.x + inkMetrics.tightBoundingRect.width / 2)
    y: root.height / 2 - (baselineOffset + inkMetrics.tightBoundingRect.y + inkMetrics.tightBoundingRect.height / 2)
  }

  TextMetrics {
    id: inkMetrics
    font: fallback.font
    text: fallback.text
  }
}
