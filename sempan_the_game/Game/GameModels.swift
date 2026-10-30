import Foundation

// MARK: - 밸런스 조정용 값 (원본 CFG 그대로)

enum CFG {
    static let baseHP: Double = 60                    // 1막 1층 체력
    static let actGrowth: [Double] = [1.30, 1.40, 1.50, 1.55] // 막별 층당 체력 배율
    static let growthAfter: Double = 1.6              // 표 이후 막의 층당 배율
    static let eliteMult: Double = 1.5
    static let bossMult: Double = 1.8
    /// 중반부(4~6막) 몹 체력 추가 배율. 보상은 그대로라 실제로 어려워져요
    static let midHP: [Int: Double] = [4: 1.2, 5: 1.25, 6: 1.3]
    static let actLen = 10
    static let shopRate = 0.22
    static let eliteRate = 0.15
    static let hand = 8
    static let plays = 4
    static let discards = 3
    static let handPerkRate = 0.12                    // 손패 +1 특전이 뽑혔을 때 실제로 나올 확률
    static let handMax = 10                           // 손패 상한
    static let discardPerkRate = 0.25                 // 버리기 +1 특전 확률
    static let discardMax = 5                         // 버리기 상한
    static let trPerkRate = 0.3                       // 변신 특전이 뽑혔을 때 실제로 나올 확률 (시뮬레이션으로 맞췄어요)
    static let shopTrRate = 0.35                      // 상점 숫자 카드가 변신 상태로 나올 확률
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
    static let powCap: Double = 2                     // ^ 카드 지수 상한 (같은 카드 두 장을 곱한 만큼까지)
    static let logAct = 9                             // 이 막부터 로그 단계 (차원 상승)
}

// MARK: - 카드 구성 요소

enum CardKind: String, Codable {
    case num, op
}

enum Op: String, Codable, CaseIterable {
    case add = "+", sub = "-", div = "/", mul = "*", pow = "^"

    var symbol: String {
        switch self {
        case .add: "+"
        case .sub: "−"
        case .mul: "×"
        case .div: "÷"
        case .pow: "^"
        }
    }

    /// 손패 정렬 순서 ('+-/*^')
    var order: Int { Op.allCases.firstIndex(of: self) ?? 0 }

    /// 강력한 대신 강화할 수 없는 기호
    var isPlain: Bool { self == .mul || self == .pow }
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
    case selfPow = "self", sfact, hfact
    /// 테트레이션 3↑↑n: 보스 보상으로만 나와요
    case tet

    var name: String {
        switch self {
        case .sq: "제곱"
        case .pow2: "2의 거듭제곱"
        case .exp: "자연지수"
        case .fact: "팩토리얼"
        case .selfPow: "자기거듭제곱"
        case .sfact: "슈퍼팩토리얼"
        case .hfact: "하이퍼팩토리얼"
        case .tet: "테트레이션"
        }
    }

    var act: Int {
        switch self {
        case .sq: 2
        case .pow2: 3
        case .exp: 4
        case .fact: 5
        case .selfPow: 6
        case .sfact: 7
        case .hfact: 8
        case .tet: 8
        }
    }

    var cap: Int {
        switch self {
        case .sq: 20
        case .pow2: 15
        case .exp: 12
        case .fact: 10
        case .selfPow: 9
        case .sfact: 7
        case .hfact: 6
        case .tet: 3
        }
    }

    var value: Double {
        switch self {
        case .sq: 14
        case .pow2: 22
        case .exp: 32
        case .fact: 44
        case .selfPow: 56
        case .sfact: 70
        case .hfact: 85
        case .tet: 60
        }
    }

    var isSpecial: Bool { self == .tet }

    /// 막마다 하나씩 해금되는 변신 사다리 (특별 카드 제외)
    static let ladder = allCases.filter { !$0.isSpecial }

    private static func fact(_ n: Int) -> Double { (1...max(1, n)).reduce(1.0) { $0 * Double($1) } }

    func apply(_ n: Int) -> Double {
        switch self {
        case .sq: return Double(n * n)
        case .pow2: return Foundation.pow(2, Double(n))
        case .exp: return Foundation.exp(Double(n)).rounded()
        case .fact: return Self.fact(n)
        case .selfPow: return Foundation.pow(Double(n), Double(n))
        case .sfact: return (1...max(1, n)).reduce(1.0) { $0 * Self.fact($1) }
        case .hfact: return (1...max(1, n)).reduce(1.0) { $0 * Foundation.pow(Double($1), Double($1)) }
        case .tet: return (0..<n).reduce(1.0) { r, _ in Foundation.pow(3, r) }
        }
    }

    func text(_ v: String) -> String {
        switch self {
        case .sq: "\(v)²"
        case .pow2: "2^\(v)"
        case .exp: "e^\(v)"
        case .fact: "\(v)!"
        case .selfPow: "\(v)^\(v)"
        case .sfact: "sf(\(v))"
        case .hfact: "H(\(v))"
        case .tet: "3↑↑\(v)"
        }
    }

    var index: Int { Transform.allCases.firstIndex(of: self) ?? 0 }
}

// MARK: - 큰 수

/// 1e300을 넘으면 log₁₀로 들고 다녀서 무한대가 되지 않아요. 작은 수는 그대로 계산해 1~8막은 정확해요
struct BigNum {
    var s: Double       // 부호 -1, 0, 1
    var v: Double?      // 작은 수일 때 값
    var l: Double = 0   // 큰 수일 때 log₁₀|x|

    static let big = 1e300

    static func of(_ x: Double) -> BigNum { BigNum(s: x > 0 ? 1 : x < 0 ? -1 : 0, v: x) }

    static func fromLog(_ s: Double, _ l: Double) -> BigNum {
        if s == 0 { return .of(0) }
        return l < 300 ? .of(s * Foundation.pow(10, l)) : BigNum(s: s, v: nil, l: l)
    }

    var isSmall: Bool { v != nil }
    /// |x|의 자릿수 (log₁₀|x|)
    var log: Double { v.map { log10(abs($0)) } ?? l }
    var num: Double { v ?? s * .infinity }
    var negated: BigNum { v.map { .of(-$0) } ?? BigNum(s: -s, v: nil, l: l) }

    static func + (a: BigNum, b: BigNum) -> BigNum {
        if a.s == 0 { return b }
        if b.s == 0 { return a }
        if let x = a.v, let y = b.v, abs(x + y) < big { return .of(x + y) }
        let (hi, lo, sh) = a.log >= b.log ? (a.log, b.log, a.s) : (b.log, a.log, b.s)
        if a.s == b.s { return .fromLog(sh, hi + log10(1 + Foundation.pow(10, lo - hi))) }
        if hi - lo < 1e-12 { return .of(0) }
        return .fromLog(sh, hi + log10(1 - Foundation.pow(10, lo - hi)))
    }

    static func - (a: BigNum, b: BigNum) -> BigNum { a + b.negated }

    static func * (a: BigNum, b: BigNum) -> BigNum {
        if a.s == 0 || b.s == 0 { return .of(0) }
        if let x = a.v, let y = b.v, abs(x * y) < big { return .of(x * y) }
        return .fromLog(a.s * b.s, a.log + b.log)
    }

    static func / (a: BigNum, b: BigNum) -> BigNum {
        if a.s == 0 || b.s == 0 { return .of(0) }
        if let x = a.v, let y = b.v, abs(x / y) < big { return .of(x / y) }
        return .fromLog(a.s * b.s, a.log - b.log)
    }

    /// a^b. 지수는 ±powCap에서 멈춰요. 음수 밑은 지수가 홀수 정수일 때만 음수가 돼요
    func power(_ b: BigNum) -> BigNum {
        let e = max(-CFG.powCap, min(CFG.powCap, b.num))
        if s == 0 { return .of(0) }
        let sign: Double = s < 0 && e == e.rounded() && Int(abs(e)) % 2 == 1 ? -1 : 1
        if let x = v {
            let r = Foundation.pow(abs(x), e)
            if r.isFinite && r < BigNum.big { return .of(sign * r) }
        }
        return .fromLog(sign, e * log)
    }

    /// 두 수가 정확히 나누어떨어지는지 (아주 큰 수는 확인할 수 없어 아니라고 봐요)
    static func divides(_ a: BigNum, _ b: BigNum) -> Bool {
        guard let x = a.v, let y = b.v, abs(x) < 1e15, abs(y) < 1e15 else { return false }
        return Enh.divides(x, y)
    }

    var text: String {
        if let v { return Fmt.n(v) }
        let e = floor(l)
        let mant = s * Foundation.pow(10, l - e)
        return String(format: "%.2f×10^", mant) + (e < 1e15 ? Fmt.n(e) : Fmt.n(e))
    }
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
            case .pow: value = 45
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
    /// 이번 전투 최고 일격 (특전 고르기 창에서 보여줘요)
    var best: BestHit?
}

/// 한 번의 계산: 쓴 카드(그때 모습 그대로)와 최종 피해
struct BestHit: Codable {
    var cards: [Card]
    var final: Double
}

struct GoldBreakdown: Codable {
    var g1: Double, g2: Double, g3: Double, g4: Double, gain: Double
    var over: Double, hp: Double
    var disc: Int, plays: Int
    var ratePlay: Double, rateDisc: Double
    var type: NodeType
    /// 골드를 계산할 때 쓴 초과 피해 상한 (물가 포함). 예전 저장과 호환되게 옵셔널
    var cap: Double?
}

// MARK: - 특전

enum PerkKind: Codable, Equatable {
    case upNum
    case enchant(Enh)
    case opPerk(Enh)
    case transform(Transform)
    case handSize, plays, discards
    /// × 카드를 ^ 카드로 진화 (6막부터)
    case evolve

    /// 같은 종류의 특전을 한 선택지에 두 번 내지 않으려고 비교하는 열쇠
    var sameKindKey: String {
        switch self {
        case .upNum: "up"
        case .enchant(let e): "en:\(e.rawValue)"
        case .opPerk(let e): "op:\(e.rawValue)"
        case .transform(let t): "tr:\(t.rawValue)"
        case .handSize: "hand"
        case .plays: "plays"
        case .discards: "disc"
        case .evolve: "evolve"
        }
    }
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

/// 화면을 덮는 등장 장면 (보스, 차원 상승)
struct Intro: Equatable {
    let id = UUID()
    let icon: String
    let title: String
    let sub: String
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
    /// 이번 판에 장착한 퍽 (시작할 때 정해져요). 예전 저장과 호환되게 옵셔널
    var perks: [String]?
    /// 막마다 한 번 쓰는 퍽: 마지막으로 쓴 막
    var perkUsed: [String: Int]?

    var econ: Double { econ(at: floor) }

    func econ(at f: Int) -> Double {
        pow(Self.baseHPAt(ladderDepth(max(1, f))) / CFG.baseHP, CFG.econPow)
    }

    func depthOf(_ f: Int) -> Int { (act - 1) * CFG.actLen + f }

    /// 로그 단계(차원 상승 뒤)에서는 체력·물가 사다리를 1막부터 다시 올라요
    var isLog: Bool { act >= CFG.logAct }

    func ladderDepth(_ f: Int) -> Int { isLog ? (act - CFG.logAct) * CFG.actLen + f : depthOf(f) }

    var actName: String { isLog ? "로그 \(act - CFG.logAct + 1)막" : "\(act)막" }

    /// 로그 단계의 체력은 10의 거듭제곱, 피해는 자릿수예요
    func hpText(_ x: Double) -> String { isLog ? "10^\(Fmt.n(x))" : Fmt.n(x) }
    func dmgText(_ x: Double) -> String { isLog ? "\(Fmt.n(x))자리" : Fmt.n(x) }

    func hasPerk(_ k: MetaPerk) -> Bool { (perks ?? []).contains(k.rawValue) }
    func perkReady(_ k: MetaPerk) -> Bool { hasPerk(k) && perkUsed?[k.rawValue] != act }

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
        var h = Self.baseHPAt(ladderDepth(max(1, f)))
        if type == .elite { h *= CFG.eliteMult }
        if type == .boss { h *= CFG.bossMult }
        if !isLog { h *= CFG.midHP[act] ?? 1 }
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

    var unlockedTR: [Transform] { Transform.ladder.filter { act >= $0.act } }

    var whereText: String { floor == 0 ? "\(actName) 출발" : "\(actName) \(floor)층" }
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
