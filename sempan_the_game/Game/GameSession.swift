import Foundation
import Observation

/// 업적·도감 알림
struct Toast: Identifiable, Equatable {
    let id = UUID()
    let icon: String
    let title: String
    let subtitle: String
}

/// 수식 계산 결과
struct EvalResult {
    var steps: [(text: String, note: String)] = []
    var fx: [(text: String, style: LogStyle)] = []
    var final: Double = 0
    var hasLuck = false
    var luckHit = false
}

// MARK: - 전투 덱 조작

extension FightState {
    /// 숫자 덱과 기호 덱을 합친 곳에서 무작위로 한 장 뽑아요. 덱이 비면 버린 더미를 섞어 다시 써요
    mutating func drawOne() -> Int? {
        var n = numDraw.count, o = opDraw.count
        if n + o == 0 {
            if numPile.isEmpty && opPile.isEmpty { return nil }
            numDraw = numPile.shuffled(); opDraw = opPile.shuffled()
            numPile = []; opPile = []
            n = numDraw.count; o = opDraw.count
        }
        return Double.random(in: 0..<1) * Double(n + o) < Double(n) ? numDraw.popLast() : opDraw.popLast()
    }

    mutating func toPile(_ c: Card) {
        if c.kind == .num { numPile.append(c.id) } else { opPile.append(c.id) }
    }
}

// MARK: - 게임 진행

@Observable
final class GameSession {
    let slot: Int
    @ObservationIgnored private let store: SaveStore

    var run: RunState
    var busy = false
    var shakeCount = 0
    /// 흔들림 세기 (1~4, 때리는 소리 단계와 같아요)
    var shakeLevel = 2
    /// 화면을 덮는 등장 장면 (보스, 차원 상승)
    var intro: Intro?
    var showStamp = false
    var tossing = false
    var finalPop = false
    var previewOverride: String?
    var toasts: [Toast] = []
    /// 방금 뽑힌 카드 (등장 애니메이션용)
    var freshIDs: Set<Int> = []
    /// 이미 저장했지만 계산 연출이 끝날 때까지 체력 막대에 숨겨 두는 피해
    var hiddenDamage: Double = 0

    init(slot: Int, store: SaveStore) {
        self.slot = slot
        self.store = store
        if let saved = store.profile(slot).run {
            run = saved
            // 계산 연출 도중에 앱이 꺼졌다면 저장된 결과로 승패를 마저 정해요
            if run.fight?.resolving == true && run.reward == nil { finish(settle()) }
        } else {
            run = RunState()
            newGame()
        }
    }

    var profile: SlotProfile { store.profile(slot) }

    // MARK: 저장과 업적

    private func updateProfile(_ change: (inout SlotProfile) -> Void) {
        var unlocked: [Achievement] = []
        var perks: [MetaPerk] = []
        store.update(slot) { p in
            change(&p)
            unlocked = p.evaluateAchievements()
            perks = p.evaluatePerks()
        }
        for a in unlocked { pushToast(Toast(icon: a.icon, title: "업적 달성!", subtitle: a.title)) }
        // 한꺼번에 여럿 풀리면 (예전 기록으로 처음 열 때) 알림 하나로 묶어요
        if perks.count > 2 {
            let names = perks.prefix(3).map(\.name).joined(separator: ", ")
            pushToast(Toast(icon: "🎒", title: "퍽 해금! 메인 화면에서 장착해요", subtitle: "\(names) 외 \(perks.count - 3)개"))
        } else {
            for k in perks { pushToast(Toast(icon: k.icon, title: "퍽 해금! 메인 화면에서 장착해요", subtitle: k.name)) }
        }
        if !unlocked.isEmpty || !perks.isEmpty { Sound.shared.play(.fanfare) }
    }

    // MARK: 퍽

    /// 다음 판에 쓸 퍽 (새 게임을 시작하기 전에만 골라요)
    func setEquipped(_ list: [String]) {
        updateProfile { $0.equipped = list }
    }

    private func usePerk(_ k: MetaPerk) {
        var used = run.perkUsed ?? [:]
        used[k.rawValue] = run.act
        run.perkUsed = used
    }

    /// 막을 시작할 때 (1막 포함)
    private func actStart() -> String {
        guard run.hasPerk(.allowance) else { return "" }
        let g = (12 * run.econ(at: 1)).rounded()
        run.gold += g
        run.goldTotal += g
        return " 비상금 +\(Fmt.n(g))골드."
    }

    /// 진행 중인 판을 슬롯에 저장해요
    func save() {
        guard run.over == nil else { return }
        let snapshot = run
        updateProfile { p in
            p.run = snapshot
            p.stats.maxGold = max(p.stats.maxGold, snapshot.gold)
            p.stats.maxAct = max(p.stats.maxAct, snapshot.act)
            p.stats.maxDepth = max(p.stats.maxDepth ?? 0, snapshot.depth)
        }
    }

    private func collect(_ cards: [Card], silent: Bool = false) {
        var newKeys: [String] = []
        updateProfile { p in
            for c in cards { newKeys += p.collect(c) }
        }
        guard !silent else { return }
        if !newKeys.isEmpty { Sound.shared.play(.chime, volume: 0.8) }
        for key in newKeys {
            if let entry = CardCatalog.entries.first(where: { $0.key == key }) {
                pushToast(Toast(icon: "🃏", title: "도감 등록", subtitle: entry.title))
            }
        }
    }

    func pushToast(_ t: Toast) {
        toasts.append(t)
        // 알림은 3개까지만 쌓아요
        if toasts.count > 3 { toasts.removeFirst(toasts.count - 3) }
        Task {
            try? await Task.sleep(for: .seconds(2.6))
            toasts.removeAll { $0.id == t.id }
        }
    }

    private func wait(_ ms: Int) async {
        try? await Task.sleep(for: .milliseconds(ms))
    }

    // MARK: 시작과 끝

    private func mk(_ kind: CardKind, num: Int = 0, op: Op = .add) -> Card {
        defer { run.nextID += 1 }
        return kind == .num ? .number(run.nextID, num) : .symbol(run.nextID, op)
    }

    private func newDeck() -> [Card] {
        var d: [Card] = []
        for _ in 0..<2 { for n in 1...9 { d.append(mk(.num, num: n)) } }
        for (o, c) in [(Op.add, 4), (.sub, 3), (.div, 3), (.mul, 2)] {
            for _ in 0..<c { d.append(mk(.op, op: o)) }
        }
        return d
    }

    func newGame() {
        run = RunState()
        busy = false
        run.deck = newDeck()
        run.map = genAct()
        let p = profile
        // 장착한 퍽은 판을 시작할 때 정해져요
        let unlocked = p.perksUnlocked ?? []
        run.perks = Array((p.equipped ?? []).filter { unlocked.contains($0) }.prefix(MetaPerk.slots))
        run.mapMsg = (p.bestDepth > 0
            ? "역대 기록: \(p.bestDepth)층까지, 한 방 \(Fmt.n(p.bestSingle))."
            : "1층에서 출발할 칸을 고르세요.") + actStart()
        updateProfile { $0.stats.runsStarted += 1 }
        collect(run.deck, silent: true)
        save()
    }

    private func gameOver(_ reason: String) {
        busy = true
        var rec = false
        let finished = run
        updateProfile { p in
            if finished.depth > p.bestDepth { p.bestDepth = finished.depth; rec = true }
            if finished.bestPlay > p.bestSingle { p.bestSingle = finished.bestPlay; rec = true }
            p.stats.runsFinished += 1
            p.stats.maxAct = max(p.stats.maxAct, finished.act)
            // 끝난 판은 슬롯에서 지워요 (기록과 업적은 남아요)
            p.run = nil
        }
        run.over = GameOverInfo(reason: reason, newRecord: rec)
    }

    // MARK: 길 생성

    private func genAct() -> [[MapNode]] {
        var floors: [[MapNode]] = []
        for f in 1...CFG.actLen {
            let n: Int
            if f == CFG.actLen { n = 1 }
            else if f == 1 { n = 2 + Int.random(in: 0..<2) }
            else { let r = Double.random(in: 0..<1); n = r < 0.2 ? 1 : r < 0.65 ? 2 : 3 }
            var row: [MapNode] = []
            for i in 0..<n {
                let jit = (Double.random(in: 0..<1) - 0.5) * 8
                let x = n == 1 ? 52 + jit : 20 + 64 * (Double(i) / Double(n - 1)) + jit
                var type: NodeType = .mob
                if f == CFG.actLen { type = .boss }
                else if f > 1 {
                    let r = Double.random(in: 0..<1)
                    type = r < CFG.shopRate ? .shop : r < CFG.shopRate + CFG.eliteRate ? .elite : .mob
                }
                if f == CFG.actLen - 1 && type == .elite { type = .mob }
                row.append(MapNode(id: "\(f)-\(i)", floor: f, x: x, type: type, next: [], name: ""))
            }
            floors.append(row)
        }
        // 이웃 층끼리 교차하지 않는 길로 잇기 (모든 칸에 들어오고 나가는 길이 하나 이상)
        for f in 0..<(floors.count - 1) {
            let aCount = floors[f].count, bCount = floors[f + 1].count
            var i = 0, j = 0
            func link() {
                let target = floors[f + 1][j].id
                if !floors[f][i].next.contains(target) { floors[f][i].next.append(target) }
            }
            link()
            while i < aCount - 1 || j < bCount - 1 {
                let r = Double.random(in: 0..<1), ci = i < aCount - 1, cj = j < bCount - 1
                if ci && cj && r < 0.3 { i += 1; j += 1 }
                else if ci && (!cj || r < 0.65) { i += 1 }
                else { j += 1 }
                link()
            }
        }
        // 막마다 상점 하나는 보장
        let mid = Array(2..<(CFG.actLen - 1))
        if !mid.contains(where: { fi in floors[fi].contains { $0.type == .shop } }),
           let fi = mid.randomElement(), let ni = floors[fi].indices.randomElement() {
            floors[fi][ni].type = .shop
        }
        for f in floors.indices {
            for i in floors[f].indices { floors[f][i].name = MobNames.random(for: floors[f][i].type) }
        }
        return floors
    }

    // MARK: 지도

    func enterNode(_ n: MapNode) {
        guard run.reachable(n), !busy else { return }
        guard n.type == .boss else { enter(n); return }
        // 보스 앞: 화면이 어두워지며 이름판이 꽂히고 무거운 종이 울려요
        let sub = "\(run.actName) 보스 · 체력 \(run.hpText(run.hpFor(n.floor, .boss)))"
        Task {
            await showIntro(Intro(icon: "👑", title: n.name, sub: sub))
            enter(n)
        }
    }

    private func showIntro(_ it: Intro) async {
        busy = true
        intro = it
        await wait(350)
        Sound.shared.play(.bell)
        await wait(1900)
        intro = nil
        busy = false
    }

    private func enter(_ n: MapNode) {
        run.curID = n.id
        run.visited.insert(n.id)
        run.floor = n.floor
        run.depth = run.depthOf(n.floor)
        if n.type == .shop { openShop() } else { startFight(n) }
    }

    private func afterNode(_ message: String) {
        var msg = message
        if run.floor >= CFG.actLen {
            // 차원 상승: 골드와 적립 보너스를 새 단위로 바꿔요 (물가가 1로 돌아가요)
            let ascending = run.act + 1 == CFG.logAct
            let oldEcon = run.econ(at: CFG.actLen)
            run.act += 1
            run.map = genAct()
            run.floor = 0
            run.curID = nil
            run.visited = []
            if ascending {
                run.gold = (run.gold / oldEcon).rounded()
                for i in run.deck.indices where run.deck[i].enh.contains(.stack) {
                    let bonus = max(CFG.stackStep, (run.deck[i].bonus / oldEcon).rounded())
                    run.deck[i].bonus = bonus
                }
                msg += " 차원 상승! 이제 체력은 10의 거듭제곱이고, 계산 결과의 자릿수(log₁₀)만큼 깎여요. 골드도 새 단위로 바뀌었어요."
                Task { await showIntro(Intro(icon: "🌌", title: "차원 상승", sub: "로그 단계 · 결과의 자릿수가 피해가 돼요")) }
            } else {
                msg += " \(run.actName)이 시작됐어요."
            }
            if let t = Transform.ladder.first(where: { $0.act == run.act }) {
                msg += " 이제 \(t.name) 변신 강화가 나와요."
            }
            if run.act == 6 { msg += " 이제 × 카드를 ^ 카드로 진화시킬 수 있어요." }
            if run.act == 8 { msg += " 이번 막 보스부터 테트레이션 카드를 줘요." }
            msg += actStart()
        }
        run.mapMsg = msg
        run.fight = nil
        run.shop = nil
        run.phase = .map
        save()
    }

    // MARK: 전투

    private func startFight(_ node: MapNode) {
        let nums = run.deck.filter { $0.kind == .num }.map(\.id).shuffled()
        let ops = run.deck.filter { $0.kind == .op }.map(\.id).shuffled()
        var f = FightState(nodeID: node.id, hpMax: run.hpFor(run.floor, node.type),
                           playsLeft: run.plays, discLeft: run.discards, numDraw: nums, opDraw: ops)
        let rate = run.leftoverRate
        let logRule = run.isLog ? " 로그 단계라서 계산 결과의 자릿수(log₁₀)만큼 체력의 지수가 깎여요." : ""
        f.log = [LogLine(text: "\(node.name)이(가) 나타났어요. \(run.plays)번 안에 체력 \(run.hpText(f.hpMax))을 깎으세요.\(logRule) 이기면 남은 계산 1번당 \(Fmt.n(rate.play))골드, 버리기 1번당 \(Fmt.n(rate.disc))골드를 받아요.", style: .info)]
        run.fight = f
        run.phase = .fight
        refill()
        if run.hasPerk(.study) { ensureNumbers(4) }
        save()
        checkStuck()
    }

    var fightNode: MapNode? { run.node(run.fight?.nodeID) }

    /// 예습: 첫 손패의 기호 카드를 숫자 덱의 카드와 바꿔 숫자를 n장 이상으로 맞춰요
    private func ensureNumbers(_ n: Int) {
        guard var f = run.fight else { return }
        var count = f.handCards.filter { run.card($0.cardID)?.kind == .num }.count
        for i in f.handCards.indices {
            guard count < n, let num = f.numDraw.popLast() else { break }
            guard run.card(f.handCards[i].cardID)?.kind == .op else { f.numDraw.append(num); continue }
            f.opDraw.insert(f.handCards[i].cardID, at: Int.random(in: 0...f.opDraw.count))
            f.handCards[i].cardID = num
            freshIDs.insert(num)
            count += 1
        }
        run.fight = f
    }

    /// 연필 깎기: 손패를 모두 버린 더미로 보내고 새로 뽑아요 (버리기를 쓰지 않아요)
    func sharpen() {
        guard !busy, var f = run.fight, run.perkReady(.sharpen) else { return }
        usePerk(.sharpen)
        f.sel = []
        for h in f.handCards { if let c = run.card(h.cardID) { f.toPile(c) } }
        f.handCards = []
        run.fight = f
        refill()
        Sound.shared.play(.toss)
        log("연필 깎기: 손패를 새로 뽑았어요", .info)
        save()
        checkStuck()
    }

    func cmpCard(_ a: Card, _ b: Card) -> Bool {
        if a.kind == b.kind {
            if a.kind == .num {
                return a.numVal != b.numVal ? a.numVal < b.numVal : a.v < b.v
            }
            return (a.op?.order ?? 0) < (b.op?.order ?? 0)
        }
        return a.kind == .num
    }

    private func refill() {
        guard var f = run.fight else { return }
        f.handCards.removeAll { $0.out }
        var fresh: Set<Int> = []
        while f.handCards.count < run.hand {
            guard let id = f.drawOne() else { break }
            f.handCards.append(HandCard(cardID: id, out: false))
            fresh.insert(id)
        }
        // 부채꼴 손패는 정렬하지 않고 뽑은 순서대로 둬요
        run.fight = f
        freshIDs = fresh
    }

    var selectedCards: [Card] { (run.fight?.sel ?? []).compactMap { run.card($0) } }

    func validity(_ s: [Card]) -> (ok: Bool, msg: String) {
        if s.isEmpty { return (false, "손패를 누르거나 훑어서 카드를 골라 수식을 만드세요") }
        for (i, c) in s.enumerated() where (i % 2 == 0) != (c.kind == .num) {
            return (false, "숫자와 기호를 번갈아 놓아야 해요")
        }
        if s.count % 2 == 0 { return (false, "숫자로 끝나야 계산할 수 있어요") }
        return (true, "")
    }

    /// 강화 효과를 빼고 왼쪽부터 계산한 값과 단계별 기록. 값은 큰 수라 아무리 커져도 무한대가 되지 않아요
    private func chain(_ cs: [Card]) -> (val: BigNum, steps: [(text: String, note: String)]) {
        guard let first = cs.first else { return (.of(0), []) }
        var steps: [(text: String, note: String)] = []
        var val = BigNum.of(first.numVal)
        var i = 1
        while i + 1 < cs.count {
            let o = cs[i], b = BigNum.of(cs[i + 1].numVal), a = val
            var r: BigNum
            var note = ""
            switch o.op ?? .add {
            case .add:
                if o.enh.contains(.amp) { r = a + b * .of(3); note = "증폭: 오른쪽 ×3" } else { r = a + b }
                if o.enh.contains(.stack) { r = r + .of(o.bonus); note = "적립 +\(Fmt.n(o.bonus))" }
            case .sub:
                // 역전은 빼서 음수가 될 때 발동해서, 빼는 대신 두 수를 더하고 ×4 해요
                r = a - b
                if o.enh.contains(.flip) && r.s < 0 { r = (a + b) * .of(4); note = "역전: 더하고 ×4" }
            case .mul:
                r = a * b
            case .div:
                if o.enh.contains(.exact) && BigNum.divides(a, b) { r = a * b * .of(2); note = "정확: 곱하고 ×2" }
                else { r = a / b }
            case .pow:
                r = a.power(b)
                if abs(b.num) > CFG.powCap { note = "지수는 \(Int(CFG.powCap))까지" }
            }
            val = r
            let shown = o.enh.contains(.amp) ? "\(a.text) + \(b.text)×3" : "\(a.text) \(o.op?.symbol ?? "") \(b.text)"
            steps.append(("\(shown) = \(r.text)", note))
            i += 2
        }
        return (val, steps)
    }

    func evaluate(_ cs: [Card], roll: Bool) -> EvalResult {
        var res = EvalResult()
        guard !cs.isEmpty else { return res }
        let chained = chain(cs)
        res.steps = chained.steps
        // 로그 단계는 결과의 자릿수가 피해의 바탕이에요. 강화 효과는 그 자릿수에 붙어요
        var val: Double
        if run.isLog {
            val = chained.val.s > 0 ? max(0, chained.val.log) : 0
            res.steps.append(("자릿수 log₁₀ = \(Fmt.n((val * 100).rounded(.down) / 100))", "로그 단계"))
        } else {
            val = chained.val.v ?? chained.val.s * BigNum.big
        }
        let fire = run.fireBonus
        for c in cs where c.enh.contains(.fire) {
            val += fire
            res.fx.append(("불꽃 +\(Fmt.n(fire))", .fx))
        }
        for c in cs where c.enh.contains(.gold) {
            val *= 2
            res.fx.append(("황금 ×2", .fxGold))
        }
        let chance = run.hasPerk(.clover) ? 0.35 : CFG.luckChance
        for c in cs where c.enh.contains(.luck) {
            res.hasLuck = true
            if roll {
                if Double.random(in: 0..<1) < chance {
                    val *= 5
                    res.luckHit = true
                    res.fx.append(("행운 ×5!!", .fxGold))
                } else {
                    res.fx.append(("행운은 다음 기회에", .miss))
                }
            }
        }
        res.final = max(0, run.isLog ? (val * 10).rounded(.down) / 10 : min(val, BigNum.big).rounded(.down))
        return res
    }

    /// 수식이 정확 ÷ 카드로 끝날 때, 그 뒤에 놓으면 나누어떨어지는 손패 숫자 카드들 (후광 표시용)
    var exactDivisorIDs: Set<Int> {
        let sel = selectedCards
        guard let last = sel.last, last.op == .div, last.enh.contains(.exact), let f = run.fight else { return [] }
        let a = chain(Array(sel.dropLast())).val
        let ids = f.handCards.filter { !$0.out }.compactMap { run.card($0.cardID) }
            .filter { $0.kind == .num && BigNum.divides(a, .of($0.numVal)) }.map(\.id)
        return Set(ids)
    }

    func select(_ id: Int) {
        guard !busy, var f = run.fight else { return }
        if f.sel.count >= CFG.maxLen {
            previewOverride = "수식은 최대 \(CFG.maxLen)장이에요"
            return
        }
        guard let i = f.handCards.firstIndex(where: { $0.cardID == id && !$0.out }) else { return }
        f.handCards[i].out = true
        f.sel.append(id)
        Sound.shared.play(.place)
        run.fight = f
        freshIDs = []
        previewOverride = nil
    }

    func unselect(_ id: Int) {
        guard !busy, var f = run.fight, let i = f.sel.firstIndex(of: id) else { return }
        f.sel.remove(at: i)
        if let h = f.handCards.firstIndex(where: { $0.cardID == id }) { f.handCards[h].out = false }
        Sound.shared.play(.place, rate: 0.8)
        run.fight = f
        freshIDs = []
        previewOverride = nil
    }

    func discard() async {
        guard !busy, let f0 = run.fight, !f0.sel.isEmpty, f0.discLeft > 0 else { return }
        busy = true
        tossing = true
        Sound.shared.play(.toss)
        await wait(400)
        guard var f = run.fight else { busy = false; tossing = false; return }
        for c in selectedCards { f.toPile(c) }
        f.sel = []
        f.discLeft -= 1
        run.fight = f
        tossing = false
        refill()
        busy = false
        save()
        checkStuck()
    }

    private func checkStuck() {
        guard let f = run.fight else { return }
        let hasNum = f.handCards.contains { run.card($0.cardID)?.kind == .num }
        if !hasNum && f.discLeft == 0 && f.playsLeft > 0 {
            gameOver("낼 수 있는 숫자 카드가 없고 버리기도 다 썼어요")
        }
    }

    private func shake(_ level: Int) {
        shakeLevel = level
        shakeCount += 1
    }

    private func log(_ text: String, _ style: LogStyle, note: String = "") {
        run.fight?.log.append(LogLine(text: text, note: note, style: style))
    }

    func play() async {
        let cs = selectedCards
        guard !busy, validity(cs).ok, var f = run.fight, f.playsLeft > 0 else { return }
        busy = true
        f.sel = []
        f.playsLeft -= 1
        for c in cs { f.toPile(c) }
        let res = evaluate(cs, roll: true)
        // 적립 카드는 쓸 때마다 보너스가 지금 물가만큼 커져요
        let step = stackStep
        for c in cs where c.enh.contains(.stack) {
            if let di = run.deck.firstIndex(where: { $0.id == c.id }) { run.deck[di].bonus += step }
        }
        // 행운 결과를 연출 전에 먼저 저장해서, 앱을 껐다 켜도 다시 굴릴 수 없게 해요
        f.score += res.final
        f.resolving = true
        f.log = [LogLine(text: cs.map(\.faceText).joined(separator: " "), style: .expr)]
        run.fight = f
        // 한 방 기록은 숫자 단계에서만 쳐요 (로그 단계의 자릿수와 섞이지 않게)
        let isLog = run.isLog
        if !isLog { run.bestPlay = max(run.bestPlay, res.final) }
        hiddenDamage = res.final
        freshIDs = []
        previewOverride = nil
        finalPop = false
        save()
        let luckHit = res.luckHit
        updateProfile { p in
            if !isLog { p.stats.maxHit = max(p.stats.maxHit, res.final) }
            if luckHit { p.stats.luckProcs += 1 }
        }

        for st in res.steps {
            await wait(380)
            log(st.text, .step, note: st.note)
            Sound.shared.play(.tick)
        }
        for fx in res.fx {
            await wait(450)
            log(fx.text, fx.style)
            if fx.style == .miss {
                Sound.shared.play(.miss)
            } else {
                Sound.shared.play(fx.text.hasPrefix("행운") ? .luck : .sparkle)
                shake(1)
            }
        }
        await wait(200)

        // 최종 결과 숫자를 세어 올려요. 연필 톡 소리가 점점 높아지며 때리는 소리로 이어져요
        log("0", .final)
        let frames = 20
        for k in 1...frames {
            let p = Double(k) / Double(frames)
            let e = 1 - pow(1 - p, 3)
            if let last = run.fight?.log.indices.last {
                // 글자를 먼저 만들어 두어야 run을 읽고 쓰는 일이 겹치지 않아요 (겹치면 앱이 멈춰요)
                let text = run.dmgText(isLog ? (res.final * e * 10).rounded(.down) / 10 : (res.final * e).rounded(.down))
                run.fight?.log[last].text = text
            }
            if k % 3 == 1 { Sound.shared.play(.tick, volume: 0.45, rate: Float(1 + 0.7 * p)) }
            await wait(500 / frames)
        }
        finalPop = true
        hiddenDamage = 0
        // 때리는 순간: 피해가 클수록 더 높고 거친 소리와 더 큰 흔들림
        let level = Sound.hitLevel(res.final, f.hpMax)
        Sound.shared.play(SFX(rawValue: "hit\(level)") ?? .miss)
        if level >= 2 { shake(level) }
        let outcome = settle()
        switch outcome {
        case .win:
            showStamp = true
            await wait(1200)
            showStamp = false
        case .lose:
            await wait(700)
        case .next:
            break
        }
        finish(outcome)
    }

    private enum Outcome {
        case win(rewards: Int), lose(reason: String), next
    }

    /// 저장된 계산 결과로 승패를 정하고 골드와 기록을 반영해요
    private func settle() -> Outcome {
        guard var f = run.fight, let node = fightNode else { return .next }
        f.resolving = nil
        // 뒷심: 막마다 한 번, 거의 다 잡았으면 한 번 더 계산해요
        if f.score < f.hpMax && f.playsLeft == 0 && f.hpMax - f.score <= f.hpMax * 0.2 && run.perkReady(.grit) {
            f.playsLeft = 1
            run.fight = f
            usePerk(.grit)
            log("뒷심! 한 번 더 계산할 수 있어요", .fxGold)
            return .next
        }
        run.fight = f
        if f.score >= f.hpMax {
            let over = f.score - f.hpMax
            let rate = run.leftoverRate
            let g1 = (CFG.killGold * run.econ).rounded()
            let g2 = RunState.overkillGold(over, f.hpMax, node.type)
            let g3 = Double(f.discLeft) * rate.disc
            let g4 = Double(f.playsLeft) * rate.play
            let gain = g1 + g2 + g3 + g4
            run.gold += gain
            run.goldTotal += gain
            run.kills += 1
            run.lastGold = GoldBreakdown(g1: g1, g2: g2, g3: g3, g4: g4, gain: gain, over: over, hp: f.hpMax,
                                         disc: f.discLeft, plays: f.playsLeft, ratePlay: rate.play, rateDisc: rate.disc, type: node.type)
            let oneShot = f.playsLeft == run.plays - 1
            let gold = run.gold
            updateProfile { p in
                p.stats.kills += 1
                if node.type == .elite { p.stats.eliteKills += 1 }
                if node.type == .boss { p.stats.bossKills += 1 }
                if oneShot { p.stats.oneShots += 1 }
                if over >= f.hpMax * 2 { p.stats.bigOverkills += 1 }
                p.stats.maxGold = max(p.stats.maxGold, gold)
            }
            log("처치 \(Fmt.n(g1)) + 초과 피해 \(Fmt.n(g2)) + 남은 계산 \(Fmt.n(g4)) + 남은 버리기 \(Fmt.n(g3)) = 골드 +\(Fmt.n(gain))", .fxGold)
            return .win(rewards: node.type == .elite ? 2 : 1)
        }
        if f.playsLeft == 0 { return .lose(reason: "\(node.name)의 체력이 \(run.hpText(f.hpMax - f.score)) 남았어요") }
        return .next
    }

    private func finish(_ outcome: Outcome) {
        busy = false
        switch outcome {
        case .win(let count):
            openReward(count: count)
        case .lose(let reason):
            gameOver(reason)
        case .next:
            refill()
            save()
            checkStuck()
        }
    }

    // MARK: 특전

    private func genPerks() -> [Perk] {
        let deck = run.deck
        let enchant: (Enh) -> () -> Perk? = { e in {
            guard let c = deck.filter({ !($0.op?.isPlain ?? false) && !$0.enh.contains(e) }).randomElement() else { return nil }
            return Perk(kind: .enchant(e), cardID: c.id, title: "\(c.label)에 \(e.name)", desc: e.desc)
        } }
        let opPerk: (Enh) -> () -> Perk? = { e in {
            guard let c = deck.filter({ $0.op == e.op && !$0.enh.contains(where: \.isOpPerk) }).randomElement() else { return nil }
            return Perk(kind: .opPerk(e), cardID: c.id, title: "\(c.label)에 \(e.name)", desc: e.desc)
        } }
        let upNum: () -> Perk? = {
            // 변신 상한에 닿은 카드는 n을 올려도 값이 그대로라 빼요
            guard let c = deck.filter({ $0.kind == .num && $0.v < ($0.tr?.cap ?? .max) }).randomElement() else { return nil }
            return Perk(kind: .upNum, cardID: c.id, title: "숫자 \(c.faceText)의 n을 \(c.v + 3)으로", desc: "이 카드의 값이 영구히 3 올라요")
        }
        let trPerk: (Transform) -> () -> Perk? = { t in {
            // 값이 내려가는 변신은 내지 않아요 (예: 3² = 9 → 2³ = 8)
            guard let c = deck.filter({ $0.kind == .num && $0.trIndex < t.index && t.apply(min($0.v, t.cap)) > $0.numVal }).randomElement() else { return nil }
            let after = t.apply(min(c.v, t.cap))
            let title = c.tr != nil ? "\(c.faceText)을 \(t.text(String(min(c.v, t.cap))))로" : "숫자 \(c.v)에 \(t.name)"
            return Perk(kind: .transform(t), cardID: c.id, title: title, desc: "변신하면 이 카드의 계산 값이 \(Fmt.n(after))이 돼요")
        } }
        // 6막부터: × 카드를 ^ 카드로 진화
        let act = run.act
        let evolve: () -> Perk? = {
            guard act >= 6, let c = deck.filter({ $0.op == .mul }).randomElement() else { return nil }
            return Perk(kind: .evolve, cardID: c.id, title: "× 카드를 ^ 카드로 진화", desc: "거듭제곱: 왼쪽 수를 오른쪽 수만큼 거듭제곱해요 (지수는 \(Int(CFG.powCap))까지)")
        }
        // 8막 보스부터 보상: 테트레이션 3↑↑n (입력 1 차이로 값이 수조 배씩 튀어서 로그 단계에서 쓰게 해요)
        let tetra: () -> Perk? = {
            let t = Transform.tet
            guard let c = deck.filter({ $0.kind == .num && $0.tr != .tet && t.apply(min($0.v, t.cap)) > $0.numVal }).randomElement() else { return nil }
            return Perk(kind: .transform(t), cardID: c.id, title: "숫자 \(c.faceText)에 테트레이션", desc: "보스 보상: 3↑↑n으로 변신해 계산 값이 \(Fmt.n(t.apply(min(c.v, t.cap))))이 돼요 (n은 \(t.cap)까지)")
        }
        let hand = run.hand, plays = run.plays, discards = run.discards
        var gens: [() -> Perk?] = [
            evolve, evolve,
            upNum, upNum,
            enchant(.gold), enchant(.fire), enchant(.fire), enchant(.luck),
            opPerk(.amp), opPerk(.stack), opPerk(.flip), opPerk(.exact), opPerk(.amp), opPerk(.exact)
        ]
        for t in run.unlockedTR { gens += [trPerk(t), trPerk(t)] }
        // 손패·계산 +1은 판을 크게 바꾸므로 뽑혀도 일정 확률로만 나와요
        let rare = { Double.random(in: 0..<1) < CFG.corePerkRate }
        gens += [
            { hand < 10 && rare() ? Perk(kind: .handSize, glyph: "손+1", title: "손패 +1장", desc: "한 번에 들고 있는 카드가 늘어요") : nil },
            { plays < 6 && rare() ? Perk(kind: .plays, glyph: "계산", title: "계산 기회 +1", desc: "전투마다 한 번 더 계산할 수 있어요") : nil },
            { discards < 6 ? Perk(kind: .discards, glyph: "버림", title: "버리기 +1", desc: "전투마다 한 번 더 버릴 수 있어요") : nil }
        ]
        let node = fightNode
        // 정예 사냥꾼: 정예를 잡으면 선택지 4개
        let size = node?.type == .elite && run.hasPerk(.hunter) ? 4 : 3
        var out: [Perk] = []
        // 같은 카드를 두 번 고르지 않고, 같은 종류의 특전도 두 번 내지 않아요
        var used: Set<String> = []
        func keys(_ o: Perk) -> [String] { [o.cardID.map { "c\($0)" }, "k" + o.kind.sameKindKey].compactMap { $0 } }
        if node?.type == .boss && run.act >= Transform.tet.act, let t = tetra() {
            out.append(t)
            used.formUnion(keys(t))
        }
        var guardCount = 0
        while out.count < size && guardCount < 200 {
            guardCount += 1
            guard let gen = gens.randomElement(), let o = gen() else { continue }
            if keys(o).contains(where: used.contains) { continue }
            used.formUnion(keys(o))
            out.append(o)
        }
        return out
    }

    private func openReward(count: Int, idx: Int = 1) {
        run.reward = RewardState(count: count, idx: idx, offers: genPerks())
        save()
    }

    func choose(_ perk: Perk) {
        guard let reward = run.reward else { return }
        Sound.shared.play(.coins)
        if let id = perk.cardID, let i = run.deck.firstIndex(where: { $0.id == id }) {
            switch perk.kind {
            case .upNum:
                run.deck[i].v += 3
                run.deck[i].up += 1
            case .enchant(let e):
                run.deck[i].enh.append(e)
            case .opPerk(let e):
                run.deck[i].enh.append(e)
                if e == .stack { run.deck[i].bonus = stackStep }
            case .transform(let t):
                run.deck[i].tr = t
            case .evolve:
                run.deck[i].op = .pow
                run.deck[i].enh = []
            default:
                break
            }
            collect([run.deck[i]])
        }
        switch perk.kind {
        case .handSize: run.hand += 1
        case .plays: run.plays += 1
        case .discards: run.discards += 1
        default: break
        }
        if reward.idx < reward.count {
            openReward(count: reward.count, idx: reward.idx + 1)
        } else {
            run.reward = nil
            afterNode("\(fightNode?.name ?? "몹") 처치! 골드 +\(Fmt.n(run.lastGold?.gain ?? 0))")
        }
    }

    /// 다시 뽑기: 막마다 한 번 특전 선택지를 새로
    func rerollPerks() {
        guard run.reward != nil, run.perkReady(.reroll) else { return }
        usePerk(.reroll)
        // 새 선택지를 먼저 만들어 두어야 run을 읽고 쓰는 일이 겹치지 않아요
        let offers = genPerks()
        run.reward?.offers = offers
        Sound.shared.play(.swish, rate: 0.8)
        save()
    }

    // MARK: 상점

    /// 할인권: 막마다 상점 첫 구매 30% 할인
    func buyPrice(_ c: Card) -> Double {
        let p = (c.baseValue * run.econ).rounded()
        return run.phase == .shop && run.perkReady(.coupon) ? (p * 0.7).rounded() : p
    }

    /// 적립 보너스의 시작값이자 1회 증가량 (물가에 비례, 최소 기본값)
    var stackStep: Double { max(CFG.stackStep, (CFG.stackStep * run.econ).rounded()) }

    private func genShop() -> [Card] {
        var items: [Card] = []
        let trs = run.unlockedTR
        for _ in 0..<3 {
            var c = mk(.num, num: Int.random(in: 1...12))
            if !trs.isEmpty && Double.random(in: 0..<1) < 0.35 { c.tr = trs.randomElement() }
            if Double.random(in: 0..<1) < 0.35, let e = [Enh.gold, .fire, .fire, .luck].randomElement() { c.enh.append(e) }
            items.append(c)
        }
        for _ in 0..<3 {
            let op = (run.act >= 6 ? [Op.add, .add, .sub, .div, .div, .mul, .pow] : [Op.add, .add, .sub, .div, .div, .mul]).randomElement() ?? .add
            var c = mk(.op, op: op)
            if !op.isPlain {
                if Double.random(in: 0..<1) < 0.65, let e = Enh.opPerks.filter({ $0.op == op }).randomElement() {
                    c.enh.append(e)
                    if e == .stack { c.bonus = stackStep }
                }
                if Double.random(in: 0..<1) < 0.2, let e = [Enh.gold, .fire, .luck].randomElement() { c.enh.append(e) }
            }
            items.append(c)
        }
        return items
    }

    private func openShop() {
        run.shop = ShopState(items: genShop(), pendingID: nil,
                             msg: "숫자 카드는 숫자와, 기호 카드는 기호와 바꿔요. 지금 물가는 1막 1층의 \(Fmt.n(run.econ))배예요.")
        run.phase = .shop
        save()
    }

    var pendingItem: Card? {
        guard let shop = run.shop, let id = shop.pendingID else { return nil }
        return shop.items.first { $0.id == id }
    }

    func togglePending(_ c: Card) {
        guard run.gold >= buyPrice(c) else { return }
        // 오른쪽 값을 먼저 읽어 두어야 run에 대한 쓰기와 읽기가 겹치지 않아요
        let next = run.shop?.pendingID == c.id ? nil : c.id
        run.shop?.pendingID = next
    }

    func cancelSwap() { run.shop?.pendingID = nil }

    /// 고른 상점 카드를 덱의 카드와 바꿔요
    func swap(with old: Card) {
        guard let pend = pendingItem, old.kind == pend.kind else { return }
        let p = buyPrice(pend)
        guard run.gold >= p, let i = run.deck.firstIndex(where: { $0.id == old.id }) else { return }
        run.gold -= p
        if run.perkReady(.coupon) { usePerk(.coupon) }
        run.deck[i] = pend
        run.shop?.items.removeAll { $0.id == pend.id }
        run.shop?.msg = "\(old.label)을(를) 버리고 \(pend.label)을(를) 넣었어요."
        run.shop?.pendingID = nil
        updateProfile { $0.stats.cardsBought += 1 }
        collect([pend])
        save()
    }

    /// 재입고: 막마다 한 번 무료로 상점 물건을 새로
    func restock() {
        guard run.shop != nil, run.perkReady(.restock) else { return }
        usePerk(.restock)
        let items = genShop()
        run.shop?.items = items
        run.shop?.pendingID = nil
        run.shop?.msg = "재입고! 물건을 새로 들여왔어요."
        Sound.shared.play(.coins, volume: 0.6, rate: 1.2)
        save()
    }

    func leaveShop() {
        run.shop?.pendingID = nil
        var msg = "상점을 나왔어요."
        // 이자: 남은 골드의 10% (최대 물가 ×10)
        if run.hasPerk(.interest) && run.gold > 0 {
            let g = min((run.gold * 0.1).rounded(), (10 * run.econ).rounded())
            if g > 0 { run.gold += g; run.goldTotal += g; msg += " 이자 +\(Fmt.n(g))골드." }
        }
        afterNode(msg)
    }

    // MARK: 덱 설명

    var sortedDeck: [Card] { run.deck.sorted(by: cmpCard) }

    func describe(_ c: Card) -> String {
        var parts = [c.label]
        if let t = c.tr {
            parts.append("\(t.name) 변신: 계산 값 \(Fmt.n(c.numVal))\(c.v > t.cap ? " (변신은 \(t.cap)까지만 적용)" : "")")
        }
        if c.up > 0 { parts.append("강화로 +\(c.up * 3)") }
        for e in c.enh {
            var s = "\(e.name): \(e.desc)"
            if e == .stack { s += " (현재 +\(Fmt.n(c.bonus)))" }
            if e == .fire { s += " (지금 +\(Fmt.n(run.fireBonus)))" }
            parts.append(s)
        }
        if c.op == .mul { parts.append("곱셈 카드는 강화할 수 없어요") }
        if c.op == .pow { parts.append("거듭제곱: 왼쪽 수를 오른쪽 수만큼 거듭제곱해요. 지수는 \(Int(CFG.powCap))까지이고 강화할 수 없어요") }
        return parts.joined(separator: ". ")
    }
}
