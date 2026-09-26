import AppKit

extension AppSymbols {
  /// Draws the 10.15 stand-in for `name` in the current context; false when unsupported.
  static func drawFallbackSymbol(named name: String, in bounds: NSRect) -> Bool {
    switch name {
    case "star", "star.fill":
      let center = NSPoint(x: bounds.midX, y: bounds.midY)
      let outerRadius: CGFloat = 8
      let innerRadius: CGFloat = 3.6
      let star = NSBezierPath()
      for index in 0..<10 {
        let angle = (-CGFloat.pi / 2) + CGFloat(index) * CGFloat.pi / 5
        let radius = index.isMultiple(of: 2) ? outerRadius : innerRadius
        let point = NSPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
        if index == 0 { star.move(to: point) } else { star.line(to: point) }
      }
      star.close()
      star.lineWidth = 1.5
      if name == "star.fill" { star.fill() } else { star.stroke() }
    case "arrow.down.circle":
      let circle = NSBezierPath(ovalIn: bounds.insetBy(dx: 1.3, dy: 1.3))
      circle.lineWidth = 1.5
      circle.stroke()
      let arrow = NSBezierPath()
      arrow.lineWidth = 1.6
      arrow.lineCapStyle = .round
      arrow.lineJoinStyle = .round
      arrow.move(to: NSPoint(x: 9, y: 13.2))
      arrow.line(to: NSPoint(x: 9, y: 5))
      arrow.move(to: NSPoint(x: 5.8, y: 8.3))
      arrow.line(to: NSPoint(x: 9, y: 5))
      arrow.line(to: NSPoint(x: 12.2, y: 8.3))
      arrow.stroke()
    case "list.bullet.rectangle":
      let frame = NSBezierPath(
        roundedRect: bounds.insetBy(dx: 1.2, dy: 1.2),
        xRadius: 2,
        yRadius: 2
      )
      frame.lineWidth = 1.4
      frame.stroke()
      for y: CGFloat in [5, 9, 13] {
        NSBezierPath(ovalIn: NSRect(x: 4, y: y - 0.6, width: 1.2, height: 1.2)).fill()
        let line = NSBezierPath()
        line.lineWidth = 1.2
        line.move(to: NSPoint(x: 7, y: y))
        line.line(to: NSPoint(x: 14, y: y))
        line.stroke()
      }
    case "square.grid.2x2":
      for x: CGFloat in [3, 10] {
        for y: CGFloat in [3, 10] {
          let tile = NSBezierPath(
            roundedRect: NSRect(x: x, y: y, width: 5, height: 5),
            xRadius: 1,
            yRadius: 1
          )
          tile.lineWidth = 1.3
          tile.stroke()
        }
      }
    case "gamecontroller":
      let body = NSBezierPath()
      body.lineWidth = 1.4
      body.lineJoinStyle = .round
      body.move(to: NSPoint(x: 5, y: 12))
      body.line(to: NSPoint(x: 6, y: 14))
      body.line(to: NSPoint(x: 12, y: 14))
      body.line(to: NSPoint(x: 13, y: 12))
      body.curve(
        to: NSPoint(x: 16, y: 6),
        controlPoint1: NSPoint(x: 16, y: 11),
        controlPoint2: NSPoint(x: 17, y: 7)
      )
      body.curve(
        to: NSPoint(x: 13, y: 7),
        controlPoint1: NSPoint(x: 15, y: 4),
        controlPoint2: NSPoint(x: 14, y: 5)
      )
      body.line(to: NSPoint(x: 5, y: 7))
      body.curve(
        to: NSPoint(x: 2, y: 6),
        controlPoint1: NSPoint(x: 4, y: 5),
        controlPoint2: NSPoint(x: 3, y: 4)
      )
      body.curve(
        to: NSPoint(x: 5, y: 12),
        controlPoint1: NSPoint(x: 1, y: 7),
        controlPoint2: NSPoint(x: 2, y: 11)
      )
      body.close()
      body.stroke()
      let dpad = NSBezierPath()
      dpad.lineWidth = 1.3
      dpad.move(to: NSPoint(x: 5, y: 8.5))
      dpad.line(to: NSPoint(x: 5, y: 11.5))
      dpad.move(to: NSPoint(x: 3.5, y: 10))
      dpad.line(to: NSPoint(x: 6.5, y: 10))
      dpad.stroke()
      NSBezierPath(ovalIn: NSRect(x: 11.5, y: 9.7, width: 1.2, height: 1.2)).fill()
      NSBezierPath(ovalIn: NSRect(x: 13.4, y: 8.1, width: 1.2, height: 1.2)).fill()
    case "arrow.down.app":
      let frame = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 1.5), xRadius: 2, yRadius: 2)
      frame.lineWidth = 1.4
      frame.stroke()
      let arrow = NSBezierPath()
      arrow.lineWidth = 1.5
      arrow.lineCapStyle = .round
      arrow.lineJoinStyle = .round
      arrow.move(to: NSPoint(x: 9, y: 13))
      arrow.line(to: NSPoint(x: 9, y: 6))
      arrow.move(to: NSPoint(x: 6.5, y: 8.5))
      arrow.line(to: NSPoint(x: 9, y: 6))
      arrow.line(to: NSPoint(x: 11.5, y: 8.5))
      arrow.stroke()
      let tray = NSBezierPath()
      tray.lineWidth = 1.3
      tray.move(to: NSPoint(x: 5, y: 4))
      tray.line(to: NSPoint(x: 13, y: 4))
      tray.stroke()
    case "puzzlepiece":
      let piece = NSBezierPath()
      piece.lineWidth = 1.4
      piece.lineJoinStyle = .round
      piece.move(to: NSPoint(x: 2.5, y: 2.5))
      piece.line(to: NSPoint(x: 7, y: 2.5))
      piece.curve(
        to: NSPoint(x: 11, y: 2.5),
        controlPoint1: NSPoint(x: 7, y: 5.8),
        controlPoint2: NSPoint(x: 11, y: 5.8)
      )
      piece.line(to: NSPoint(x: 15.5, y: 2.5))
      piece.line(to: NSPoint(x: 15.5, y: 7))
      piece.curve(
        to: NSPoint(x: 15.5, y: 11),
        controlPoint1: NSPoint(x: 12.2, y: 7),
        controlPoint2: NSPoint(x: 12.2, y: 11)
      )
      piece.line(to: NSPoint(x: 15.5, y: 15.5))
      piece.line(to: NSPoint(x: 11, y: 15.5))
      piece.curve(
        to: NSPoint(x: 7, y: 15.5),
        controlPoint1: NSPoint(x: 11, y: 12.2),
        controlPoint2: NSPoint(x: 7, y: 12.2)
      )
      piece.line(to: NSPoint(x: 2.5, y: 15.5))
      piece.close()
      piece.stroke()
    case "paintbrush":
      let handle = NSBezierPath()
      handle.lineWidth = 2
      handle.lineCapStyle = .round
      handle.move(to: NSPoint(x: 4, y: 3))
      handle.line(to: NSPoint(x: 10.5, y: 9.5))
      handle.stroke()
      let brush = NSBezierPath()
      brush.lineWidth = 1.4
      brush.lineJoinStyle = .round
      brush.move(to: NSPoint(x: 8, y: 11))
      brush.line(to: NSPoint(x: 12, y: 15))
      brush.line(to: NSPoint(x: 16, y: 7))
      brush.line(to: NSPoint(x: 13, y: 4))
      brush.close()
      brush.stroke()
    case "person.crop.square":
      let frame = NSBezierPath(
        roundedRect: bounds.insetBy(dx: 1.5, dy: 1.5),
        xRadius: 2,
        yRadius: 2
      )
      frame.lineWidth = 1.3
      frame.stroke()
      let head = NSBezierPath(ovalIn: NSRect(x: 6.5, y: 9.5, width: 5, height: 5))
      head.lineWidth = 1.3
      head.stroke()
      let shoulders = NSBezierPath()
      shoulders.lineWidth = 1.3
      shoulders.lineCapStyle = .round
      shoulders.move(to: NSPoint(x: 4.5, y: 4.5))
      shoulders.curve(
        to: NSPoint(x: 13.5, y: 4.5),
        controlPoint1: NSPoint(x: 6, y: 8),
        controlPoint2: NSPoint(x: 12, y: 8)
      )
      shoulders.stroke()
    case "shippingbox", "shippingbox.fill":
      let box = NSBezierPath()
      box.lineWidth = 1.35
      box.lineJoinStyle = .round
      box.move(to: NSPoint(x: 2, y: 6))
      box.line(to: NSPoint(x: 9, y: 2.5))
      box.line(to: NSPoint(x: 16, y: 6))
      box.line(to: NSPoint(x: 16, y: 13))
      box.line(to: NSPoint(x: 9, y: 16.5))
      box.line(to: NSPoint(x: 2, y: 13))
      box.close()
      box.stroke()
      let seams = NSBezierPath()
      seams.lineWidth = 1.15
      seams.move(to: NSPoint(x: 2.2, y: 6))
      seams.line(to: NSPoint(x: 9, y: 9.5))
      seams.line(to: NSPoint(x: 15.8, y: 6))
      seams.move(to: NSPoint(x: 9, y: 9.5))
      seams.line(to: NSPoint(x: 9, y: 16))
      seams.stroke()
      if name == "shippingbox.fill" {
        let lid = NSBezierPath()
        lid.lineWidth = 1.35
        lid.move(to: NSPoint(x: 3.5, y: 6.7))
        lid.line(to: NSPoint(x: 9, y: 3.9))
        lid.line(to: NSPoint(x: 14.5, y: 6.7))
        lid.stroke()
      }
    case "key.horizontal":
      let ring = NSBezierPath(ovalIn: NSRect(x: 1.5, y: 5.5, width: 7, height: 7))
      ring.lineWidth = 1.5
      ring.stroke()
      let shaft = NSBezierPath()
      shaft.lineWidth = 1.6
      shaft.lineCapStyle = .round
      shaft.lineJoinStyle = .round
      shaft.move(to: NSPoint(x: 8, y: 9))
      shaft.line(to: NSPoint(x: 16.5, y: 9))
      shaft.move(to: NSPoint(x: 12.5, y: 9))
      shaft.line(to: NSPoint(x: 12.5, y: 6.5))
      shaft.move(to: NSPoint(x: 15, y: 9))
      shaft.line(to: NSPoint(x: 15, y: 11.5))
      shaft.stroke()
    case "sidebar.right":
      let frame = NSBezierPath(
        roundedRect: bounds.insetBy(dx: 1.5, dy: 2.5),
        xRadius: 2,
        yRadius: 2
      )
      frame.lineWidth = 1.4
      frame.stroke()
      let divider = NSBezierPath()
      divider.lineWidth = 1.4
      divider.move(to: NSPoint(x: 11.5, y: 3))
      divider.line(to: NSPoint(x: 11.5, y: 15))
      divider.stroke()
    default: return false
    }
    return true
  }
}
