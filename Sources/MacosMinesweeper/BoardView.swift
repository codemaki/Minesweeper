import AppKit

// Port of drawing.c (RedrawUIOnDC and friends) and the mouse/keyboard parts
// of WindowProc in windowing.c. Coordinates are in original pixels and are
// scaled by `zoom` when drawing and when converting mouse locations.

final class BoardView: NSView {
    let game: Game
    var zoom: CGFloat = 1.5 {
        didSet { needsDisplay = true }
    }

    /// Left/right/middle button is held on the board (HasMouseCapture)
    private var hasMouseCapture = false
    /// Mouse button held on the smile button (HandleLeftClick)
    private var smilePressed = false
    private var smileHovered = false
    /// Control-click acts as a right click; swallow its mouseUp
    private var controlClickInProgress = false

    /// XYZZY cheat: CheatPasswordIndex
    private static let cheatPassword = Array("xyzzy")
    private var cheatPasswordIndex = 0
    private var cheatPixelIsBomb: Bool?

    init(game: Game) {
        self.game = game
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: - Layout (InitializeWindowBorder)

    /// xRight
    var boardWidth: Int { game.width * Sprites.blockSize + 24 }
    /// yBottom
    var boardHeight: Int { game.height * Sprites.blockSize + 67 }

    var preferredSize: NSSize {
        NSSize(width: CGFloat(boardWidth) * zoom, height: CGFloat(boardHeight) * zoom)
    }

    private var smileOrigin: (x: Int, y: Int) { ((boardWidth - Sprites.smileSize) / 2, 16) }

    private func blockOrigin(column: Int, row: Int) -> (x: Int, y: Int) {
        (column * Sprites.blockSize - 4, row * Sprites.blockSize + 39)
    }

    private func unitPoint(_ event: NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil)
        return CGPoint(x: p.x / zoom, y: p.y / zoom)
    }

    private func boardPoint(_ p: CGPoint) -> BoardPoint {
        BoardPoint(
            column: Int(floor((p.x + 4) / CGFloat(Sprites.blockSize))),
            row: Int(floor((p.y - 39) / CGFloat(Sprites.blockSize)))
        )
    }

    private func isInSmile(_ p: CGPoint) -> Bool {
        let (x, y) = smileOrigin
        return CGRect(x: x, y: y, width: Sprites.smileSize, height: Sprites.smileSize).contains(p)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let palette = Palette(color: game.config.color)

        ctx.saveGState()
        ctx.scaleBy(x: zoom, y: zoom)
        ctx.setShouldAntialias(false)
        ctx.interpolationQuality = .none

        let xRight = boardWidth
        let yBottom = boardHeight

        Sprites.fill(ctx, 0, 0, xRight, yBottom, palette.face)

        // DrawHUDRectangles
        Sprites.bevel(ctx, 0, 0, xRight, yBottom, width: 3, raised: true, palette: palette)
        Sprites.bevel(ctx, 9, 52, xRight - 18, yBottom - 61, width: 3, raised: false, palette: palette)
        Sprites.bevel(ctx, 9, 9, xRight - 18, 37, width: 2, raised: false, palette: palette)
        Sprites.bevel(ctx, 16, 15, 41, 25, width: 1, raised: false, palette: palette)
        Sprites.bevel(ctx, xRight - 57, 15, 41, 25, width: 1, raised: false, palette: palette)

        let (smileX, smileY) = smileOrigin
        Sprites.fill(ctx, smileX - 1, smileY - 1, Sprites.smileSize + 2, Sprites.smileSize + 2, palette.shadow)

        drawLeftFlags(ctx, palette)
        drawTimer(ctx, palette, xRight: xRight)
        Sprites.drawSmile(ctx, x: smileX, y: smileY, smile: displayedSmile, palette: palette)
        drawAllBlocks(ctx, palette)

        // XYZZY: the original sets pixel (0, 0) of the desktop; use the
        // window's top-left pixel instead.
        if let isBomb = cheatPixelIsBomb {
            Sprites.fill(ctx, 0, 0, 1, 1, isBomb ? palette.black : palette.light)
        }

        ctx.restoreGState()
    }

    private var displayedSmile: Smile {
        if smilePressed {
            return smileHovered ? .clicked : game.smile
        }
        if hasMouseCapture && game.isPlaying {
            return .wow
        }
        return game.smile
    }

    private func drawLeftFlags(_ ctx: CGContext, _ palette: Palette) {
        let flags = game.leftFlags
        let digits: [Int]
        if flags >= 0 {
            let value = min(flags, 999)
            digits = [value / 100, value / 10 % 10, value % 10]
        } else {
            let value = min(-flags, 99)
            digits = [Sprites.ledMinus, value / 10, value % 10]
        }
        for (i, digit) in digits.enumerated() {
            Sprites.drawLED(ctx, x: 17 + i * Sprites.numberWidth, y: 16, digit: digit, palette: palette)
        }
    }

    private func drawTimer(_ ctx: CGContext, _ palette: Palette, xRight: Int) {
        let seconds = game.timerSeconds
        let digits = [seconds / 100, seconds / 10 % 10, seconds % 10]
        for (i, digit) in digits.enumerated() {
            Sprites.drawLED(ctx, x: xRight - 56 + i * Sprites.numberWidth, y: 16, digit: digit, palette: palette)
        }
    }

    private func drawAllBlocks(_ ctx: CGContext, _ palette: Palette) {
        for row in 1...game.height {
            for column in 1...game.width {
                let (x, y) = blockOrigin(column: column, row: row)
                let state = game.block(column: column, row: row) & BlockState.mask
                Sprites.drawBlock(ctx, x: x, y: y, state: state, palette: palette)
            }
        }
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            controlClickInProgress = true
            rightMouseDown(with: event)
            return
        }

        let p = unitPoint(event)

        if isInSmile(p) {
            smilePressed = true
            smileHovered = true
            needsDisplay = true
            return
        }

        guard game.isPlaying else { return }

        // WM_LBUTTONDOWN: Shift or the right button held means a 3x3 click.
        // Option is accepted too, for trackpads.
        let rightHeld = NSEvent.pressedMouseButtons & 0b10 != 0
        let chord = rightHeld || !event.modifierFlags.intersection([.shift, .option]).isEmpty
        captureMouseInput(at: p, chord: chord)
    }

    override func mouseDragged(with event: NSEvent) {
        let p = unitPoint(event)

        if smilePressed {
            let hovered = isInSmile(p)
            if hovered != smileHovered {
                smileHovered = hovered
                needsDisplay = true
            }
            return
        }

        mouseMoveHandler(p)
    }

    override func mouseUp(with event: NSEvent) {
        if controlClickInProgress {
            controlClickInProgress = false
            return
        }

        if smilePressed {
            smilePressed = false
            if smileHovered {
                game.newGame()
            }
            needsDisplay = true
            return
        }

        releaseMouseCapture()
    }

    override func rightMouseDown(with event: NSEvent) {
        guard game.isPlaying else { return }
        let p = unitPoint(event)

        if hasMouseCapture {
            // Left button already down: turn it into a 3x3 click
            game.switchToChord(at: boardPoint(p))
        } else if NSEvent.pressedMouseButtons & 0b1 != 0 && !controlClickInProgress && !smilePressed {
            captureMouseInput(at: p, chord: true)
        } else {
            game.toggleMark(at: boardPoint(p))
        }
    }

    override func rightMouseDragged(with event: NSEvent) {
        mouseMoveHandler(unitPoint(event))
    }

    override func rightMouseUp(with event: NSEvent) {
        releaseMouseCapture()
    }

    override func otherMouseDown(with event: NSEvent) {
        guard game.isPlaying else { return }
        captureMouseInput(at: unitPoint(event), chord: true)
    }

    override func otherMouseDragged(with event: NSEvent) {
        mouseMoveHandler(unitPoint(event))
    }

    override func otherMouseUp(with event: NSEvent) {
        releaseMouseCapture()
    }

    override func mouseMoved(with event: NSEvent) {
        updateCheatPixel(unitPoint(event), control: event.modifierFlags.contains(.control))
    }

    private func captureMouseInput(at p: CGPoint, chord: Bool) {
        hasMouseCapture = true
        game.beginPress(at: boardPoint(p), chord: chord)
        needsDisplay = true
    }

    private func mouseMoveHandler(_ p: CGPoint) {
        guard hasMouseCapture else { return }
        if game.isPlaying {
            game.movePress(to: boardPoint(p))
        } else {
            releaseMouseCapture()
        }
    }

    private func releaseMouseCapture() {
        guard hasMouseCapture else { return }
        hasMouseCapture = false
        game.endPress()
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self
        ))
    }

    // MARK: - Keyboard (KeyDownHandler)

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 120 { // F2
            game.newGame()
            return
        }

        guard let ch = event.charactersIgnoringModifiers?.lowercased().first else {
            super.keyDown(with: event)
            return
        }

        if cheatPasswordIndex < BoardView.cheatPassword.count {
            if BoardView.cheatPassword[cheatPasswordIndex] == ch {
                cheatPasswordIndex += 1
            } else {
                cheatPasswordIndex = ch == BoardView.cheatPassword[0] ? 1 : 0
            }
        }
    }

    override func flagsChanged(with event: NSEvent) {
        // VK_SHIFT: flip between the "armed" (5) and "active" (17) states
        if event.modifierFlags.contains(.shift) && cheatPasswordIndex >= 5 {
            cheatPasswordIndex ^= 0x14
        }
        super.flagsChanged(with: event)
    }

    private func updateCheatPixel(_ p: CGPoint, control: Bool) {
        guard !hasMouseCapture, cheatPasswordIndex > 5 || (cheatPasswordIndex == 5 && !control) else {
            return
        }
        let point = boardPoint(p)
        guard game.isInBoardRange(point) else { return }
        let isBomb = game.isBomb(at: point)
        if isBomb != cheatPixelIsBomb {
            cheatPixelIsBomb = isBomb
            needsDisplay = true
        }
    }
}
