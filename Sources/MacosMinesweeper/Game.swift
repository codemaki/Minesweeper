import Foundation

// Port of game.c.
//
// The board keeps the original byte layout:
//   [ is_bomb: 0x80 ][ revealed: 0x40 ][ unused: 0x20 ][ state: 0x1F ]
// with a border of BLOCK_STATE_BORDER_VALUE around the playing field, so the
// neighbour loops never need bounds checks.
//
// Places marked "FIX" deviate from the reversed binary where it has a bug
// (see the WIERD comments in ReversingMinesweeper/Minesweeper/game.c).

struct BoardPoint: Equatable {
    var column: Int
    var row: Int

    static let none = BoardPoint(column: -1, row: -1)
    static let released = BoardPoint(column: -2, row: -2)
}

enum BlockState {
    static let border: UInt8 = 0x10
    static let emptyUnclicked: UInt8 = 0x0F
    static let flag: UInt8 = 0x0E
    static let questionMark: UInt8 = 0x0D
    static let bombRedBackground: UInt8 = 0x0C
    static let bombWithX: UInt8 = 0x0B
    static let blackBomb: UInt8 = 0x0A
    static let clickedQuestionMark: UInt8 = 0x09
    static let readEmpty: UInt8 = 0x00
    static let mask: UInt8 = 0x1F

    static let isRevealed: UInt8 = 0x40
    static let isBomb: UInt8 = 0x80
}

enum Smile: Int {
    case normal = 0
    case wow = 1
    case lost = 2
    case winner = 3
    case clicked = 4
}

enum GameSound {
    case tick, win, lose
}

protocol GameDelegate: AnyObject {
    func gameNeedsDisplay(_ game: Game)
    func gameBoardSizeChanged(_ game: Game)
    func game(_ game: Game, play sound: GameSound)
    func gameDidSetBestTime(_ game: Game, difficulty: Difficulty)
}

final class Game {
    static let maxRows = 27
    static let maxColumns = 32

    weak var delegate: GameDelegate?
    let config: GameConfig

    private(set) var blocks = [[UInt8]](
        repeating: [UInt8](repeating: BlockState.emptyUnclicked, count: Game.maxColumns),
        count: Game.maxRows
    )
    private(set) var width = 0
    private(set) var height = 0
    private(set) var leftFlags = 0
    private(set) var timerSeconds = 0
    private(set) var smile = Smile.normal

    /// STATE_GAME_IS_ON
    private(set) var isPlaying = false
    /// STATE_WINDOW_MINIMIZED
    var isPaused = false

    /// IsTimerOnAndShowed
    private var isTimerOn = false
    private var timer: Timer?

    private(set) var clickedBlock = BoardPoint.none
    private(set) var is3x3Click = false

    private var numberOfEmptyBlocks = 0
    private var numberOfRevealedBlocks = 0

    init(config: GameConfig) {
        self.config = config
        width = config.width
        height = config.height
        initializeBlockArrayBorders()
    }

    func block(column: Int, row: Int) -> UInt8 {
        blocks[row][column]
    }

    private subscript(point: BoardPoint) -> UInt8 {
        get { blocks[point.row][point.column] }
        set { blocks[point.row][point.column] = newValue }
    }

    // MARK: - Setup

    private func initializeBlockArrayBorders() {
        for row in 0..<Game.maxRows {
            for column in 0..<Game.maxColumns {
                blocks[row][column] = BlockState.emptyUnclicked
            }
        }

        for column in 0...(width + 1) {
            blocks[0][column] = BlockState.border
            blocks[height + 1][column] = BlockState.border
        }

        // FIX: the reversed loop counts `row++` from Height + 1 and never ends
        for row in 0...(height + 1) {
            blocks[row][0] = BlockState.border
            blocks[row][width + 1] = BlockState.border
        }
    }

    func newGame() {
        let sizeChanged = config.width != width || config.height != height

        width = config.width
        height = config.height

        initializeBlockArrayBorders()
        smile = .normal

        var minesToPlace = config.mines
        while minesToPlace > 0 {
            let point = BoardPoint(
                column: Int.random(in: 0..<width) + 1,
                row: Int.random(in: 0..<height) + 1
            )
            if self[point] & BlockState.isBomb == 0 {
                self[point] |= BlockState.isBomb
                minesToPlace -= 1
            }
        }

        stopTimer()
        timerSeconds = 0
        leftFlags = config.mines
        numberOfRevealedBlocks = 0
        numberOfEmptyBlocks = height * width - config.mines
        clickedBlock = .none
        isPlaying = true

        if sizeChanged {
            delegate?.gameBoardSizeChanged(self)
        }
        delegate?.gameNeedsDisplay(self)
    }

    // MARK: - Timer

    private func startTimer() {
        isTimerOn = true
        timer?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.tickSeconds()
        }
        // .common keeps the clock running while a menu is being tracked,
        // like WM_TIMER does inside the Windows menu loop.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTimer() {
        isTimerOn = false
        timer?.invalidate()
        timer = nil
    }

    private func tickSeconds() {
        if isTimerOn && !isPaused && timerSeconds < GameConfig.maxTime {
            timerSeconds += 1
            delegate?.game(self, play: .tick)
            delegate?.gameNeedsDisplay(self)
        }
    }

    // MARK: - Helpers

    func isInBoardRange(_ point: BoardPoint) -> Bool {
        point.column > 0 && point.row > 0 && point.column <= width && point.row <= height
    }

    private func state(_ point: BoardPoint) -> UInt8 {
        self[point] & BlockState.mask
    }

    private func isRevealed(_ point: BoardPoint) -> Bool {
        self[point] & BlockState.isRevealed != 0
    }

    private func changeBlockState(_ point: BoardPoint, _ blockState: UInt8) {
        self[point] = (self[point] & 0xE0) | blockState
    }

    private func neighbours(of point: BoardPoint) -> [BoardPoint] {
        var result: [BoardPoint] = []
        for row in (point.row - 1)...(point.row + 1) {
            for column in (point.column - 1)...(point.column + 1) {
                result.append(BoardPoint(column: column, row: row))
            }
        }
        return result
    }

    private func countNearBombs(_ point: BoardPoint) -> Int {
        neighbours(of: point).filter { self[$0] & BlockState.isBomb != 0 }.count
    }

    private func flagBlocksCount(_ point: BoardPoint) -> Int {
        neighbours(of: point).filter { state($0) == BlockState.flag }.count
    }

    // MARK: - Pressed-block visuals

    private func updateBlockStateToClicked(_ point: BoardPoint) {
        // FIX: the reversed code compared the unmasked byte, so pressing
        // a hidden bomb did not look pressed.
        switch state(point) {
        case BlockState.questionMark: changeBlockState(point, BlockState.clickedQuestionMark)
        case BlockState.emptyUnclicked: changeBlockState(point, BlockState.readEmpty)
        default: break
        }
    }

    private func updateBlockStateToUnclicked(_ point: BoardPoint) {
        switch state(point) {
        case BlockState.clickedQuestionMark: changeBlockState(point, BlockState.questionMark)
        case BlockState.readEmpty: changeBlockState(point, BlockState.emptyUnclicked)
        default: break
        }
    }

    private func clampedArea(around point: BoardPoint) -> [BoardPoint] {
        guard height > 0, width > 0 else { return [] }
        let top = max(1, point.row - 1), bottom = min(height, point.row + 1)
        let left = max(1, point.column - 1), right = min(width, point.column + 1)
        guard top <= bottom, left <= right else { return [] }
        var result: [BoardPoint] = []
        for row in top...bottom {
            for column in left...right {
                result.append(BoardPoint(column: column, row: row))
            }
        }
        return result
    }

    private func updateClickedBlocksState(_ point: BoardPoint) {
        guard point != clickedBlock else { return }

        let oldClick = clickedBlock
        clickedBlock = point

        if is3x3Click {
            for p in clampedArea(around: oldClick) where !isRevealed(p) {
                updateBlockStateToUnclicked(p)
            }
            if isInBoardRange(point) {
                for p in clampedArea(around: point) where !isRevealed(p) {
                    updateBlockStateToClicked(p)
                }
            }
        } else {
            if isInBoardRange(oldClick) && !isRevealed(oldClick) {
                updateBlockStateToUnclicked(oldClick)
            }
            if isInBoardRange(point) && !isRevealed(point) && state(point) != BlockState.flag {
                updateBlockStateToClicked(point)
            }
        }

        delegate?.gameNeedsDisplay(self)
    }

    private func releaseBlocksClick() {
        updateClickedBlocksState(.released)
    }

    // MARK: - Mouse input (CaptureMouseInput / MouseMoveHandler / ReleaseMouseCapture)

    func beginPress(at point: BoardPoint, chord: Bool) {
        guard isPlaying else { return }
        is3x3Click = chord
        clickedBlock = .none
        updateClickedBlocksState(point)
    }

    func movePress(to point: BoardPoint) {
        guard isPlaying else { return }
        updateClickedBlocksState(point)
    }

    /// Right button pressed while the left button is held down.
    func switchToChord(at point: BoardPoint) {
        guard isPlaying else { return }
        releaseBlocksClick()
        is3x3Click = true
        updateClickedBlocksState(point)
    }

    func endPress() {
        if isPlaying {
            handleBlockClick()
        } else {
            releaseBlocksClick()
        }
    }

    // MARK: - Game actions

    /// HandleBlockClick
    private func handleBlockClick() {
        guard isInBoardRange(clickedBlock) else {
            delegate?.gameNeedsDisplay(self)
            return
        }

        if numberOfRevealedBlocks == 0 && timerSeconds == 0 {
            // First click! Initialize timer
            delegate?.game(self, play: .tick)
            timerSeconds += 1
            startTimer()
        }

        if is3x3Click {
            handle3x3BlockClick(clickedBlock)
        } else if !isRevealed(clickedBlock) && state(clickedBlock) != BlockState.flag {
            handleNormalBlockClick(clickedBlock)
        }

        delegate?.gameNeedsDisplay(self)
    }

    /// HandleRightClick
    func toggleMark(at point: BoardPoint) {
        guard isPlaying, isInBoardRange(point), !isRevealed(point) else { return }

        let newState: UInt8
        switch state(point) {
        case BlockState.flag:
            newState = config.mark ? BlockState.questionMark : BlockState.emptyUnclicked
            leftFlags += 1
        case BlockState.questionMark:
            newState = BlockState.emptyUnclicked
        default:
            newState = BlockState.flag
            leftFlags -= 1
        }

        changeBlockState(point, newState)
        delegate?.gameNeedsDisplay(self)
    }

    private func handleNormalBlockClick(_ point: BoardPoint) {
        if self[point] & BlockState.isBomb == 0 {
            expandEmptyBlock(point)
            checkForWin()
        } else if numberOfRevealedBlocks == 0 {
            replaceFirstNonBomb(point)
            checkForWin()
        } else {
            changeBlockState(point, BlockState.isRevealed | BlockState.bombRedBackground)
            finishGame(won: false)
        }
    }

    /// The very first click never hits a bomb: move it to the first
    /// free block (scanning from the top-left corner).
    private func replaceFirstNonBomb(_ point: BoardPoint) {
        // FIX: the reversed loops use `<` and skip the last row and column
        for row in 1...height {
            for column in 1...width {
                let candidate = BoardPoint(column: column, row: row)
                if self[candidate] & BlockState.isBomb == 0 {
                    self[point] = BlockState.emptyUnclicked
                    self[candidate] |= BlockState.isBomb
                    expandEmptyBlock(point)
                    return
                }
            }
        }
    }

    private func handle3x3BlockClick(_ point: BoardPoint) {
        // FIX: compare against the block's number, not the raw byte
        // (which includes the revealed bit and never matches).
        guard isRevealed(point), flagBlocksCount(point) == Int(state(point)) else {
            releaseBlocksClick()
            return
        }

        var lostGame = false

        for p in neighbours(of: point) {
            // FIX: skip flagged blocks by their masked state
            if state(p) == BlockState.flag || isRevealed(p) {
                continue
            }
            if self[p] & BlockState.isBomb == 0 {
                expandEmptyBlock(p)
            } else {
                lostGame = true
                changeBlockState(p, BlockState.isRevealed | BlockState.bombRedBackground)
            }
        }

        if lostGame {
            finishGame(won: false)
        } else {
            checkForWin()
        }
    }

    private func checkForWin() {
        if isPlaying && numberOfRevealedBlocks == numberOfEmptyBlocks {
            finishGame(won: true)
        }
    }

    /// ShowBlockValue: returns true when the block became an empty (0) block.
    private func showBlockValue(_ point: BoardPoint) -> Bool {
        guard !isRevealed(point) else { return false }

        let blockState = state(point)
        if blockState == BlockState.border || blockState == BlockState.flag {
            return false
        }

        numberOfRevealedBlocks += 1
        let nearBombs = UInt8(countNearBombs(point))
        self[point] = nearBombs | BlockState.isRevealed
        return nearBombs == 0
    }

    /// ExpandEmptyBlock. FIX: the original uses a 100-entry ring buffer that
    /// can overflow on large boards; a plain queue is used instead.
    private func expandEmptyBlock(_ point: BoardPoint) {
        guard showBlockValue(point) else { return }

        var queue = [point]
        var index = 0
        while index < queue.count {
            let current = queue[index]
            index += 1
            for p in neighbours(of: current) where p != current {
                if showBlockValue(p) {
                    queue.append(p)
                }
            }
        }
    }

    private func revealAllBombs(_ revealedBombsState: UInt8) {
        for row in 1...height {
            for column in 1...width {
                let p = BoardPoint(column: column, row: row)
                if isRevealed(p) {
                    continue
                }
                if self[p] & BlockState.isBomb != 0 {
                    if state(p) != BlockState.flag {
                        changeBlockState(p, revealedBombsState)
                    }
                } else if state(p) == BlockState.flag {
                    // Flagged by the player, but not a bomb
                    changeBlockState(p, BlockState.bombWithX)
                }
            }
        }
    }

    private func finishGame(won: Bool) {
        stopTimer()
        smile = won ? .winner : .lost

        revealAllBombs(won ? BlockState.flag : BlockState.blackBomb)

        if won {
            leftFlags = 0
        }

        delegate?.game(self, play: won ? .win : .lose)
        isPlaying = false
        delegate?.gameNeedsDisplay(self)

        let difficulty = config.difficulty
        if won && difficulty != .custom && timerSeconds < config.times[difficulty.rawValue] {
            config.times[difficulty.rawValue] = timerSeconds
            delegate?.gameDidSetBestTime(self, difficulty: difficulty)
        }
    }

    // MARK: - Window minimize (NotifyMinimize / NotifyWindowRestore)

    func pause() {
        isPaused = true
    }

    func resume() {
        isPaused = false
    }

    // MARK: - XYZZY

    func isBomb(at point: BoardPoint) -> Bool {
        isInBoardRange(point) && self[point] & BlockState.isBomb != 0
    }
}
