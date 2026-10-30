import Foundation

// MARK: - 밸런스 조정용 값 (원본 CFG 그대로)

enum CFG {
    static let baseHP: Double = 60                    // 1막 1층 체력
    static let actGrowth: [Double] = [1.30, 1.40, 1.50, 1.55] // 막별 층당 체력 배율
    static let growthAfter: Double = 1.6              // 표 이후 막의 층당 배율
    static let eliteMult: Double = 1.5
    static let bossMult: Double = 1.8
    static let actLen = 10
    static let shopRate = 0.22
    static let eliteRate = 0.15
    static let hand = 8
    static let plays = 4
    static let discards = 3
    static let corePerkRate = 0.35                    // 손패·계산 +1 특전이 뽑혔을 때 실제로 나올 확률
    static let maxLen = 5
    static let fireBase: Double = 10
    static let firePow: Double = 0.8
    static let luckChance = 0.25
    static let stackStep: Double = 4
    static let econPow: Double = 1
    static let killGold: Double = 5
    static let discGold: Double = 3
    static let playGold: Double = 6
    static let goldA: Double = 8
    static let goldK: Double = 0.25
    static let goldCap: Double = 20
    static let eliteGoldMult: Double = 1
    static let bossGoldMult: Double = 1
}

// MARK: - 카드 구성 요소

enum CardKind: String, Codable {
    case num, op
}

enum Op: String, Codable, CaseIterable {
    case add = "+", sub = "-", div = "/", mul = "*"

    var symbol: String {
        switch self {
        case .add: "+"
        case .sub: "−"
        case .mul: "×"
        case .div: "÷"
        }
    }

    /// 손패 정렬 순서 (원본 ORD = '+-/*')
    var order: Int { Op.allCases.firstIndex(of: self) ?? 0 }
}

/// 카드 강화
enum Enh: String, Codable, CaseIterable {
    case gold, fire, luck, amp, stack, flip, exact

    var badge: String {
        switch self {
        case .gold: "×2"
        case .fire: "+"
        case .luck: "?×5"
        case .amp: "증폭"
        case .stack: "적립"
        case .flip: "역전"
        case .exact: "정확"
        }
    }

    var name: String {
        switch self {
        case .gold: "황금"
        case .fire: "불꽃"
        case .luck: "행운"
        case .amp: "증폭"
        case .stack: "적립"
        case .flip: "역전"
        case .exact: "정확"
        }
    }

    var desc: String {
        switch self {
        case .gold: "수식에 쓰면 최종 결과 ×2"
        case .fire: "수식에 쓰면 최종 결과에 더해요. 적 체력과 함께 커져요"
        case .luck: "수식에 쓰면 25% 확률로 최종 결과 ×5"
        case .amp: "오른쪽 수를 세 배로 더해요"
        case .stack: "보너스를 함께 더하고, 쓸 때마다 보너스가 \(Int(CFG.stackStep))×물가만큼 영구히 커져요"
        case .flip: "빼서 음수가 되면 빼는 대신 두 수를 더하고 ×4"
        case .exact: "나누어떨어지면 나누는 대신 두 수를 곱하고 ×2"
        }
    }

    /// 상점 가치
    var value: Double {
        switch self {
        case .gold: 18
        case .fire: 8
        case .luck: 12
        case .amp, .stack, .flip: 15
        case .exact: 16
        }
    }

    /// 기호 전용 강화가 붙는 기호
    var op: Op? {
        switch self {
        case .amp, .stack: .add
        case .flip: .sub
        case .exact: .div
        default: nil
        }
    }

    var isOpPerk: Bool { op != nil }

    static let opPerks: [Enh] = [.amp, .stack, .flip, .exact]

    /// 정확 강화가 발동하는 나눗셈 (0은 나눠도 0이라 빼요)
    static func divides(_ a: Double, _ b: Double) -> Bool {
        a != 0 && b != 0 && abs(a.truncatingRemainder(dividingBy: b)) < 1e-9
    }
}

/// 숫자 변신 강화. 막마다 하나씩 해금. cap은 변신에 넣는 값의 상한
enum Transform: String, Codable, CaseIterable {
    case sq, pow2, exp, fact

    var name: String {
        switch self {
        case .sq: "제곱"
        case .pow2: "2의 거듭제곱"
        case .exp: "자연지수"
        case .fact: "팩토리얼"
        }
    }

    var act: Int {
        switch self {
        case .sq: 2
        case .pow2: 3
        case .exp: 4
        case .fact: 5
        }
    }

    var cap: Int {
        switch self {
        case .sq: 20
        case .pow2: 15
        case .exp: 12
        case .fact: 10
        }
    }

    var value: Double {
        switch self {
        case .sq: 14
        case .pow2: 22
        case .exp: 32
        case .fact: 44
        }
    }

    func apply(_ n: Int) -> Double {
        switch self {
        case .sq: return Double(n * n)
        case .pow2: return pow(2, Double(n))
        case .exp: return Foundation.exp(Double(n)).rounded()
        case .fact: return (1...max(1, n)).reduce(1.0) { $0 * Double($1) }
        }
    }

    func text(_ v: String) -> String {
        switch self {
        case .sq: "\(v)²"
        case .pow2: "2^\(v)"
        case .exp: "e^\(v)"
        case .fact: "\(v)!"
        }
    }

    var index: Int { Transform.allCases.firstIndex(of: self) ?? 0 }
}

// MARK: - 카드

struct Card: Codable, Identifiable, Equatable {
    var id: Int
    var kind: CardKind
    var v: Int = 0
    var op: Op?
    var enh: [Enh] = []
    var up: Int = 0
    var tr: Transform?
    var bonus: Double = 0

    static func number(_ id: Int, _ v: Int) -> Card { Card(id: id, kind: .num, v: v) }
    static func symbol(_ id: Int, _ op: Op) -> Card { Card(id: id, kind: .op, op: op) }

    /// 변신에 실제로 들어가는 n (상한에서 멈춰요)
    var trInput: Int { tr.map { min(v, $0.cap) } ?? v }

    /// 실제 계산 값 (변신 적용)
    var numVal: Double {
        if let tr { return tr.apply(trInput) }
        return Double(v)
    }

    var trIndex: Int { tr?.index ?? -1 }

    var faceText: String {
        if kind == .op { return op?.symbol ?? "" }
        if let tr { return tr.text(String(trInput)) }
        return String(v)
    }

    var label: String { kind == .num ? "숫자 \(faceText)" : "\(op?.symbol ?? "") 카드" }

    var baseValue: Double {
        var value: Double
        if kind == .num {
            value = 6 + Double(v)
        } else {
            switch op {
            case .mul: value = 30
            case .div: value = 12
            default: value = 10
            }
        }
        for e in enh { value += e.value }
        if let tr { value += tr.value }
        return value
    }
}

// MARK: - 지도

enum NodeType: String, Codable {
    case mob, elite, shop, boss

    var icon: String {
        switch self {
        case .mob: "👾"
        case .elite: "💀"
        case .shop: "🛒"
        case .boss: "👑"
        }
    }

    var name: String {
        switch self {
        case .mob: "몹"
        case .elite: "정예"
        case .shop: "상점"
        case .boss: "보스"
        }
    }
}

struct MapNode: Codable, Identifiable, Equatable {
    var id: String
    var floor: Int
    var x: Double
    var type: NodeType
    var next: [String]
    var name: String
}

enum MobNames {
    static let mob = ["계산 슬라임", "나머지 고블린", "분모 박쥐", "소수점 쥐", "괄호 거미", "오답 유령", "반올림 두더지", "약수 버섯"]
    static let elite = ["구구단 기사", "약분 마법사", "통분 쌍둥이", "검산 감시자"]
    static let boss = ["방정식 골렘", "무한소 군주", "미지수 용", "증명 거인"]

    static func random(for type: NodeType) -> String {
        switch type {
        case .mob: mob.randomElement() ?? "몹"
        case .elite: elite.randomElement() ?? "정예"
        case .boss: boss.randomElement() ?? "보스"
        case .shop: "상점"
        }
    }
}

// MARK: - 전투 상태

struct HandCard: Codable, Equatable {
    var cardID: Int
    var out: Bool
}

enum LogStyle: String, Codable {
    case info, expr, step, fx, fxGold, miss, final
}

struct LogLine: Codable, Identifiable, Equatable {
    var id = UUID()
    var text: String
    var note: String = ""
    var style: LogStyle
}

struct FightState: Codable {
    var nodeID: String
    var hpMax: Double
    var score: Double = 0
    var playsLeft: Int
    var discLeft: Int
    var numDraw: [Int] = []
    var opDraw: [Int] = []
    var numPile: [Int] = []
    var opPile: [Int] = []
    var handCards: [HandCard] = []
    var sel: [Int] = []
    var log: [LogLine] = []
    /// 계산 결과는 저장됐지만 승패 처리가 아직이에요 (옛 저장과 호환되게 옵셔널)
    var resolving: Bool?
}

struct GoldBreakdown: Codable {
    var g1: Double, g2: Double, g3: Double, g4: Double, gain: Double
    var over: Double, hp: Double
    var disc: Int, plays: Int
    var ratePlay: Double, rateDisc: Double
    var type: NodeType
}

// MARK: - 특전

enum PerkKind: Codable, Equatable {
    case upNum
    case enchant(Enh)
    case opPerk(Enh)
    case transform(Transform)
    case handSize, plays, discards
}

struct Perk: Codable, Identifiable, Equatable {
    var id = UUID()
    var kind: PerkKind
    var cardID: Int?
    var glyph: String = ""
    var title: String
    var desc: String
}

struct RewardState: Codable {
    var count: Int
    var idx: Int
    var offers: [Perk]
}

struct ShopState: Codable {
    var items: [Card]
    var pendingID: Int?
    var msg: String
}

struct GameOverInfo: Codable {
    var reason: String
    var newRecord: Bool
}

enum Phase: String, Codable {
    case map, fight, shop
}

// MARK: - 한 판 전체 상태 (저장 대상)

struct RunState: Codable {
    var act = 1
    var map: [[MapNode]] = []
    var floor = 0
    var curID: String?
    var visited: Set<String> = []
    var depth = 1
    var deck: [Card] = []
    var gold: Double = 0
    var goldTotal: Double = 0
    var kills = 0
    var hand = CFG.hand
    var plays = CFG.plays
    var discards = CFG.discards
    var bestPlay: Double = 0
    var nextID = 0
    var phase: Phase = .map
    var mapMsg = ""
    var fight: FightState?
    var shop: ShopState?
    var reward: RewardState?
    var lastGold: GoldBreakdown?
    var over: GameOverInfo?
    var startedAt = Date()

    var econ: Double { econ(at: floor) }

    func econ(at f: Int) -> Double {
        pow(Self.baseHPAt(depthOf(max(1, f))) / CFG.baseHP, CFG.econPow)
    }

    func depthOf(_ f: Int) -> Int { (act - 1) * CFG.actLen + f }

    static func growthOf(_ act: Int) -> Double {
        act - 1 < CFG.actGrowth.count ? CFG.actGrowth[act - 1] : CFG.growthAfter
    }

    static func baseHPAt(_ depth: Int) -> Double {
        var h = CFG.baseHP
        if depth >= 2 {
            for d in 2...depth {
                h *= growthOf(Int((Double(d) / Double(CFG.actLen)).rounded(.up)))
            }
        }
        return h
    }

    func hpFor(_ f: Int, _ type: NodeType) -> Double {
        var h = Self.baseHPAt(depthOf(max(1, f)))
        if type == .elite { h *= CFG.eliteMult }
        if type == .boss { h *= CFG.bossMult }
        return (h / 10).rounded() * 10
    }

    var fireBonus: Double { (CFG.fireBase * pow(econ, CFG.firePow)).rounded() }

    var leftoverRate: (play: Double, disc: Double) {
        ((CFG.playGold * econ).rounded(), (CFG.discGold * econ).rounded())
    }

    static func hpUnit(_ hp: Double, _ type: NodeType) -> Double {
        let mult: Double = type == .elite ? CFG.eliteGoldMult : type == .boss ? CFG.bossGoldMult : 1
        return pow(hp / CFG.baseHP, CFG.econPow) * mult
    }

    static func overkillCap(_ hp: Double, _ type: NodeType) -> Double { CFG.goldCap * hpUnit(hp, type) }

    /// 초과 피해 → 골드: 로그로 빠르게 꺾이고 상한에서 멈춰요
    static func overkillGold(_ over: Double, _ hp: Double, _ type: NodeType) -> Double {
        (min(CFG.goldCap, CFG.goldA * log(1 + (over / hp) / CFG.goldK)) * hpUnit(hp, type)).rounded()
    }

    func card(_ id: Int) -> Card? { deck.first { $0.id == id } }

    func node(_ id: String?) -> MapNode? {
        guard let id else { return nil }
        return map.joined().first { $0.id == id }
    }

    var cur: MapNode? { node(curID) }

    func reachable(_ n: MapNode) -> Bool {
        if let cur { return cur.next.contains(n.id) }
        return n.floor == 1
    }

    var unlockedTR: [Transform] { Transform.allCases.filter { act >= $0.act } }

    var whereText: String { floor == 0 ? "\(act)막 출발" : "\(act)막 \(floor)층" }
}

// MARK: - 숫자 표시

enum Fmt {
    private static let units: [(Double, String)] = [(1e16, "경"), (1e12, "조"), (1e8, "억"), (1e4, "만")]

    private static let formatter: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.numberStyle = .decimal
        f.maximumFractionDigits = 2
        return f
    }()

    private static func grouped(_ n: Double) -> String {
        formatter.string(from: NSNumber(value: n)) ?? String(n)
    }

    /// 원본 fmt(): 만·억·조·경 단위로 짧게 보여줘요
    static func n(_ n: Double) -> String {
        guard n.isFinite else { return "∞" }
        let a = abs(n)
        if a < 1e5 { return grouped((n * 100).rounded() / 100) }
        if a >= 1e20 {
            let exponent = Int(floor(log10(a)))
            let mantissa = n / pow(10, Double(exponent))
            return String(format: "%.2f×10^%d", mantissa, exponent)
        }
        for (u, name) in units where a >= u {
            let x = n / u
            // 유효숫자 3자리로 반올림
            let digits = floor(log10(abs(x))) + 1
            let factor = pow(10, 3 - digits)
            return grouped((x * factor).rounded() / factor) + name
        }
        return grouped(n)
    }
}
