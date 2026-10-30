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
    var showStamp = false
    var tossing = false
    var finalPop = false
    var previewOverride: String?
    var toasts: [Toast] = []
    /// 방금 뽑힌 카드 (등장 애니메이션용)
    var freshIDs: Set<Int> = []

    init(slot: Int, store: SaveStore) {
        self.slot = slot
        self.store = store
        if let saved = store.profile(slot).run {
            run = saved
        } else {
            run = RunState()
            newGame()
        }
    }

    var profile: SlotProfile { store.profile(slot) }

    // MARK: 저장과 업적

    private func updateProfile(_ change: (inout SlotProfile) -> Void) {
        var unlocked: [Achievement] = []
        store.update(slot) { p in
            change(&p)
            unlocked = p.evaluateAchievements()
        }
        for a in unlocked { pushToast(Toast(icon: a.icon, title: "업적 달성!", subtitle: a.title)) }
    }

    /// 진행 중인 판을 슬롯에 저장해요
    func save() {
        guard run.over == nil else { return }
        let snapshot = run
        updateProfile { p in
            p.run = snapshot
            p.stats.maxGold = max(p.stats.maxGold, snapshot.gold)
            p.stats.maxAct = max(p.stats.maxAct, snapshot.act)
        }
    }

    private func collect(_ cards: [Card], silent: Bool = false) {
        var newKeys: [String] = []
        updateProfile { p in
            for c in cards { newKeys += p.collect(c) }
        }
        guard !silent else { return }
        for key in newKeys {
            if let entry = CardCatalog.entries.first(where: { $0.key == key }) {
                pushToast(Toast(icon: "🃏", title: "도감 등록", subtitle: entry.title))
            }
        }
    }

    func pushToast(_ t: Toast) {
        toasts.append(t)
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
        run.mapMsg = p.bestDepth > 0
            ? "역대 기록: \(p.bestDepth)층까지, 한 방 \(Fmt.n(p.bestSingle))"
            : "1층에서 출발할 칸을 고르세요."
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
                let x = n == 1 ? 54 + jit : 22 + 68 * (Double(i) / Double(n - 1)) + jit
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
        run.curID = n.id
        run.visited.insert(n.id)
        run.floor = n.floor
        run.depth = run.depthOf(n.floor)
        if n.type == .shop { openShop() } else { startFight(n) }
    }

    private func afterNode(_ message: String) {
        var msg = message
        if run.floor >= CFG.actLen {
            run.act += 1
            run.map = genAct()
            run.floor = 0
            run.curID = nil
            run.visited = []
            msg += " \(run.act)막이 시작됐어요."
            if let t = Transform.allCases.first(where: { $0.act == run.act }) {
                msg += " 이제 \(t.name) 변신 강화가 나와요."
            }
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
        f.log = [LogLine(text: "\(node.name)이(가) 나타났어요. \(run.plays)번 안에 체력 \(Fmt.n(f.hpMax))을 깎으세요. 이기면 남은 계산 1번당 \(Fmt.n(rate.play))골드, 버리기 1번당 \(Fmt.n(rate.disc))골드를 받아요.", style: .info)]
        run.fight = f
        run.phase = .fight
        refill()
        save()
        checkStuck()
    }

    var fightNode: MapNode? { run.node(run.fight?.nodeID) }

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

    func evaluate(_ cs: [Card], roll: Bool) -> EvalResult {
        var res = EvalResult()
        guard let first = cs.first else { return res }
        var val = first.numVal
        var i = 1
        while i + 1 < cs.count {
            let o = cs[i], b = cs[i + 1].numVal, a = val
            var r: Double = 0
            var note = ""
            switch o.op ?? .add {
            case .add:
                if o.enh.contains(.amp) { r = a + b * 3; note = "증폭: 오른쪽 ×3" } else { r = a + b }
                if o.enh.contains(.stack) { r += o.bonus; note = "적립 +\(Fmt.n(o.bonus))" }
            case .sub:
                // 역전은 오른쪽 수가 바로 앞 숫자 카드보다 클 때만 발동해요
                if o.enh.contains(.flip) && b > cs[i - 1].numVal { r = abs(a - b) * 4; note = "역전 ×4" } else { r = a - b }
            case .mul:
                r = a * b
            case .div:
                if b == 0 { r = 0 }
                else if o.enh.contains(.exact) && abs(a.truncatingRemainder(dividingBy: b)) < 1e-9 { r = a * b * 2; note = "정확: 곱하고 ×2" }
                else { r = a / b }
            }
            val = r
            let shown = o.enh.contains(.amp) ? "\(Fmt.n(a)) + \(Fmt.n(b))×3" : "\(Fmt.n(a)) \(o.op?.symbol ?? "") \(Fmt.n(b))"
            res.steps.append(("\(shown) = \(Fmt.n(r))", note))
            i += 2
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
        for c in cs where c.enh.contains(.luck) {
            res.hasLuck = true
            if roll {
                if Double.random(in: 0..<1) < CFG.luckChance {
                    val *= 5
                    res.luckHit = true
                    res.fx.append(("행운 ×5!!", .fxGold))
                } else {
                    res.fx.append(("행운은 다음 기회에", .miss))
                }
            }
        }
        res.final = max(0, val.rounded(.down))
        return res
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
        run.fight = f
        freshIDs = []
        previewOverride = nil
    }

    func unselect(_ id: Int) {
        guard !busy, var f = run.fight, let i = f.sel.firstIndex(of: id) else { return }
        f.sel.remove(at: i)
        if let h = f.handCards.firstIndex(where: { $0.cardID == id }) { f.handCards[h].out = false }
        run.fight = f
        freshIDs = []
        previewOverride = nil
    }

    func discard() async {
        guard !busy, let f0 = run.fight, !f0.sel.isEmpty, f0.discLeft > 0 else { return }
        busy = true
        tossing = true
        await wait(400)
        guard var f = run.fight else { return }
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

    private func log(_ text: String, _ style: LogStyle, note: String = "") {
        run.fight?.log.append(LogLine(text: text, note: note, style: style))
    }

    func play() async {
        let cs = selectedCards
        guard !busy, validity(cs).ok, var f = run.fight, f.playsLeft > 0, let node = fightNode else { return }
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
        f.log = []
        run.fight = f
        freshIDs = []
        previewOverride = nil
        finalPop = false

        log(cs.map(\.faceText).joined(separator: " "), .expr)
        for st in res.steps {
            await wait(380)
            log(st.text, .step, note: st.note)
        }
        for fx in res.fx {
            await wait(450)
            log(fx.text, fx.style)
            if fx.style != .miss { shakeCount += 1 }
        }
        await wait(350)

        // 최종 결과 숫자를 세어 올려요
        log("0", .final)
        let frames = 20
        for k in 1...frames {
            let p = Double(k) / Double(frames)
            let e = 1 - pow(1 - p, 3)
            if let last = run.fight?.log.indices.last {
                run.fight?.log[last].text = Fmt.n((res.final * e).rounded(.down))
            }
            await wait(650 / frames)
        }
        finalPop = true
        guard var f2 = run.fight else { return }
        if res.final >= f2.hpMax * 0.4 { shakeCount += 1 }
        f2.score += res.final
        run.bestPlay = max(run.bestPlay, res.final)
        run.fight = f2
        let luckHit = res.luckHit
        updateProfile { p in
            p.stats.maxHit = max(p.stats.maxHit, res.final)
            if luckHit { p.stats.luckProcs += 1 }
        }

        if f2.score >= f2.hpMax {
            let over = f2.score - f2.hpMax
            let rate = run.leftoverRate
            let g1 = (CFG.killGold * run.econ).rounded()
            let g2 = RunState.overkillGold(over, f2.hpMax, node.type)
            let g3 = Double(f2.discLeft) * rate.disc
            let g4 = Double(f2.playsLeft) * rate.play
            let gain = g1 + g2 + g3 + g4
            run.gold += gain
            run.goldTotal += gain
            run.kills += 1
            run.lastGold = GoldBreakdown(g1: g1, g2: g2, g3: g3, g4: g4, gain: gain, over: over, hp: f2.hpMax,
                                         disc: f2.discLeft, plays: f2.playsLeft, ratePlay: rate.play, rateDisc: rate.disc, type: node.type)
            let oneShot = f2.playsLeft == run.plays - 1
            let gold = run.gold
            updateProfile { p in
                p.stats.kills += 1
                if node.type == .elite { p.stats.eliteKills += 1 }
                if node.type == .boss { p.stats.bossKills += 1 }
                if oneShot { p.stats.oneShots += 1 }
                if over >= f2.hpMax * 2 { p.stats.bigOverkills += 1 }
                p.stats.maxGold = max(p.stats.maxGold, gold)
            }
            log("처치 \(Fmt.n(g1)) + 초과 피해 \(Fmt.n(g2)) + 남은 계산 \(Fmt.n(g4)) + 남은 버리기 \(Fmt.n(g3)) = 골드 +\(Fmt.n(gain))", .fxGold)
            showStamp = true
            await wait(1200)
            showStamp = false
            busy = false
            openReward(count: node.type == .elite ? 2 : 1)
        } else if f2.playsLeft == 0 {
            await wait(700)
            busy = false
            gameOver("\(node.name)의 체력이 \(Fmt.n(f2.hpMax - f2.score)) 남았어요")
        } else {
            refill()
            busy = false
            save()
            checkStuck()
        }
    }

    // MARK: 특전

    private func genPerks() -> [Perk] {
        let deck = run.deck
        let enchant: (Enh) -> () -> Perk? = { e in {
            guard let c = deck.filter({ $0.op != .mul && !$0.enh.contains(e) }).randomElement() else { return nil }
            return Perk(kind: .enchant(e), cardID: c.id, title: "\(c.label)에 \(e.name)", desc: e.desc)
        } }
        let opPerk: (Enh) -> () -> Perk? = { e in {
            guard let c = deck.filter({ $0.op == e.op && !$0.enh.contains(where: \.isOpPerk) }).randomElement() else { return nil }
            return Perk(kind: .opPerk(e), cardID: c.id, title: "\(c.label)에 \(e.name)", desc: e.desc)
        } }
        let upNum: () -> Perk? = {
            guard let c = deck.filter({ $0.kind == .num }).randomElement() else { return nil }
            return Perk(kind: .upNum, cardID: c.id, title: "숫자 \(c.faceText)의 n을 \(c.v + 3)으로", desc: "이 카드의 값이 영구히 3 올라요")
        }
        let trPerk: (Transform) -> () -> Perk? = { t in {
            guard let c = deck.filter({ $0.kind == .num && $0.trIndex < t.index }).randomElement() else { return nil }
            let after = t.apply(min(c.v, t.cap))
            let title = c.tr != nil ? "\(c.faceText)을 \(t.text(String(c.v)))로" : "숫자 \(c.v)에 \(t.name)"
            return Perk(kind: .transform(t), cardID: c.id, title: title, desc: "변신하면 이 카드의 계산 값이 \(Fmt.n(after))이 돼요")
        } }
        let hand = run.hand, plays = run.plays, discards = run.discards
        var gens: [() -> Perk?] = [
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
        var out: [Perk] = []
        var used: Set<String> = []
        var guardCount = 0
        while out.count < 3 && guardCount < 100 {
            guardCount += 1
            guard let gen = gens.randomElement(), let o = gen() else { continue }
            let key = o.cardID.map { "c\($0)" } ?? "r\(o.title)"
            if used.contains(key) { continue }
            used.insert(key)
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

    // MARK: 상점

    func buyPrice(_ c: Card) -> Double { (c.baseValue * run.econ).rounded() }

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
            let op = [Op.add, .add, .sub, .div, .div, .mul].randomElement() ?? .add
            var c = mk(.op, op: op)
            if op != .mul {
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
        run.deck[i] = pend
        run.shop?.items.removeAll { $0.id == pend.id }
        run.shop?.msg = "\(old.label)을(를) 버리고 \(pend.label)을(를) 넣었어요."
        run.shop?.pendingID = nil
        updateProfile { $0.stats.cardsBought += 1 }
        collect([pend])
        save()
    }

    func leaveShop() {
        run.shop?.pendingID = nil
        afterNode("상점을 나왔어요.")
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
        return parts.joined(separator: ". ")
    }
}
