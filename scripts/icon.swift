import AppKit
let directory = CommandLine.arguments[1]
for size in [16,32,128,256,512] {
    for scale in [1,2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,pixelsWide: pixels,pixelsHigh: pixels,bitsPerSample: 8,samplesPerPixel: 4,hasAlpha: true,isPlanar: false,colorSpaceName: .deviceRGB,bytesPerRow: 0,bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
        let factor = CGFloat(pixels) / 1024
        let transform = NSAffineTransform(); transform.scale(by: factor); transform.concat()
        NSColor(calibratedRed: 0.10,green: 0.12,blue: 0.15,alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 64,y: 64,width: 896,height: 896),xRadius: 190,yRadius: 190).fill()
        NSColor(calibratedRed: 0.50,green: 0.80,blue: 0.87,alpha: 1).setFill()
        // Three staggered edit strips form an original R/play monogram.
        NSBezierPath(rect: NSRect(x: 280,y: 282,width: 90,height: 460)).fill()
        let top = NSBezierPath(); top.move(to: NSPoint(x: 400,y: 742)); top.line(to: NSPoint(x: 724,y: 585)); top.line(to: NSPoint(x: 400,y: 426)); top.close(); top.fill()
        let leg = NSBezierPath(); leg.move(to: NSPoint(x: 442,y: 404)); leg.line(to: NSPoint(x: 564,y: 464)); leg.line(to: NSPoint(x: 735,y: 282)); leg.line(to: NSPoint(x: 585,y: 282)); leg.close(); leg.fill()
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png,properties: [:])!.write(to: URL(fileURLWithPath: "\(directory)/icon_\(size)x\(size)\(suffix).png"))
    }
}
