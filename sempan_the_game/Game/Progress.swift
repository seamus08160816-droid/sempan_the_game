import Foundation
import Observation

// MARK: - 누적 기록

struct LifetimeStats: Codable {
    var runsStarted = 0
    var runsFinished = 0
    var kills = 0
    var eliteKills = 0
    var bossKills = 0
    var maxAct = 1
    var maxHit: Double = 0
    var maxGold: Double = 0
    var oneShots = 0
    var bigOverkills = 0
    var luckProcs = 0
    var cardsBought = 0
}

// MARK: - 슬롯 하나에 저장되는 모든 진행상황

struct SlotProfile: Codable {
    var run: RunState?
    var bestDepth = 0
    var bestSingle: Double = 0
    var stats = LifetimeStats()
    var achievements: [String: Date] = [:]
    var collection: Set<String> = []
    var createdAt = Date()
    var updatedAt = Date()

    var collectionProgress: Double {
        Double(collection.intersection(CardCatalog.allKeys).count) / Double(CardCatalog.entries.count)
    }
}

// MARK: - 카드 도감

struct CatalogEntry: Identifiable {
    var id: String { key }
    let key: String
    let title: String
    let desc: String
    let sample: Card
}

enum CardCatalog {
    static let maxNumber = 15

    static let entries: [CatalogEntry] = {
        var list: [CatalogEntry] = []
        for n in 1...maxNumber {
            let desc = n <= 9 ? "기본 덱에 들어 있는 숫자예요" : "상점이나 강화로 얻는 큰 숫자예요"
            list.append(CatalogEntry(key: "num-\(n)", title: "숫자 \(n)", desc: desc, sample: .number(-n, n)))
        }
        for op in [Op.add, .sub, .mul, .div] {
            let desc = op == .mul ? "강력한 대신 강화할 수 없어요" : "기본 기호 카드예요"
            list.append(CatalogEntry(key: "op-\(op.rawValue)", title: "\(op.symbol) 카드", desc: desc, sample: .symbol(-100 - op.order, op)))
        }
        for (i, e) in Enh.allCases.enumerated() {
            var sample: Card = e.isOpPerk ? .symbol(-200 - i, e.op ?? .add) : .number(-200 - i, 7)
            sample.enh = [e]
            if e == .stack { sample.bonus = CFG.stackStep }
            let target = e.op.map { " (\($0.symbol) 카드)" } ?? ""
            list.append(CatalogEntry(key: "enh-\(e.rawValue)", title: "\(e.name) 강화\(target)", desc: e.desc, sample: sample))
        }
        for t in Transform.allCases {
            var sample: Card = .number(-300 - t.index, 5)
            sample.tr = t
            list.append(CatalogEntry(key: "tr-\(t.rawValue)", title: "\(t.name) 변신", desc: "\(t.act)막부터 나와요. 숫자 n을 \(t.text("n"))으로 계산해요 (n은 \(t.cap)까지)", sample: sample))
        }
        return list
    }()

    static let allKeys = Set(entries.map(\.key))

    /// 카드 한 장이 도감에서 채워 주는 항목들
    static func keys(for card: Card) -> [String] {
        var keys: [String] = []
        if card.kind == .num, (1...maxNumber).contains(card.v) { keys.append("num-\(card.v)") }
        if let op = card.op { keys.append("op-\(op.rawValue)") }
        keys += card.enh.map { "enh-\($0.rawValue)" }
        if let tr = card.tr { keys.append("tr-\(tr.rawValue)") }
        return keys
    }
}

// MARK: - 업적

struct Achievement: Identifiable {
    let id: String
    let icon: String
    let title: String
    let desc: String
    let isMet: (SlotProfile) -> Bool
}

enum Achievements {
    static let all: [Achievement] = [
        Achievement(id: "firstKill", icon: "👾", title: "첫 계산", desc: "몹을 처음으로 처치하기") { $0.stats.kills >= 1 },
        Achievement(id: "elite", icon: "💀", title: "정예 사냥꾼", desc: "정예 몹 처치하기") { $0.stats.eliteKills >= 1 },
        Achievement(id: "boss", icon: "👑", title: "1막 돌파", desc: "보스 처치하기") { $0.stats.bossKills >= 1 },
        Achievement(id: "act3", icon: "🧭", title: "깊은 곳으로", desc: "3막에 도달하기") { $0.stats.maxAct >= 3 },
        Achievement(id: "act5", icon: "🏔️", title: "팩토리얼의 땅", desc: "5막에 도달하기") { $0.stats.maxAct >= 5 },
        Achievement(id: "hit1k", icon: "💥", title: "천 단위", desc: "한 방에 1,000 이상 피해 주기") { $0.stats.maxHit >= 1_000 },
        Achievement(id: "hit100k", icon: "🔥", title: "십만 대군", desc: "한 방에 10만 이상 피해 주기") { $0.stats.maxHit >= 100_000 },
        Achievement(id: "hit1e8", icon: "🌋", title: "억 소리 나는", desc: "한 방에 1억 이상 피해 주기") { $0.stats.maxHit >= 1e8 },
        Achievement(id: "oneShot", icon: "🎯", title: "일격필살", desc: "첫 계산 한 번으로 몹 처치하기") { $0.stats.oneShots >= 1 },
        Achievement(id: "overkill", icon: "📈", title: "과잉 계산", desc: "적 체력의 200% 이상 초과 피해 주기") { $0.stats.bigOverkills >= 1 },
        Achievement(id: "luck", icon: "🍀", title: "행운의 숫자", desc: "행운 ×5 터뜨리기") { $0.stats.luckProcs >= 1 },
        Achievement(id: "rich", icon: "💰", title: "부자 수학자", desc: "골드 1,000 이상 모으기") { $0.stats.maxGold >= 1_000 },
        Achievement(id: "shopper", icon: "🛒", title: "단골손님", desc: "상점에서 카드 5장 사기 (누적)") { $0.stats.cardsBought >= 5 },
        Achievement(id: "kills100", icon: "⚔️", title: "백전노장", desc: "몹 100마리 처치하기 (누적)") { $0.stats.kills >= 100 },
        Achievement(id: "runs10", icon: "📚", title: "끈기", desc: "게임 10판 끝내기") { $0.stats.runsFinished >= 10 },
        Achievement(id: "collectHalf", icon: "🗂️", title: "수집가", desc: "카드 도감 절반 채우기") { $0.collectionProgress >= 0.5 },
        Achievement(id: "collectAll", icon: "🏆", title: "완벽한 도감", desc: "카드 도감 모두 채우기") { $0.collectionProgress >= 1 }
    ]
}

extension SlotProfile {
    /// 새로 달성한 업적을 기록하고 돌려줘요
    mutating func evaluateAchievements() -> [Achievement] {
        var unlocked: [Achievement] = []
        for a in Achievements.all where achievements[a.id] == nil && a.isMet(self) {
            achievements[a.id] = Date()
            unlocked.append(a)
        }
        return unlocked
    }

    /// 카드가 도감에 처음 들어오면 그 항목들을 돌려줘요
    mutating func collect(_ card: Card) -> [String] {
        CardCatalog.keys(for: card).filter { collection.insert($0).inserted }
    }
}

// MARK: - 3개 저장 슬롯 (로컬 JSON 파일)

@Observable
final class SaveStore {
    static let slotCount = 3

    private(set) var slots: [SlotProfile?] = Array(repeating: nil, count: SaveStore.slotCount)

    private let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appending(path: "Saves", directoryHint: .isDirectory)
    }()

    init() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        load()
    }

    private func url(for index: Int) -> URL {
        directory.appending(path: "slot\(index + 1).json")
    }

    func load() {
        let decoder = JSONDecoder()
        for i in 0..<Self.slotCount {
            guard let data = try? Data(contentsOf: url(for: i)) else { continue }
            slots[i] = try? decoder.decode(SlotProfile.self, from: data)
        }
    }

    /// 슬롯이 비어 있으면 새 프로필을 만들어 돌려줘요
    func profile(_ index: Int) -> SlotProfile {
        slots[index] ?? SlotProfile()
    }

    func update(_ index: Int, _ change: (inout SlotProfile) -> Void) {
        var p = profile(index)
        change(&p)
        p.updatedAt = Date()
        slots[index] = p
        write(index)
    }

    func delete(_ index: Int) {
        slots[index] = nil
        try? FileManager.default.removeItem(at: url(for: index))
    }

    private func write(_ index: Int) {
        guard let p = slots[index] else { return }
        do {
            let data = try JSONEncoder().encode(p)
            try data.write(to: url(for: index), options: .atomic)
        } catch {
            print("저장 실패 (슬롯 \(index + 1)): \(error)")
        }
    }
}
