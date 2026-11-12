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
    /// 가장 깊이 들어간 층 (퍽 해금 기준). 예전 저장과 호환되게 옵셔널
    var maxDepth: Int?
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
    /// 해금한 퍽과 장착한 퍽 (최대 3개). 예전 저장과 호환되게 옵셔널
    var perksUnlocked: [String]?
    var equipped: [String]?

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

    /// 지금 언어로 만든 도감 항목 (언어를 바꾸면 다시 만들어요)
    static var entries: [CatalogEntry] {
        var list: [CatalogEntry] = []
        for n in 1...maxNumber {
            let desc = n <= 9 ? L("기본 덱에 들어 있는 숫자예요", "A number from the starting deck") : L("상점이나 강화로 얻는 큰 숫자예요", "A big number from shops or upgrades")
            list.append(CatalogEntry(key: "num-\(n)", title: L("숫자 \(n)", "Number \(n)"), desc: desc, sample: .number(-n, n)))
        }
        for op in [Op.add, .sub, .mul, .div, .pow] {
            let desc = op == .mul ? L("강력한 대신 강화할 수 없어요", "Powerful, but can't be enhanced")
                : op == .pow ? L("× 카드가 진화한 거듭제곱 카드예요. 지수는 \(Int(CFG.powCap))까지 (6막부터)", "A power card evolved from a × card. Exponent capped at \(Int(CFG.powCap)) (from Act 6)")
                : L("기본 기호 카드예요", "A basic operator card")
            list.append(CatalogEntry(key: "op-\(op.rawValue)", title: L("\(op.symbol) 카드", "\(op.symbol) card"), desc: desc, sample: .symbol(-100 - op.order, op)))
        }
        for (i, e) in Enh.allCases.enumerated() {
            var sample: Card = e.isOpPerk ? .symbol(-200 - i, e.op ?? .add) : .number(-200 - i, 7)
            sample.enh = [e]
            if e == .stack { sample.bonus = CFG.stackStep }
            let target = e.op.map { L(" (\($0.symbol) 카드)", " (\($0.symbol) card)") } ?? ""
            list.append(CatalogEntry(key: "enh-\(e.rawValue)", title: L("\(e.name) 강화\(target)", "\(e.name) enhancement\(target)"), desc: e.desc, sample: sample))
        }
        for t in Transform.allCases {
            var sample: Card = .number(-300 - t.index, 5)
            sample.tr = t
            let desc = L("\(t.act)막부터 나와요. 숫자 n을 \(t.text("n"))으로 계산해요 (n은 \(t.cap)까지)",
                         "Appears from Act \(t.act). Counts number n as \(t.text("n")) (n up to \(t.cap))")
            list.append(CatalogEntry(key: "tr-\(t.rawValue)", title: L("\(t.name) 변신", "\(t.name) transformation"), desc: desc, sample: sample))
        }
        return list
    }

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

// MARK: - 퍽 (판 밖에서 해금해 3개까지 장착)

/// 밸런스 기준: 막마다 상점을 한 번 공짜로 재입고하는 정도의 이득
enum MetaPerk: String, CaseIterable, Identifiable {
    case restock, allowance, coupon, reroll, sharpen, study, interest, clover, hunter, grit

    static let slots = 3

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .restock: "🔄"
        case .allowance: "👛"
        case .coupon: "🎟️"
        case .reroll: "🎲"
        case .sharpen: "✏️"
        case .study: "📖"
        case .interest: "🏦"
        case .clover: "🍀"
        case .hunter: "🏹"
        case .grit: "💪"
        }
    }

    var name: String {
        switch self {
        case .restock: L("재입고", "Restock")
        case .allowance: L("비상금", "Allowance")
        case .coupon: L("할인권", "Coupon")
        case .reroll: L("다시 뽑기", "Reroll")
        case .sharpen: L("연필 깎기", "Sharpen")
        case .study: L("예습", "Study")
        case .interest: L("이자", "Interest")
        case .clover: L("네잎클로버", "Four-leaf Clover")
        case .hunter: L("정예 사냥꾼", "Elite Hunter")
        case .grit: L("뒷심", "Second Wind")
        }
    }

    /// 이 층(전체 깊이)에 처음 도달하면 해금돼요
    var depth: Int {
        switch self {
        case .restock: 3
        case .allowance: 6
        case .coupon: 10
        case .reroll: 13
        case .sharpen: 16
        case .study: 20
        case .interest: 25
        case .clover: 30
        case .hunter: 40
        case .grit: 50
        }
    }

    var desc: String {
        switch self {
        case .restock: L("상점에서 막마다 한 번 무료로 물건을 새로 들여요", "Once per act, refresh the shop for free")
        case .allowance: L("막을 시작할 때 골드를 받아요 (물가 ×12)", "Gain gold at the start of each act (price level ×12)")
        case .coupon: L("막마다 상점 첫 구매가 30% 싸요", "Your first shop purchase each act is 30% off")
        case .reroll: L("막마다 한 번 특전 선택지를 새로 뽑아요", "Once per act, reroll your upgrade choices")
        case .sharpen: L("막마다 한 번 전투 중 손패를 모두 새로 뽑아요 (버리기를 쓰지 않아요)", "Once per act, redraw your whole hand in a fight (doesn't use a discard)")
        case .study: L("전투 첫 손패에 숫자 카드가 4장 이상 들어와요", "Your first hand in each fight has at least 4 number cards")
        case .interest: L("상점을 나갈 때 남은 골드의 10%를 받아요 (최대 물가 ×10)", "Gain 10% of your remaining gold when leaving a shop (up to price level ×10)")
        case .clover: L("행운 강화가 터질 확률이 25%에서 35%로 올라요", "Luck triggers 35% of the time instead of 25%")
        case .hunter: L("정예를 잡으면 특전 선택지가 4개씩 나와요", "Defeating an elite offers 4 upgrades instead of 3")
        case .grit: L("막마다 한 번, 계산 기회를 다 썼을 때 체력이 20% 이하로 남았으면 한 번 더 계산해요", "Once per act, if you run out of calcs with the enemy at 20% HP or less, calculate once more")
        }
    }

    /// 막마다 한 번만 쓰는 퍽
    var oncePerAct: Bool { [.restock, .coupon, .reroll, .sharpen, .grit].contains(self) }

    static func depthText(_ d: Int) -> String {
        let act = (d + CFG.actLen - 1) / CFG.actLen, floor = (d - 1) % CFG.actLen + 1
        return L("\(act)막 \(floor)층", "Act \(act), Floor \(floor)")
    }
}

// MARK: - 업적

struct Achievement: Identifiable {
    let id: String
    let icon: String
    /// (한국어, 영어)
    let titles: (String, String)
    let descs: (String, String)
    let isMet: (SlotProfile) -> Bool

    var title: String { L(titles.0, titles.1) }
    var desc: String { L(descs.0, descs.1) }
}

enum Achievements {
    static let all: [Achievement] = [
        Achievement(id: "firstKill", icon: "👾", titles: ("첫 계산", "First Calculation"), descs: ("몹을 처음으로 처치하기", "Defeat your first monster")) { $0.stats.kills >= 1 },
        Achievement(id: "elite", icon: "💀", titles: ("정예 사냥꾼", "Elite Hunter"), descs: ("정예 몹 처치하기", "Defeat an elite")) { $0.stats.eliteKills >= 1 },
        Achievement(id: "boss", icon: "👑", titles: ("1막 돌파", "Act 1 Cleared"), descs: ("보스 처치하기", "Defeat a boss")) { $0.stats.bossKills >= 1 },
        Achievement(id: "act3", icon: "🧭", titles: ("깊은 곳으로", "Going Deeper"), descs: ("3막에 도달하기", "Reach Act 3")) { $0.stats.maxAct >= 3 },
        Achievement(id: "act5", icon: "🏔️", titles: ("팩토리얼의 땅", "Land of Factorials"), descs: ("5막에 도달하기", "Reach Act 5")) { $0.stats.maxAct >= 5 },
        Achievement(id: "ascend", icon: "🌌", titles: ("차원 상승", "Dimension Ascent"), descs: ("로그 단계(\(CFG.logAct)막)에 도달하기", "Reach the log stage (Act \(CFG.logAct))")) { $0.stats.maxAct >= CFG.logAct },
        Achievement(id: "hit1k", icon: "💥", titles: ("천 단위", "Four Digits"), descs: ("한 방에 1,000 이상 피해 주기", "Deal 1,000+ damage in one hit")) { $0.stats.maxHit >= 1_000 },
        Achievement(id: "hit100k", icon: "🔥", titles: ("십만 대군", "Six Figures"), descs: ("한 방에 10만 이상 피해 주기", "Deal 100,000+ damage in one hit")) { $0.stats.maxHit >= 100_000 },
        Achievement(id: "hit1e8", icon: "🌋", titles: ("억 소리 나는", "Hundred Million"), descs: ("한 방에 1억 이상 피해 주기", "Deal 100,000,000+ damage in one hit")) { $0.stats.maxHit >= 1e8 },
        Achievement(id: "oneShot", icon: "🎯", titles: ("일격필살", "One-Shot"), descs: ("첫 계산 한 번으로 몹 처치하기", "Defeat a monster with your first calculation")) { $0.stats.oneShots >= 1 },
        Achievement(id: "overkill", icon: "📈", titles: ("과잉 계산", "Overkill"), descs: ("적 체력의 200% 이상 초과 피해 주기", "Deal 200%+ overkill damage")) { $0.stats.bigOverkills >= 1 },
        Achievement(id: "luck", icon: "🍀", titles: ("행운의 숫자", "Lucky Number"), descs: ("행운 ×5 터뜨리기", "Trigger Luck ×5")) { $0.stats.luckProcs >= 1 },
        Achievement(id: "rich", icon: "💰", titles: ("부자 수학자", "Rich Mathematician"), descs: ("골드 1,000 이상 모으기", "Hold 1,000+ gold")) { $0.stats.maxGold >= 1_000 },
        Achievement(id: "shopper", icon: "🛒", titles: ("단골손님", "Regular"), descs: ("상점에서 카드 5장 사기 (누적)", "Buy 5 cards in shops (total)")) { $0.stats.cardsBought >= 5 },
        Achievement(id: "kills100", icon: "⚔️", titles: ("백전노장", "Veteran"), descs: ("몹 100마리 처치하기 (누적)", "Defeat 100 monsters (total)")) { $0.stats.kills >= 100 },
        Achievement(id: "runs10", icon: "📚", titles: ("끈기", "Persistence"), descs: ("게임 10판 끝내기", "Finish 10 runs")) { $0.stats.runsFinished >= 10 },
        Achievement(id: "collectHalf", icon: "🗂️", titles: ("수집가", "Collector"), descs: ("카드 도감 절반 채우기", "Fill half of the collection")) { $0.collectionProgress >= 0.5 },
        Achievement(id: "collectAll", icon: "🏆", titles: ("완벽한 도감", "Complete Collection"), descs: ("카드 도감 모두 채우기", "Fill the whole collection")) { $0.collectionProgress >= 1 }
    ]
}

extension SlotProfile {
    /// 새로 해금한 퍽을 기록하고 돌려줘요
    mutating func evaluatePerks() -> [MetaPerk] {
        let depth = stats.maxDepth ?? max(bestDepth, run?.depth ?? 0)
        if stats.maxDepth == nil { stats.maxDepth = depth }
        var have = perksUnlocked ?? []
        let fresh = MetaPerk.allCases.filter { depth >= $0.depth && !have.contains($0.rawValue) }
        have += fresh.map(\.rawValue)
        perksUnlocked = have
        return fresh
    }

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
            // 예전 기록으로 이미 도달한 깊이의 퍽은 불러올 때 바로 해금해요
            _ = slots[i]?.evaluatePerks()
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
