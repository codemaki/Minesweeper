import AppKit

// Replacement for the bitmap resources (ID_BITMAP_BLOCK / NUMBERS / SMILES)
// that drawing.c blits with SetDIBitsToDevice. Everything is drawn in
// "original pixels"; BoardView scales the context by the zoom factor.

struct Palette {
    let color: Bool

    static func rgb(_ r: Int, _ g: Int, _ b: Int) -> CGColor {
        CGColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
    }

    let face = rgb(192, 192, 192)
    let light = rgb(255, 255, 255)
    let shadow = rgb(128, 128, 128)
    let black = rgb(0, 0, 0)

    var red: CGColor { color ? Self.rgb(255, 0, 0) : black }
    var explodeBackground: CGColor { color ? Self.rgb(255, 0, 0) : shadow }
    var ledOn: CGColor { color ? Self.rgb(255, 0, 0) : light }
    var ledOff: CGColor { color ? Self.rgb(128, 0, 0) : Self.rgb(48, 48, 48) }
    var smileFace: CGColor { color ? Self.rgb(255, 255, 0) : light }

    func number(_ n: Int) -> CGColor {
        guard color else { return black }
        switch n {
        case 1: return Self.rgb(0, 0, 255)
        case 2: return Self.rgb(0, 128, 0)
        case 3: return Self.rgb(255, 0, 0)
        case 4: return Self.rgb(0, 0, 128)
        case 5: return Self.rgb(128, 0, 0)
        case 6: return Self.rgb(0, 128, 128)
        case 7: return Self.rgb(0, 0, 0)
        default: return Self.rgb(128, 128, 128)
        }
    }
}

enum Sprites {
    static let blockSize = 16
    static let numberWidth = 13
    static let numberHeight = 23
    static let smileSize = 24

    // MARK: - Primitive helpers

    static func fill(_ ctx: CGContext, _ x: Int, _ y: Int, _ w: Int, _ h: Int, _ color: CGColor) {
        ctx.setFillColor(color)
        ctx.fill(CGRect(x: x, y: y, width: w, height: h))
    }

    /// Windows style 3D border (DrawHUDRectangle). `raised` puts the light
    /// colour on the top/left edges, otherwise on the bottom/right edges.
    static func bevel(_ ctx: CGContext, _ x: Int, _ y: Int, _ w: Int, _ h: Int,
                      width: Int, raised: Bool, palette: Palette) {
        let topLeft = raised ? palette.light : palette.shadow
        let bottomRight = raised ? palette.shadow : palette.light
        for i in 0..<width {
            fill(ctx, x, y + i, w - i, 1, topLeft)                   // top
            fill(ctx, x + i, y, 1, h - i, topLeft)                   // left
            fill(ctx, x + i + 1, y + h - 1 - i, w - i - 1, 1, bottomRight) // bottom
            fill(ctx, x + w - 1 - i, y + i + 1, 1, h - i - 1, bottomRight) // right
        }
    }

    /// Draws a pixel map. Characters map to colours, '.' is transparent.
    static func pixels(_ ctx: CGContext, _ x: Int, _ y: Int, _ rows: [String], _ colors: [Character: CGColor]) {
        for (dy, line) in rows.enumerated() {
            for (dx, ch) in line.enumerated() {
                if let color = colors[ch] {
                    fill(ctx, x + dx, y + dy, 1, 1, color)
                }
            }
        }
    }

    // MARK: - Pixel maps

    static let digits: [[String]] = [
        [],
        ["....##..",
         "...###..",
         "..####..",
         ".#####..",
         "...###..",
         "...###..",
         "...###..",
         "...###..",
         ".#######",
         ".#######"],
        [".######.",
         "########",
         "###..###",
         "....###.",
         "...###..",
         "..###...",
         ".###....",
         "###.....",
         "########",
         "########"],
        ["#######.",
         "########",
         ".....###",
         ".....###",
         "..#####.",
         "..#####.",
         ".....###",
         ".....###",
         "########",
         "#######."],
        [".###.###",
         ".###.###",
         "###..###",
         "###..###",
         "########",
         "########",
         ".....###",
         ".....###",
         ".....###",
         ".....###"],
        ["########",
         "########",
         "###.....",
         "###.....",
         "#######.",
         "########",
         ".....###",
         ".....###",
         "########",
         "#######."],
        [".#######",
         "########",
         "###.....",
         "###.....",
         "#######.",
         "########",
         "###..###",
         "###..###",
         "########",
         ".######."],
        ["########",
         "########",
         ".....###",
         ".....###",
         "....###.",
         "....###.",
         "...###..",
         "...###..",
         "..###...",
         "..###..."],
        [".######.",
         "########",
         "###..###",
         "###..###",
         ".######.",
         ".######.",
         "###..###",
         "###..###",
         "########",
         ".######."],
    ]

    static let mine = [
        "......#......",
        "......#......",
        "..#.#####.#..",
        "...#######...",
        "..##WW#####..",
        "..##WW#####..",
        "#############",
        "..#########..",
        "..#########..",
        "...#######...",
        "..#.#####.#..",
        "......#......",
        "......#......",
    ]

    static let flag = [
        "....RR....",
        "..RRRR....",
        ".RRRRR....",
        "..RRRR....",
        "....RR....",
        ".....#....",
        ".....#....",
        "...####...",
        ".########.",
        ".########.",
    ]

    static let question = [
        "..####..",
        ".##..##.",
        ".##..##.",
        "....##..",
        "...##...",
        "...##...",
        "........",
        "...##...",
        "...##...",
    ]

    // MARK: - Blocks

    /// Draws one 16x16 block for a BLOCK_STATE_* value (BlockStates[] in drawing.c).
    static func drawBlock(_ ctx: CGContext, x: Int, y: Int, state: UInt8, palette: Palette) {
        let size = blockSize

        func raisedBlock() {
            fill(ctx, x, y, size, size, palette.face)
            bevel(ctx, x, y, size, size, width: 2, raised: true, palette: palette)
        }

        func revealedBlock(_ background: CGColor) {
            fill(ctx, x, y, size, size, background)
            fill(ctx, x, y, size, 1, palette.shadow)
            fill(ctx, x, y, 1, size, palette.shadow)
        }

        func drawMine() {
            pixels(ctx, x + 2, y + 2, mine, ["#": palette.black, "W": palette.light])
        }

        switch state {
        case BlockState.emptyUnclicked:
            raisedBlock()
        case BlockState.flag:
            raisedBlock()
            pixels(ctx, x + 3, y + 3, flag, ["R": palette.red, "#": palette.black])
        case BlockState.questionMark:
            raisedBlock()
            pixels(ctx, x + 4, y + 3, question, ["#": palette.black])
        case BlockState.bombRedBackground:
            revealedBlock(palette.explodeBackground)
            drawMine()
        case BlockState.bombWithX:
            revealedBlock(palette.face)
            drawMine()
            for i in 0..<10 {
                fill(ctx, x + 3 + i, y + 3 + i, 2, 1, palette.red)
                fill(ctx, x + 12 - i, y + 3 + i, 2, 1, palette.red)
            }
        case BlockState.blackBomb:
            revealedBlock(palette.face)
            drawMine()
        case BlockState.clickedQuestionMark:
            revealedBlock(palette.face)
            pixels(ctx, x + 4, y + 4, question, ["#": palette.black])
        case 1...8:
            revealedBlock(palette.face)
            let n = Int(state)
            pixels(ctx, x + 4, y + 3, digits[n], ["#": palette.number(n)])
        default:
            revealedBlock(palette.face)
        }
    }

    // MARK: - LED numbers (13 x 23)

    // Segments a..g, each a list of (x, y, w, h) pixel runs.
    private static let segments: [[(Int, Int, Int, Int)]] = [
        [(2, 1, 9, 1), (3, 2, 7, 1), (4, 3, 5, 1)],       // a: top
        [(11, 2, 1, 9), (10, 3, 1, 7), (9, 4, 1, 5)],     // b: upper right
        [(11, 12, 1, 9), (10, 13, 1, 7), (9, 14, 1, 5)],  // c: lower right
        [(4, 19, 5, 1), (3, 20, 7, 1), (2, 21, 9, 1)],    // d: bottom
        [(1, 12, 1, 9), (2, 13, 1, 7), (3, 14, 1, 5)],    // e: lower left
        [(1, 2, 1, 9), (2, 3, 1, 7), (3, 4, 1, 5)],       // f: upper left
        [(3, 10, 7, 1), (2, 11, 9, 1), (3, 12, 7, 1)],    // g: middle
    ]

    private static let digitSegments: [String] = [
        "abcdef", "bc", "abdeg", "abcdg", "bcfg", "acdfg", "acdefg", "abc", "abcdefg", "abcdfg",
    ]

    static let ledMinus = 10

    static func drawLED(_ ctx: CGContext, x: Int, y: Int, digit: Int, palette: Palette) {
        fill(ctx, x, y, numberWidth, numberHeight, palette.black)
        let lit = digit == ledMinus ? "g" : digitSegments[digit]
        for (index, name) in "abcdefg".enumerated() {
            let color = lit.contains(name) ? palette.ledOn : palette.ledOff
            for (sx, sy, sw, sh) in segments[index] {
                fill(ctx, x + sx, y + sy, sw, sh, color)
            }
        }
    }

    // MARK: - Smile button (24 x 24)

    static func drawSmile(_ ctx: CGContext, x: Int, y: Int, smile: Smile, palette: Palette) {
        let pressed = smile == .clicked
        fill(ctx, x, y, smileSize, smileSize, palette.face)
        if pressed {
            fill(ctx, x, y, smileSize, 1, palette.shadow)
            fill(ctx, x, y, 1, smileSize, palette.shadow)
        } else {
            bevel(ctx, x, y, smileSize, smileSize, width: 2, raised: true, palette: palette)
        }

        let offset: CGFloat = pressed ? 1 : 0
        let cx = CGFloat(x) + 12 + offset
        let cy = CGFloat(y) + 12 + offset

        ctx.saveGState()
        ctx.setShouldAntialias(true)

        // Face
        ctx.setFillColor(palette.smileFace)
        ctx.setStrokeColor(palette.black)
        ctx.setLineWidth(1)
        let face = CGRect(x: cx - 8.5, y: cy - 8.5, width: 17, height: 17)
        ctx.fillEllipse(in: face)
        ctx.strokeEllipse(in: face)

        ctx.setFillColor(palette.black)
        ctx.setStrokeColor(palette.black)

        func eyes() {
            ctx.fill(CGRect(x: cx - 4, y: cy - 4, width: 2, height: 2))
            ctx.fill(CGRect(x: cx + 2, y: cy - 4, width: 2, height: 2))
        }

        func mouthArc(up: Bool) {
            ctx.setLineWidth(1.2)
            ctx.beginPath()
            if up {
                ctx.addArc(center: CGPoint(x: cx, y: cy - 1), radius: 5,
                           startAngle: .pi * 0.2, endAngle: .pi * 0.8, clockwise: false)
            } else {
                ctx.addArc(center: CGPoint(x: cx, y: cy + 8), radius: 5,
                           startAngle: .pi * 1.25, endAngle: .pi * 1.75, clockwise: false)
            }
            ctx.strokePath()
        }

        switch smile {
        case .normal, .clicked:
            eyes()
            mouthArc(up: true)
        case .wow:
            eyes()
            ctx.setLineWidth(1.2)
            ctx.strokeEllipse(in: CGRect(x: cx - 2, y: cy + 1.5, width: 4, height: 4))
        case .lost:
            ctx.setLineWidth(1)
            for ex in [cx - 3, cx + 3] {
                ctx.beginPath()
                ctx.move(to: CGPoint(x: ex - 1.5, y: cy - 4.5))
                ctx.addLine(to: CGPoint(x: ex + 1.5, y: cy - 1.5))
                ctx.move(to: CGPoint(x: ex + 1.5, y: cy - 4.5))
                ctx.addLine(to: CGPoint(x: ex - 1.5, y: cy - 1.5))
                ctx.strokePath()
            }
            mouthArc(up: false)
        case .winner:
            // Sunglasses
            ctx.fill(CGRect(x: cx - 7, y: cy - 4, width: 14, height: 1))
            ctx.fill(CGRect(x: cx - 6, y: cy - 4, width: 5, height: 3))
            ctx.fill(CGRect(x: cx + 1, y: cy - 4, width: 5, height: 3))
            mouthArc(up: true)
        }

        ctx.restoreGState()
    }
}
