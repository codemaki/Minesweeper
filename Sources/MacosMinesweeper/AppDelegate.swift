import AppKit

// Port of the window, menu and dialog parts of windowing.c:
// WinMain, MenuHandler, InitializeWindowBorder, CustomFieldDialogProc,
// SaveWinnerNameDialogProc and WinnersDialogProc.

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuItemValidation {
    private let config = GameConfig()
    private lazy var game = Game(config: config)
    private lazy var boardView = BoardView(game: game)
    private let sound = SoundPlayer()
    private var window: NSWindow!

    private static let zoomLevels: [Double] = [1, 1.5, 2, 2.5, 3]

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = makeMainMenu()

        game.delegate = self
        boardView.zoom = config.zoom

        window = NSWindow(
            contentRect: NSRect(origin: .zero, size: boardView.preferredSize),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Minesweeper"
        window.contentView = boardView
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("MinesweeperWindow")
        if !window.setFrameUsingName("MinesweeperWindow") {
            window.center()
        }

        game.newGame()
        resizeWindowToFit()

        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(boardView)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        config.save()
    }

    // MARK: - Window

    /// InitializeWindowBorder: fit the window to the board, keeping the
    /// top-left corner in place and moving it back on screen if needed.
    private func resizeWindowToFit() {
        guard let window else { return }
        let oldFrame = window.frame
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: boardView.preferredSize))
        frame.origin = NSPoint(x: oldFrame.minX, y: oldFrame.maxY - frame.height)

        if let visible = (window.screen ?? NSScreen.main)?.visibleFrame {
            frame.origin.x = min(max(frame.origin.x, visible.minX), max(visible.minX, visible.maxX - frame.width))
            frame.origin.y = max(min(frame.origin.y, visible.maxY - frame.height), visible.minY)
        }

        window.setFrame(frame, display: true, animate: false)
        boardView.needsDisplay = true
    }

    func windowWillMiniaturize(_ notification: Notification) {
        game.pause()
    }

    func windowDidDeminiaturize(_ notification: Notification) {
        game.resume()
    }

    // MARK: - Menu

    private func makeMainMenu() -> NSMenu {
        let mainMenu = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Minesweeper", action: #selector(showAbout), keyEquivalent: "").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Minesweeper", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Minesweeper", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        addSubmenu(appMenu, title: "Minesweeper", to: mainMenu)

        let gameMenu = NSMenu(title: "Game")
        addItem(gameMenu, "New", #selector(newGame), "n")
        gameMenu.addItem(.separator())
        for difficulty in [Difficulty.beginner, .intermediate, .expert] {
            let item = addItem(gameMenu, difficulty.title, #selector(selectDifficulty(_:)), "\(difficulty.rawValue + 1)")
            item.tag = difficulty.rawValue
        }
        addItem(gameMenu, "Custom…", #selector(showCustomField), "4")
        gameMenu.addItem(.separator())
        addItem(gameMenu, "Marks (?)", #selector(toggleMarks), "")
        addItem(gameMenu, "Color", #selector(toggleColor), "")
        addItem(gameMenu, "Sound", #selector(toggleSound), "")

        let zoomMenu = NSMenu(title: "Zoom")
        for (index, level) in AppDelegate.zoomLevels.enumerated() {
            let item = addItem(zoomMenu, "\(Int(level * 100))%", #selector(selectZoom(_:)), "")
            item.tag = index
        }
        addItem(zoomMenu, "Zoom In", #selector(zoomIn), "+")
        addItem(zoomMenu, "Zoom Out", #selector(zoomOut), "-")
        zoomMenu.insertItem(.separator(), at: AppDelegate.zoomLevels.count)
        let zoomItem = gameMenu.addItem(withTitle: "Zoom", action: nil, keyEquivalent: "")
        gameMenu.setSubmenu(zoomMenu, for: zoomItem)

        gameMenu.addItem(.separator())
        addItem(gameMenu, "Best Times…", #selector(showBestTimes), "")
        addSubmenu(gameMenu, title: "Game", to: mainMenu)

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        addSubmenu(windowMenu, title: "Window", to: mainMenu)
        NSApp.windowsMenu = windowMenu

        let helpMenu = NSMenu(title: "Help")
        addItem(helpMenu, "How to Play", #selector(showHowToPlay), "?")
        addSubmenu(helpMenu, title: "Help", to: mainMenu)
        NSApp.helpMenu = helpMenu

        return mainMenu
    }

    @discardableResult
    private func addItem(_ menu: NSMenu, _ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func addSubmenu(_ submenu: NSMenu, title: String, to menu: NSMenu) {
        let item = menu.addItem(withTitle: title, action: nil, keyEquivalent: "")
        menu.setSubmenu(submenu, for: item)
    }

    // InitializeCheckedMenuItems
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(selectDifficulty(_:)):
            menuItem.state = config.difficulty.rawValue == menuItem.tag ? .on : .off
        case #selector(showCustomField):
            menuItem.state = config.difficulty == .custom ? .on : .off
        case #selector(toggleMarks):
            menuItem.state = config.mark ? .on : .off
        case #selector(toggleColor):
            menuItem.state = config.color ? .on : .off
        case #selector(toggleSound):
            menuItem.state = config.sound ? .on : .off
        case #selector(selectZoom(_:)):
            menuItem.state = AppDelegate.zoomLevels[menuItem.tag] == config.zoom ? .on : .off
        case #selector(zoomIn):
            return config.zoom < AppDelegate.zoomLevels.last!
        case #selector(zoomOut):
            return config.zoom > AppDelegate.zoomLevels.first!
        default:
            break
        }
        return true
    }

    // MARK: - Menu actions (MenuHandler)

    @objc private func newGame() {
        game.newGame()
    }

    @objc private func selectDifficulty(_ sender: NSMenuItem) {
        guard let difficulty = Difficulty(rawValue: sender.tag) else { return }
        config.apply(difficulty)
        config.save()
        game.newGame()
    }

    @objc private func toggleMarks() {
        config.mark.toggle()
        config.save()
    }

    @objc private func toggleColor() {
        config.color.toggle()
        config.save()
        boardView.needsDisplay = true
    }

    @objc private func toggleSound() {
        config.sound.toggle()
        config.save()
    }

    @objc private func selectZoom(_ sender: NSMenuItem) {
        setZoom(AppDelegate.zoomLevels[sender.tag])
    }

    @objc private func zoomIn() {
        if let level = AppDelegate.zoomLevels.first(where: { $0 > config.zoom }) {
            setZoom(level)
        }
    }

    @objc private func zoomOut() {
        if let level = AppDelegate.zoomLevels.last(where: { $0 < config.zoom }) {
            setZoom(level)
        }
    }

    private func setZoom(_ zoom: Double) {
        config.zoom = zoom
        config.save()
        boardView.zoom = zoom
        resizeWindowToFit()
    }

    @objc private func showAbout() {
        let credits = NSAttributedString(
            string: "A macOS port of the Windows XP Minesweeper,\nbased on the ReversingMinesweeper reconstruction.",
            attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)]
        )
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Minesweeper",
            .credits: credits,
        ])
    }

    @objc private func showHowToPlay() {
        let alert = NSAlert()
        alert.messageText = "How to Play"
        alert.informativeText = """
        Uncover every square that does not hide a mine.

        • Click a square to uncover it. The number tells how many mines touch it.
        • Right-click (or Control-click) to place a flag, then a question mark.
        • Click a number with both buttons, the middle button, or Shift/Option-click \
        to uncover its neighbours when enough flags are placed.
        • Click the smiley face or press F2 / ⌘N to start a new game.
        """
        alert.runModal()
    }

    // CustomFieldDialogProc
    @objc private func showCustomField() {
        let alert = NSAlert()
        alert.messageText = "Custom Field"
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        func field(_ value: Int) -> NSTextField {
            let field = NSTextField(string: "\(value)")
            field.alignment = .right
            field.widthAnchor.constraint(equalToConstant: 60).isActive = true
            return field
        }
        let heightField = field(config.height)
        let widthField = field(config.width)
        let minesField = field(config.mines)

        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "Height:"), heightField],
            [NSTextField(labelWithString: "Width:"), widthField],
            [NSTextField(labelWithString: "Mines:"), minesField],
        ])
        grid.rowSpacing = 8
        grid.column(at: 0).xPlacement = .trailing
        grid.frame = NSRect(x: 0, y: 0, width: 160, height: 86)
        alert.accessoryView = grid
        alert.window.initialFirstResponder = heightField

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        config.applyCustom(
            height: heightField.integerValue,
            width: widthField.integerValue,
            mines: minesField.integerValue
        )
        config.save()
        game.newGame()
    }

    // SaveWinnerNameDialogProc
    private func askWinnerName(_ difficulty: Difficulty) {
        let alert = NSAlert()
        alert.messageText = "You have the fastest time for \(difficulty.title.lowercased()) level."
        alert.informativeText = "Please enter your name."
        alert.addButton(withTitle: "OK")

        let nameField = NSTextField(string: config.names[difficulty.rawValue])
        nameField.frame = NSRect(x: 0, y: 0, width: 220, height: 24)
        alert.accessoryView = nameField
        alert.window.initialFirstResponder = nameField
        alert.runModal()

        let name = String(nameField.stringValue.trimmingCharacters(in: .whitespaces).prefix(32))
        config.names[difficulty.rawValue] = name.isEmpty ? GameConfig.anonymous : name
        config.save()
    }

    // WinnersDialogProc
    @objc private func showBestTimes() {
        while true {
            let alert = NSAlert()
            alert.messageText = "Fastest Mine Sweepers"
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Reset Scores")

            let rows = [Difficulty.beginner, .intermediate, .expert].map { difficulty -> [NSView] in
                let time = NSTextField(labelWithString: "\(config.times[difficulty.rawValue]) seconds")
                time.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
                return [
                    NSTextField(labelWithString: "\(difficulty.title):"),
                    time,
                    NSTextField(labelWithString: config.names[difficulty.rawValue]),
                ]
            }
            let grid = NSGridView(views: rows)
            grid.rowSpacing = 6
            grid.columnSpacing = 16
            grid.frame = NSRect(x: 0, y: 0, width: 300, height: 70)
            alert.accessoryView = grid

            guard alert.runModal() == .alertSecondButtonReturn else { return }
            config.resetBestTimes()
            config.save()
        }
    }
}

// MARK: - GameDelegate

extension AppDelegate: GameDelegate {
    func gameNeedsDisplay(_ game: Game) {
        boardView.needsDisplay = true
    }

    func gameBoardSizeChanged(_ game: Game) {
        resizeWindowToFit()
    }

    func game(_ game: Game, play gameSound: GameSound) {
        if config.sound {
            sound.play(gameSound)
        }
    }

    func gameDidSetBestTime(_ game: Game, difficulty: Difficulty) {
        // Let the finished board draw before the modal dialogs appear
        DispatchQueue.main.async {
            self.askWinnerName(difficulty)
            self.showBestTimes()
        }
    }
}
