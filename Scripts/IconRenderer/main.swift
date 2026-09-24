import AppKit

// Renders the app icon from the same pixel sprites the game uses.
// Usage: IconRenderer <output.iconset>

let output = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func render(size: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    let palette = Palette(color: true)
    let scale = CGFloat(size) / 1024

    // macOS icon grid: 824pt rounded square centred in a 1024 canvas
    let inset = 100 * scale
    let side = 824 * scale
    let tile = CGRect(x: inset, y: inset, width: side, height: side)
    ctx.addPath(CGPath(roundedRect: tile, cornerWidth: 185 * scale, cornerHeight: 185 * scale, transform: nil))
    ctx.clip()

    // Flip to the top-left origin the sprites use, then draw one 16x16 block
    ctx.translateBy(x: inset, y: inset + side)
    ctx.scaleBy(x: side / 16, y: -side / 16)
    ctx.setShouldAntialias(false)
    Sprites.fill(ctx, 0, 0, 16, 16, palette.face)
    Sprites.bevel(ctx, 0, 0, 16, 16, width: 1, raised: true, palette: palette)
    Sprites.pixels(ctx, 1, 1, Sprites.mine.map { "." + $0 }, ["#": palette.black, "W": palette.light])

    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try render(size: base).write(to: output.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(size: base * 2).write(to: output.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
