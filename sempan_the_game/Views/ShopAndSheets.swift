import SwiftUI

// MARK: - 상점

struct ShopView: View {
    let session: GameSession

    var body: some View {
        if let shop = session.run.shop {
            VStack(alignment: .leading, spacing: 12) {
                Text("상점").font(.hand(28)).foregroundStyle(Theme.ink)
                let coupon = session.run.perkReady(.coupon)
                Text(shop.msg + (coupon ? " 🎟️ 할인권: 이번 막 첫 구매가 30% 싸요." : "")).font(.subheadline).foregroundStyle(Theme.muted)
                if session.run.hasPerk(.restock) {
                    // 재입고 퍽: 막마다 한 번 무료로 새 물건
                    let ready = session.run.perkReady(.restock)
                    Button("🔄 재입고 \(ready ? "(무료, 이번 막 1번)" : "(이번 막에 씀)")") { session.restock() }
                        .buttonStyle(ChipButtonStyle())
                        .disabled(!ready)
                        .opacity(ready ? 1 : 0.4)
                }
                Text("사기").font(.footnote.weight(.semibold)).foregroundStyle(Theme.muted)
                if shop.items.isEmpty {
                    Text("다 팔렸어요.").font(.subheadline).foregroundStyle(Theme.muted)
                }
                ForEach(shop.items) { c in item(c, pending: shop.pendingID == c.id) }
                if let pend = session.pendingItem { swapArea(pend) }
                Button("상점 나가기") { session.leaveShop() }
                    .buttonStyle(MainButtonStyle())
            }
        }
    }

    private func item(_ c: Card, pending: Bool) -> some View {
        let price = session.buyPrice(c)
        let extras = ([c.tr.map { "\($0.name) 변신 (계산 값 \(Fmt.n(c.numVal)))" }] + c.enh.map { "\($0.name): \($0.desc)" })
            .compactMap { $0 }
            .joined(separator: " / ")
        return HStack(spacing: 12) {
            CardView(card: c, fireBonus: session.run.fireBonus, fontSize: 26, badgeSize: 7, shadow: false)
                .frame(width: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text(c.label).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                Text(extras.isEmpty ? (c.op == .mul ? "강화할 수 없는 곱셈 카드" : c.op == .pow ? "거듭제곱 카드 (지수는 \(Int(CFG.powCap))까지)" : "강화 없는 기본 카드") : extras)
                    .font(.caption).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)
            Button(pending ? "고르는 중" : "\(Fmt.n(price)) 골드\(session.run.perkReady(.coupon) ? " 🎟️" : "")") { session.togglePending(c) }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.paper)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(Theme.ink, in: .rect(cornerRadius: 8))
                .buttonStyle(.plain)
                .disabled(session.run.gold < price)
                .opacity(session.run.gold < price ? 0.35 : 1)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(Theme.card, in: .rect(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(pending ? Theme.red : Theme.edge, lineWidth: 2))
    }

    private func swapArea(_ pend: Card) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(pend.label)(\(Fmt.n(session.buyPrice(pend))) 골드)와 바꿀 \(pend.kind == .num ? "숫자" : "기호") 카드를 고르세요")
                .font(.footnote.weight(.semibold)).foregroundStyle(Theme.muted)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 48), spacing: 6)], spacing: 6) {
                ForEach(session.sortedDeck.filter { $0.kind == pend.kind }) { c in
                    Button { session.swap(with: c) } label: {
                        CardView(card: c, fireBonus: session.run.fireBonus, fontSize: 24, badgeSize: 7)
                    }
                    .buttonStyle(.plain)
                }
            }
            Button("교환 취소") { session.cancelSwap() }
                .buttonStyle(MainButtonStyle(filled: false))
        }
    }
}

// MARK: - 처치 보상 (특전 고르기)

struct RewardOverlay: View {
    let session: GameSession
    let reward: RewardState
    @Binding var showDeck: Bool
    @Environment(\.verticalSizeClass) private var vSize

    var body: some View {
        // 가로 화면: 왼쪽은 결과(골드 내역), 오른쪽은 특전 3개
        if vSize == .compact {
            OverlaySheet(maxWidth: 820) {
                HStack(alignment: .top, spacing: 16) {
                    summary
                        .frame(maxWidth: .infinity)
                    VStack(spacing: 10) {
                        ForEach(reward.offers) { o in offer(o) }
                        rerollButton
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        } else {
            OverlaySheet {
                VStack(alignment: .leading, spacing: 12) {
                    summary
                    ForEach(reward.offers) { o in offer(o) }
                    rerollButton
                }
            }
        }
    }

    /// 다시 뽑기 퍽: 막마다 한 번 선택지를 새로
    @ViewBuilder
    private var rerollButton: some View {
        if session.run.hasPerk(.reroll) {
            let ready = session.run.perkReady(.reroll)
            Button("🎲 다시 뽑기 \(ready ? "(이번 막 1번)" : "(이번 막에 씀)")") { session.rerollPerks() }
                .buttonStyle(ChipButtonStyle())
                .disabled(!ready)
                .opacity(ready ? 1 : 0.4)
        }
    }

    /// 제목, 골드 내역, 안내 문구
    private var summary: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(reward.count > 1 ? "특전 \(reward.idx)/\(reward.count)" : "처치")
                    .font(.hand(32)).foregroundStyle(Theme.red)
                Spacer()
                Button("덱 보기") { showDeck = true }.buttonStyle(ChipButtonStyle())
            }
            if reward.idx == 1, let g = session.run.lastGold {
                breakdown(g)
                Text("특전 하나를 고르세요.").font(.subheadline).foregroundStyle(Theme.muted)
            } else {
                Text("하나 더 고르세요.").font(.subheadline).foregroundStyle(Theme.muted)
            }
        }
    }

    private func breakdown(_ g: GoldBreakdown) -> some View {
        let pct = Int((g.over / g.hp * 100).rounded())
        return VStack(spacing: 3) {
            row("처치 보상", g.g1)
            row("초과 피해 \(Fmt.n(g.over)) (체력의 \(pct)%, 상한 \(Fmt.n(RunState.overkillCap(g.hp, g.type).rounded())))", g.g2)
            row("남은 계산 \(g.plays)번 × \(Fmt.n(g.ratePlay))", g.g4)
            row("남은 버리기 \(g.disc)번 × \(Fmt.n(g.rateDisc))", g.g3)
            Divider().overlay(Theme.edge)
            HStack {
                Text("합계").font(.footnote.weight(.semibold))
                Spacer()
                Text("+\(Fmt.n(g.gain))").font(.hand(22)).foregroundStyle(Theme.red)
            }
        }
        .foregroundStyle(Theme.text)
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(Theme.card, in: .rect(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.edge, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
    }

    private func row(_ title: String, _ value: Double) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.caption)
            Spacer()
            Text(Fmt.n(value)).font(.hand(18)).foregroundStyle(Theme.ink)
        }
    }

    private func offer(_ o: Perk) -> some View {
        Button { session.choose(o) } label: {
            HStack(spacing: 12) {
                Group {
                    if let id = o.cardID, let c = session.run.card(id) {
                        CardView(card: c, fireBonus: session.run.fireBonus, fontSize: 26, badgeSize: 7, shadow: false)
                    } else {
                        Text(o.glyph)
                            .font(.hand(17))
                            .foregroundStyle(Theme.red)
                            .frame(width: 56, height: 56)
                            .overlay(Circle().stroke(Theme.red, lineWidth: 2))
                            .rotationEffect(.degrees(-8))
                    }
                }
                .frame(width: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(o.title).font(.body.weight(.semibold)).foregroundStyle(Theme.ink)
                    Text(o.desc).font(.footnote).foregroundStyle(Theme.muted)
                }
                .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(Theme.card, in: .rect(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.edge, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 덱 보기

struct DeckSheet: View {
    let session: GameSession
    @Environment(\.dismiss) private var dismiss
    @State private var info = "카드를 누르면 설명이 보여요."

    var body: some View {
        let run = session.run
        let deck = session.sortedDeck
        let nums = deck.filter { $0.kind == .num }
        let ops = deck.filter { $0.kind == .op }
        let inFight = run.phase == .fight && run.reward == nil
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("내 덱").font(.hand(32)).foregroundStyle(Theme.red)
                    Spacer()
                    Button("닫기") { dismiss() }.buttonStyle(ChipButtonStyle())
                }
                Group {
                    if inFight, let f = run.fight {
                        Text("이번 전투에서 뽑을 카드: 숫자 \(f.numDraw.count)장, 기호 \(f.opDraw.count)장 / 덱 \(run.deck.count)장. 회색은 손패에 있거나 이미 쓴 카드예요.")
                    } else {
                        Text("손패 \(run.hand)장, 계산 \(run.plays)번, 버리기 \(run.discards)번 / 덱 \(run.deck.count)장")
                    }
                }
                .font(.subheadline).foregroundStyle(Theme.muted)
                perkList(run)
                // 전투 중에는 버리기로 새로 나올 수 있는 카드만 원래 색이에요 (뽑을 덱이 비면 버린 더미를 섞어 다시 써요)
                let drawable: Set<Int>? = inFight ? run.fight.map { f in
                    Set(f.numDraw.count + f.opDraw.count > 0 ? f.numDraw + f.opDraw : f.numPile + f.opPile)
                } : nil
                grid("숫자 덱 \(nums.count)장", nums, drawable: drawable)
                grid("기호 덱 \(ops.count)장", ops, drawable: drawable)
                Text(info)
                    .font(.footnote)
                    .foregroundStyle(Theme.text)
                    .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(Theme.card, in: .rect(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.edge, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
                legend(run)
            }
            .padding(18)
        }
        .background(PaperBackground())
        .presentationDetents([.large])
    }

    private func grid(_ title: String, _ cards: [Card], drawable: Set<Int>?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.footnote.weight(.semibold)).foregroundStyle(Theme.muted)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 48), spacing: 6)], spacing: 6) {
                ForEach(cards) { c in
                    let dim = drawable.map { !$0.contains(c.id) } ?? false
                    Button { info = session.describe(c) } label: {
                        CardView(card: c, fireBonus: session.run.fireBonus, fontSize: 24, badgeSize: 7)
                            .grayscale(dim ? 1 : 0)
                            .opacity(dim ? 0.32 : 1)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func perkList(_ run: RunState) -> some View {
        let perks = (run.perks ?? []).compactMap(MetaPerk.init(rawValue:))
        if !perks.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("장착한 퍽").font(.footnote.weight(.semibold)).foregroundStyle(Theme.muted)
                ForEach(perks) { k in
                    Text("\(Text("\(k.icon) \(k.name)").bold().foregroundStyle(Theme.ink))  \(k.desc)\(k.oncePerAct ? (run.perkReady(k) ? " (이번 막에 아직 안 씀)" : " (이번 막에 씀)") : "")")
                        .font(.caption).foregroundStyle(Theme.muted)
                }
            }
        }
    }

    private func legend(_ run: RunState) -> some View {
        let r = run.leftoverRate, e = run.econ
        return VStack(alignment: .leading, spacing: 5) {
            ForEach(Enh.allCases, id: \.self) { x in
                Text("\(Text(x.badge).bold().foregroundStyle(x.isOpPerk ? Theme.red : Theme.ink))  \(x.name)\(x.op.map { " (\($0.symbol) 카드)" } ?? ""): \(x.desc)")
            }
            ForEach(Transform.allCases, id: \.self) { t in
                Text("\(Text(t.text("n")).bold().foregroundStyle(Theme.ink))  \(t.name) 변신 (\(t.act)막부터\(run.act >= t.act ? ", 해금됨" : "")): 숫자 n을 \(t.text("n"))으로 계산해요. n은 \(t.cap)까지만 적용돼요")
            }
            Text("× 카드는 강력한 대신 강화할 수 없어요.")
            Text("\(Text("^").bold().foregroundStyle(Theme.red))  거듭제곱 카드 (6막부터 × 카드가 진화): 지수는 \(Int(CFG.powCap))까지예요.")
            if run.isLog {
                Text("로그 단계: 체력은 10의 거듭제곱이고, 계산 결과의 자릿수(log₁₀)에 강화 효과가 붙어 피해가 돼요.")
            }
            Text("골드(지금 층 기준): 처치 \(Fmt.n((CFG.killGold * e).rounded())) + 초과 피해 골드(일반 몹 기준 최대 \(Fmt.n((CFG.goldCap * e).rounded()))) + 남은 계산당 \(Fmt.n(r.play)) + 남은 버리기당 \(Fmt.n(r.disc)). 지금 물가 \(Fmt.n(e))배.")
        }
        .font(.caption)
        .foregroundStyle(Theme.muted)
    }
}

// MARK: - 게임 끝

struct GameOverOverlay: View {
    let session: GameSession
    let info: GameOverInfo
    let onExit: () -> Void

    var body: some View {
        let run = session.run
        let p = session.profile
        OverlaySheet {
            VStack(alignment: .leading, spacing: 12) {
                Text("여기까지").font(.hand(32)).foregroundStyle(Theme.red)
                Text(info.reason).font(.subheadline).foregroundStyle(Theme.muted)
                if info.newRecord {
                    Text("새 기록!").font(.hand(22)).foregroundStyle(Theme.red)
                }
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                    stat("도달 위치", "\(run.act)막 \(run.floor)층")
                    stat("처치한 몹", "\(run.kills)")
                    stat("최고 한 방", Fmt.n(run.bestPlay))
                    stat("모은 골드", Fmt.n(run.goldTotal))
                    stat("역대 기록", "\(p.bestDepth)층, 한 방 \(Fmt.n(p.bestSingle))")
                }
                Button("새 게임 시작") { session.newGame() }
                    .buttonStyle(MainButtonStyle())
                Button("메인 화면으로") { onExit() }
                    .buttonStyle(MainButtonStyle(filled: false))
            }
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title).foregroundStyle(Theme.muted)
            Text(value).font(.hand(22)).foregroundStyle(Theme.ink)
        }
    }
}
