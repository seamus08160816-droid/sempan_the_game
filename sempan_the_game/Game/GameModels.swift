import Foundation

// MARK: - 밸런스 조정용 값 (원본 CFG 그대로)

enum CFG {
    static let baseHP: Double = 60                    // 1막 1층 체력
    static let actGrowth: [Double] = [1.30, 1.40, 1.50, 1.55] // 막별 층당 체력 배율
    static let growthAfter: Double = 1.6              // 표 이후 막의 층당 배율
    static let eliteMult: Double = 1.5
    static let bossMult: Double = 1.8
    /// 숫자 단계(1~6막) 몹 체력 보정: 1층은 hpScale0배에서 시작해, 층마다 그 막의 hpRamp만큼 곱해 가요.
    /// 보상(물가)은 그대로라 낮추면 실제로 쉬워지고 높이면 실제로 어려워져요. 로그 단계에는 쓰지 않아요
    static let hpScale0: Double = 0.75
    static let hpRamp: [Int: Double] = [2: 1.0292, 3: 1.10, 4: 1.13, 5: 1.12, 6: 1.12]
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
    static let logAct = 7                             // 이 막부터 로그 단계 (차원 상승). 7~8막 변신은 로그 단계에서 자릿수를 늘리는 카드예요
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
        case .amp: L("증폭", "AMP")
        case .stack: L("적립", "ACC")
        case .flip: L("역전", "REV")
        case .exact: L("정확", "EXACT")
        }
    }

    var name: String {
        switch self {
        case .gold: L("황금", "Gold")
        case .fire: L("불꽃", "Fire")
        case .luck: L("행운", "Luck")
        case .amp: L("증폭", "Amplify")
        case .stack: L("적립", "Accumulate")
        case .flip: L("역전", "Reversal")
        case .exact: L("정확", "Exact")
        }
    }

    var desc: String {
        switch self {
        case .gold: L("수식에 쓰면 최종 결과 ×2", "Doubles the final result when used in an equation")
        case .fire: L("수식에 쓰면 최종 결과에 더해요. 적 체력과 함께 커져요", "Adds a bonus to the final result. Grows with enemy HP")
        case .luck: L("수식에 쓰면 25% 확률로 최종 결과 ×5", "25% chance to multiply the final result by 5")
        case .amp: L("오른쪽 수를 세 배로 더해요", "Adds the right-hand number three times")
        case .stack: L("보너스를 함께 더하고, 쓸 때마다 보너스가 \(Int(CFG.stackStep))×물가만큼 영구히 커져요", "Adds a bonus that grows by \(Int(CFG.stackStep))× the price level every time it is used")
        case .flip: L("빼서 음수가 되면 빼는 대신 두 수를 더하고 ×4", "If the subtraction goes negative, adds the two numbers instead and multiplies by 4")
        case .exact: L("나누어떨어지면 나누는 대신 두 수를 곱하고 ×2", "If it divides evenly, multiplies the two numbers instead and doubles the result")
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

    var name: String {
        switch self {
        case .sq: L("제곱", "Square")
        case .pow2: L("2의 거듭제곱", "Power of two")
        case .exp: L("자연지수", "Natural exponent")
        case .fact: L("팩토리얼", "Factorial")
        case .selfPow: L("자기거듭제곱", "Self-power")
        case .sfact: L("슈퍼팩토리얼", "Superfactorial")
        case .hfact: L("하이퍼팩토리얼", "Hyperfactorial")
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
        }
    }

    var isSpecial: Bool { false }

    /// 막마다 하나씩 해금되는 변신 사다리
    static let ladder = allCases

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

    var label: String { kind == .num ? L("숫자 \(faceText)", "Number \(faceText)") : L("\(op?.symbol ?? "") 카드", "\(op?.symbol ?? "") card") }

    /// 수식 글자: 다섯 장이면 앞의 세 장을 괄호로 묶어 계산 순서를 보여줘요
    static func exprText(_ cs: [Card]) -> String {
        let faces = cs.map(\.faceText)
        guard faces.count == 5 else { return faces.joined(separator: " ") }
        return "(\(faces[0..<3].joined(separator: " "))) \(faces[3...].joined(separator: " "))"
    }

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

extension Card {
    /// 예전 저장에 지금은 없는 변신(예: 테트레이션)이 붙어 있으면 평범한 숫자로 읽어요
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        kind = try c.decode(CardKind.self, forKey: .kind)
        v = try c.decodeIfPresent(Int.self, forKey: .v) ?? 0
        op = try c.decodeIfPresent(Op.self, forKey: .op)
        enh = try c.decodeIfPresent([Enh].self, forKey: .enh) ?? []
        up = try c.decodeIfPresent(Int.self, forKey: .up) ?? 0
        tr = (try? c.decodeIfPresent(Transform.self, forKey: .tr)) ?? nil
        bonus = try c.decodeIfPresent(Double.self, forKey: .bonus) ?? 0
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
        case .mob: L("몹", "Monster")
        case .elite: L("정예", "Elite")
        case .shop: L("상점", "Shop")
        case .boss: L("보스", "Boss")
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

    /// 저장에는 한국어 이름을 두고, 화면에 보일 때만 지금 언어로 바꿔요
    private static let english: [String: String] = [
        "계산 슬라임": "Calc Slime", "나머지 고블린": "Remainder Goblin", "분모 박쥐": "Denominator Bat", "소수점 쥐": "Decimal Rat",
        "괄호 거미": "Bracket Spider", "오답 유령": "Wrong-Answer Ghost", "반올림 두더지": "Rounding Mole", "약수 버섯": "Divisor Mushroom",
        "구구단 기사": "Times-Table Knight", "약분 마법사": "Fraction Mage", "통분 쌍둥이": "Common-Denominator Twins", "검산 감시자": "Checksum Sentinel",
        "방정식 골렘": "Equation Golem", "무한소 군주": "Infinitesimal Lord", "미지수 용": "Dragon of Unknowns", "증명 거인": "Proof Giant",
        "상점": "Shop", "몹": "Monster", "정예": "Elite", "보스": "Boss"
    ]

    static func display(_ name: String) -> String {
        Lang.shared.isKorean ? name : (english[name] ?? name)
    }

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

/// 하나가 읽히지 않아도 나머지는 살리는 배열 원소
private struct Lossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

extension RewardState {
    /// 예전 저장에 지금은 없는 특전(예: 테트레이션)이 있으면 그 선택지만 빼요
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        count = try c.decode(Int.self, forKey: .count)
        idx = try c.decode(Int.self, forKey: .idx)
        offers = try c.decode([Lossy<Perk>].self, forKey: .offers).compactMap(\.value)
    }
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

    var actName: String { isLog ? L("로그 \(act - CFG.logAct + 1)막", "Log Act \(act - CFG.logAct + 1)") : L("\(act)막", "Act \(act)") }

    /// 로그 단계의 체력은 10의 거듭제곱, 피해는 자릿수예요
    func hpText(_ x: Double) -> String { isLog ? "10^\(Fmt.n(x))" : Fmt.n(x) }
    func dmgText(_ x: Double) -> String { isLog ? L("\(Fmt.n(x))자리", "\(Fmt.n(x)) digits") : Fmt.n(x) }

    func hasPerk(_ k: MetaPerk) -> Bool { (perks ?? []).contains(k.rawValue) }
    func perkReady(_ k: MetaPerk) -> Bool { hasPerk(k) && perkUsed?[k.rawValue] != act }

    static func growthOf(_ act: Int) -> Double {
        act - 1 < CFG.actGrowth.count ? CFG.actGrowth[act - 1] : CFG.growthAfter
    }

    /// 숫자 단계 체력 보정 배율 (층마다 이어져서 막이 바뀔 때 튀지 않아요)
    static func hpScaleAt(_ depth: Int) -> Double {
        var s = CFG.hpScale0
        if depth >= 2 {
            for d in 2...depth { s *= CFG.hpRamp[Int((Double(d) / Double(CFG.actLen)).rounded(.up))] ?? 1 }
        }
        return s
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
        if !isLog { h *= Self.hpScaleAt(depthOf(max(1, f))) }
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

    var whereText: String { floor == 0 ? L("\(actName) 출발", "\(actName) start") : L("\(actName) \(floor)층", "\(actName) F\(floor)") }
}

// MARK: - 숫자 표시

enum Fmt {
    private static let units: [(Double, String)] = [(1e16, "경"), (1e12, "조"), (1e8, "억"), (1e4, "만")]
    /// 영어: 짧은 단위 (K는 10만~100만 아래에서만)
    private static let unitsEn: [(Double, String)] = [(1e18, "Qi"), (1e15, "Qa"), (1e12, "T"), (1e9, "B"), (1e6, "M"), (1e3, "K")]

    private static let formatterKo = makeFormatter("ko_KR")
    private static let formatterEn = makeFormatter("en_US")

    private static func makeFormatter(_ id: String) -> NumberFormatter {
        let f = NumberFormatter()
        f.locale = Locale(identifier: id)
        f.numberStyle = .decimal
        f.maximumFractionDigits = 2
        return f
    }

    private static func grouped(_ n: Double) -> String {
        (Lang.shared.isKorean ? formatterKo : formatterEn).string(from: NSNumber(value: n)) ?? String(n)
    }

    /// 3자리 유효숫자로 반올림
    private static func sig3(_ x: Double) -> Double {
        let digits = floor(log10(abs(x))) + 1
        let factor = pow(10, 3 - digits)
        return (x * factor).rounded() / factor
    }

    /// 원본 fmt(): 한국어는 만·억·조·경, 영어는 K·M·B·T·Qa·Qi 단위로 짧게 보여줘요
    static func n(_ n: Double) -> String {
        guard n.isFinite else { return "∞" }
        let a = abs(n)
        if a < 1e5 { return grouped((n * 100).rounded() / 100) }
        let sci = Lang.shared.isKorean ? 1e20 : 1e21
        if a >= sci {
            let exponent = Int(floor(log10(a)))
            let mantissa = n / pow(10, Double(exponent))
            return String(format: "%.2f×10^%d", mantissa, exponent)
        }
        for (u, name) in (Lang.shared.isKorean ? units : unitsEn) where a >= u {
            return grouped(sig3(n / u)) + name
        }
        return grouped(n)
    }
}
