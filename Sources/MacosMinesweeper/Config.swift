import Foundation

// Port of config.c. The Windows registry (HKCU\Software\Microsoft\winmine)
// is replaced by UserDefaults, but the value names and ranges are the same.

enum Difficulty: Int, CaseIterable {
    case beginner = 0
    case intermediate = 1
    case expert = 2
    case custom = 3

    var title: String {
        switch self {
        case .beginner: return "Beginner"
        case .intermediate: return "Intermediate"
        case .expert: return "Expert"
        case .custom: return "Custom"
        }
    }

    // DifficultyConfigTable from windowing.c
    var preset: (mines: Int, height: Int, width: Int)? {
        switch self {
        case .beginner: return (10, 9, 9)
        case .intermediate: return (40, 16, 16)
        case .expert: return (99, 16, 30)
        case .custom: return nil
        }
    }
}

final class GameConfig {
    static let anonymous = "Anonymous"
    static let maxTime = 999

    // Limits from CustomFieldDialogProc
    static let heightRange = 9...24
    static let widthRange = 9...30

    static func minesRange(height: Int, width: Int) -> ClosedRange<Int> {
        10...min((height - 1) * (width - 1), 999)
    }

    var difficulty: Difficulty = .beginner
    var mines = 10
    var height = 9
    var width = 9
    var mark = true
    var color = true
    var sound = false
    var zoom: Double = 1.5
    var times = [maxTime, maxTime, maxTime]
    var names = [anonymous, anonymous, anonymous]

    private let defaults = UserDefaults.standard

    init() {
        load()
    }

    func apply(_ difficulty: Difficulty) {
        self.difficulty = difficulty
        if let preset = difficulty.preset {
            mines = preset.mines
            height = preset.height
            width = preset.width
        }
    }

    func applyCustom(height: Int, width: Int, mines: Int) {
        self.height = height.clamped(to: Self.heightRange)
        self.width = width.clamped(to: Self.widthRange)
        self.mines = mines.clamped(to: Self.minesRange(height: self.height, width: self.width))
        difficulty = .custom
    }

    func resetBestTimes() {
        times = [Self.maxTime, Self.maxTime, Self.maxTime]
        names = [Self.anonymous, Self.anonymous, Self.anonymous]
    }

    // InitializeConfigFromRegistry
    func load() {
        difficulty = Difficulty(rawValue: integer("Difficulty", 0, 0...3)) ?? .beginner
        height = integer("Height", 9, Self.heightRange)
        width = integer("Width", 9, Self.widthRange)
        mines = integer("Mines", 10, Self.minesRange(height: height, width: width))
        mark = integer("Mark", 1, 0...1) == 1
        color = integer("Color", 1, 0...1) == 1
        sound = integer("Sound", 0, 0...1) == 1
        zoom = defaults.object(forKey: "Zoom") as? Double ?? 1.5
        times = [
            integer("Time1", Self.maxTime, 0...Self.maxTime),
            integer("Time2", Self.maxTime, 0...Self.maxTime),
            integer("Time3", Self.maxTime, 0...Self.maxTime),
        ]
        names = [
            defaults.string(forKey: "Name1") ?? Self.anonymous,
            defaults.string(forKey: "Name2") ?? Self.anonymous,
            defaults.string(forKey: "Name3") ?? Self.anonymous,
        ]
    }

    // SaveConfigToRegistry
    func save() {
        defaults.set(difficulty.rawValue, forKey: "Difficulty")
        defaults.set(height, forKey: "Height")
        defaults.set(width, forKey: "Width")
        defaults.set(mines, forKey: "Mines")
        defaults.set(mark ? 1 : 0, forKey: "Mark")
        defaults.set(color ? 1 : 0, forKey: "Color")
        defaults.set(sound ? 1 : 0, forKey: "Sound")
        defaults.set(zoom, forKey: "Zoom")
        for i in 0..<3 {
            defaults.set(times[i], forKey: "Time\(i + 1)")
            defaults.set(names[i], forKey: "Name\(i + 1)")
        }
    }

    // GetIntegerFromRegistry
    private func integer(_ key: String, _ defaultValue: Int, _ range: ClosedRange<Int>) -> Int {
        guard let value = defaults.object(forKey: key) as? Int else {
            return defaultValue
        }
        return value.clamped(to: range)
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
