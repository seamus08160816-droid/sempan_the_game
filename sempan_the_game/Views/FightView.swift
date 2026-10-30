import SwiftUI

/// 전투 화면: 숫자와 기호를 번갈아 놓아 수식을 만들어요
struct FightView: View {
    let session: GameSession
    /// 손패 ↔ 수식 칸 사이를 카드가 날아가게 이어 줘요
    @Namespace private var cardSpace
    /// 날아가는 카드가 가려지지 않게, 마지막으로 카드가 향한 쪽을 위에 그려요
    @State private var handOnTop = false
    @Environment(\.verticalSizeClass) private var vSize

    /// 가로 화면(높이가 좁을 때)에는 정보를 왼쪽에 모으고 한 화면에 들어가게 압축해요
    private var wide: Bool { vSize == .compact }

    var body: some View {
        if let f = session.run.fight, let node = session.fightNode {
            if wide {
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 12) {
                        status(f, node: node)
                        actions(f)
                    }
                    .frame(width: 200)
                    VStack(spacing: 8) {
                        board(f)
                            .zIndex(handOnTop ? 0 : 1)
                        hand
                            .zIndex(handOnTop ? 1 : 0)
                    }
                }
            } else {
                portrait(f, node: node)
            }
        }
    }

    private var hand: some View {
        FanHand(session: session, cardSpace: cardSpace, maxCardWidth: wide ? 60 : 80) { id in
            handOnTop = false
            withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) { session.select(id) }
        }
    }

    private func portrait(_ f: FightState, node: MapNode) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            status(f, node: node)
            board(f)
                .zIndex(handOnTop ? 0 : 1)
            hand
                .zIndex(handOnTop ? 1 : 0)
            actions(f)
            RulesBox(lines: [
                "손패를 손가락으로 훑으면 카드가 커져요. 손을 떼면 그 카드를 수식 칸에 놓아요. 아래로 끌어내리면 취소돼요.",
                "숫자 3장과 기호 2장까지 번갈아 놓아 수식을 만들어요. 왼쪽부터 순서대로 계산하고, 결과가 음수면 0이에요.",
                "계산 결과만큼 몹에게 피해를 줘요. 계산 기회 안에 체력을 0으로 만들면 이겨요. 남은 계산과 버리기는 골드로 바뀌니 빨리 끝낼수록 이득이에요.",
                "버리기는 수식 칸에 올린 카드를 버리고 새로 뽑아요. 카드는 숫자 덱과 기호 덱을 합친 곳에서 무작위로 뽑혀요."
            ])
        }
    }

    // MARK: 상태

    private func status(_ f: FightState, node: MapNode) -> some View {
        let left = max(0, f.hpMax - f.score)
        let title = HStack(alignment: .firstTextBaseline) {
            Text(node.name).font(.hand(26)).foregroundStyle(Theme.ink)
            if node.type != .mob {
                Text(node.type.name)
                    .font(.hand(16))
                    .foregroundStyle(Theme.red)
                    .padding(.horizontal, 6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.red, lineWidth: 2))
                    .rotationEffect(.degrees(-6))
            }
        }
        let hp = Text("체력 \(Text("\(Fmt.n(left)) / \(Fmt.n(f.hpMax))").font(.hand(22)).foregroundStyle(Theme.red))")
            .font(.subheadline)
            .foregroundStyle(Theme.muted)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        // 가로 화면의 좁은 왼쪽 칸에서는 이름·체력과 덱 정보를 세로로 쌓아요
        let metaLayout = wide ? AnyLayout(VStackLayout(alignment: .leading, spacing: 3)) : AnyLayout(HStackLayout(spacing: 12))
        return VStack(alignment: .leading, spacing: 6) {
            if wide {
                title
                hp
            } else {
                HStack(alignment: .firstTextBaseline) {
                    title
                    Spacer()
                    hp
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Theme.card
                    Theme.red.opacity(0.85)
                        .frame(width: geo.size.width * max(0, min(1, left / f.hpMax)))
                        .animation(.spring(duration: 0.6), value: left)
                }
            }
            .frame(height: 16)
            .clipShape(.rect(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.ink, lineWidth: 2))
            metaLayout {
                meta("계산", "\(f.playsLeft)번")
                meta("버리기", "\(f.discLeft)번")
                meta("숫자 덱", "\(f.numDraw.count)장")
                meta("기호 덱", "\(f.opDraw.count)장")
            }
            .font(.caption)
            .foregroundStyle(Theme.muted)
        }
    }

    private func meta(_ title: String, _ value: String) -> some View {
        Text("\(title) \(Text(value).bold().foregroundStyle(Theme.text))")
    }

    // MARK: 수식판

    private func board(_ f: FightState) -> some View {
        let sel = session.selectedCards
        return Group {
            if wide {
                // 가로: 수식 칸은 작게 고정하고, 미리보기와 기록은 오른쪽에 둬요
                HStack(alignment: .top, spacing: 10) {
                    slots(sel)
                        .frame(width: CGFloat(CFG.maxLen) * 48 + CGFloat(CFG.maxLen - 1) * 6)
                    VStack(alignment: .leading, spacing: 4) {
                        preview(sel)
                        logView(f)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    slots(sel)
                    preview(sel)
                    logView(f)
                }
            }
        }
        .padding(10)
        .background(Theme.card, in: .rect(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.ink, lineWidth: 2))
        .overlay(alignment: .trailing) {
            if session.showStamp {
                Text("처치")
                    .font(.hand(40))
                    .foregroundStyle(Theme.red)
                    .padding(.horizontal, 14)
                    .background(Theme.card, in: .rect(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.red, lineWidth: 4))
                    .rotationEffect(.degrees(-12))
                    .padding(.trailing, 14)
                    .transition(.scale(scale: 2.2).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.35), value: session.showStamp)
        .modifier(ShakeEffect(animatableData: CGFloat(session.shakeCount)))
        .animation(.linear(duration: 0.4), value: session.shakeCount)
    }

    private func slots(_ sel: [Card]) -> some View {
        HStack(spacing: 6) {
            ForEach(0..<CFG.maxLen, id: \.self) { i in
                if i < sel.count {
                    let c = sel[i]
                    Button {
                        handOnTop = true
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) { session.unselect(c.id) }
                    } label: {
                        CardView(card: c, fireBonus: session.run.fireBonus, fontSize: 26, badgeSize: 7)
                    }
                    .buttonStyle(.plain)
                    .matchedGeometryEffect(id: c.id, in: cardSpace)
                    .modifier(TossEffect(active: session.tossing, index: i))
                    // 손패에서 들려 커진 크기(1.28배)에서 출발해 제자리 크기로 줄어들어요
                    .transition(.asymmetric(insertion: .scale(scale: 1.28, anchor: UnitPoint(x: 0.5, y: 0.7)), removal: .opacity))
                } else {
                    GhostCard(label: i % 2 == 0 ? "숫자" : "기호")
                }
            }
        }
    }

    private func preview(_ sel: [Card]) -> some View {
        let v = session.validity(sel)
        return Group {
            if let msg = session.previewOverride {
                Text(msg).font(.subheadline).foregroundStyle(Theme.muted)
            } else if v.ok {
                let r = session.evaluate(sel, roll: false)
                Text("= \(Fmt.n(r.final))\(r.hasLuck ? "  (행운 미포함)" : "")")
                    .font(.hand(22)).foregroundStyle(Theme.ink)
            } else if !session.busy && !(wide && sel.isEmpty) {
                // 가로 화면에서는 빈 수식 칸 안내("손패를 누르거나…")를 생략해요
                Text(v.msg).font(.subheadline).foregroundStyle(Theme.muted)
            } else {
                Text(" ").font(.subheadline)
            }
        }
        .frame(minHeight: 26, alignment: .leading)
    }

    private func logView(_ f: FightState) -> some View {
        // 가로 화면에서는 전투 시작 안내(info) 줄을 빼고 기록 칸도 낮춰요
        let lines = wide ? f.log.filter { $0.style != .info } : f.log
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(lines) { line in
                        logLine(line).id(line.id)
                            .transition(.opacity.combined(with: .offset(y: 4)))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.easeOut(duration: 0.25), value: f.log.count)
            }
            .frame(height: wide ? 72 : 180)
            // 줄이 늘어나면 맨 아래(최신 줄)를 계속 보여줘요
            .defaultScrollAnchor(.bottom, for: .sizeChanges)
            // 글자만 보면 "황금 ×2"처럼 같은 줄이 연달아 붙을 때 놓치므로, 줄 전체(id 포함)가 바뀔 때마다 내려요
            .onChange(of: f.log.last) {
                if let last = f.log.last {
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
        .padding(.top, 6)
        .overlay(alignment: .top) {
            Line().stroke(Theme.edge, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])).frame(height: 1)
        }
    }

    @ViewBuilder
    private func logLine(_ line: LogLine) -> some View {
        switch line.style {
        case .info:
            Text(line.text).font(.subheadline).foregroundStyle(Theme.muted)
        case .expr:
            Text(line.text).font(.hand(21)).foregroundStyle(Theme.ink)
        case .step:
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(line.text).font(.hand(20, weight: .regular)).foregroundStyle(Theme.text)
                if !line.note.isEmpty { Text(line.note).font(.caption).foregroundStyle(Theme.red) }
            }
        case .fx:
            Text(line.text).font(.hand(24)).foregroundStyle(Theme.red)
        case .fxGold:
            Text(line.text).font(.hand(20)).foregroundStyle(Theme.text).modifier(Highlight())
        case .miss:
            Text(line.text).font(.hand(19, weight: .regular)).foregroundStyle(Theme.muted)
        case .final:
            Text(line.text)
                .font(.hand(54))
                .foregroundStyle(Theme.red)
                .scaleEffect(session.finalPop && line.id == session.run.fight?.log.last(where: { $0.style == .final })?.id ? 1 : 0.9)
                .animation(.spring(response: 0.3, dampingFraction: 0.4), value: session.finalPop)
        }
    }

    private func actions(_ f: FightState) -> some View {
        let canPlay = !session.busy && session.validity(session.selectedCards).ok && f.playsLeft > 0
        let canDiscard = !session.busy && !f.sel.isEmpty && f.discLeft > 0
        let discard = Button { Task { await session.discard() } } label: {
            actionLabel("버리기", total: session.run.discards, left: f.discLeft)
        }
        .buttonStyle(MainButtonStyle(filled: false))
        .disabled(!canDiscard)
        .accessibilityLabel("버리기, \(f.discLeft)번 남음")
        let play = Button { Task { await session.play() } } label: {
            actionLabel("계산하기", total: session.run.plays, left: f.playsLeft)
        }
        .buttonStyle(MainButtonStyle())
        .disabled(!canPlay)
        .accessibilityLabel("계산하기, \(f.playsLeft)번 남음")
        return Group {
            if wide {
                // 가로: 왼쪽 칸 아래에 세로로 쌓아요
                VStack(spacing: 8) {
                    play
                    discard
                }
            } else {
                HStack(spacing: 10) {
                    discard
                        .containerRelativeFrame(.horizontal, count: 13, span: 5, spacing: 10)
                    play
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .lineLimit(1)
    }
}

extension FightView {
    /// 버튼 이름 옆에 남은 횟수를 낙서 세로선으로 그어요
    fileprivate func actionLabel(_ title: String, total: Int, left: Int) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.hand(22))
            TallyMarks(total: max(total, left), left: left)
        }
    }
}

/// 노트에 펜으로 긋듯 삐뚤빼뚤한 세로선으로 횟수를 보여줘요. 쓴 만큼 오른쪽부터 회색으로 바뀌어요
struct TallyMarks: View {
    let total: Int
    let left: Int
    var height: CGFloat = 18

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<total, id: \.self) { i in
                ScribbleStroke(seed: i)
                    .stroke(i < left ? AnyShapeStyle(.foreground) : AnyShapeStyle(Color.gray.opacity(0.55)),
                            style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
                    .frame(width: 5, height: height)
            }
        }
        .animation(.easeOut(duration: 0.3), value: left)
        .accessibilityHidden(true)
    }
}

/// 손으로 그은 듯 살짝 기울고 휜 세로선 한 획 (seed마다 모양이 달라요)
struct ScribbleStroke: Shape {
    let seed: Int

    func path(in r: CGRect) -> Path {
        // seed로 정해지는 -0.5...0.5 사이의 흔들림 값 (매번 같은 모양이 나오게)
        func jitter(_ k: Double) -> CGFloat {
            let v = sin(Double(seed + 1) * 12.9898 + k * 78.233) * 43758.5453
            return CGFloat(v - v.rounded(.down)) - 0.5
        }
        // 위아래 끝을 조금씩 비껴 기울이고, 가운데는 아주 살짝만 휘게 해요 (괄호처럼 보이지 않게)
        let top = CGPoint(x: r.midX + jitter(1) * r.width * 0.9, y: r.minY + abs(jitter(2)) * r.height * 0.15)
        let bottom = CGPoint(x: r.midX + jitter(3) * r.width * 0.9, y: r.maxY - abs(jitter(4)) * r.height * 0.15)
        let mid = CGPoint(x: (top.x + bottom.x) / 2 + jitter(5) * r.width * 0.35, y: r.midY + jitter(6) * r.height * 0.2)
        var p = Path()
        p.move(to: top)
        p.addQuadCurve(to: bottom, control: mid)
        return p
    }
}

/// 수평선
struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.minX, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        }
    }
}

#Preview("부채꼴 손패", traits: .fixedLayout(width: 390, height: 900)) {
    let session = GameSession(slot: 2, store: SaveStore())
    if session.run.phase == .map, let first = session.run.map.first?.first {
        session.enterNode(first)
    }
    session.freshIDs = []
    return FightView(session: session)
        .padding(14)
        .background(PaperBackground())
}

// MARK: - 부채꼴 손패

/// 카드 한 장의 부채꼴 배치
struct FanPose: Equatable {
    var tx: CGFloat
    var ty: CGFloat
    var rot: Double
    var scale: CGFloat
    var z: Double
}

/// 숫자·기호를 섞어 부채꼴로 쥔 손패.
/// 터치: 손가락으로 훑으면 손가락 아래 카드가 들려 커지고, 손을 떼면 그 카드를 내요.
/// 손패 아래로 끌어내린 뒤 떼면 취소돼요. 마우스·트랙패드에서는 올려 두기만 해도 커져요.
struct FanHand: View {
    let session: GameSession
    let cardSpace: Namespace.ID
    /// 손패 카드의 최대 너비 (가로 화면에서는 높이를 아끼려고 줄여요)
    var maxCardWidth: CGFloat = 80
    let onSelect: (Int) -> Void

    @State private var width: CGFloat = 340
    @State private var focusID: Int?
    @State private var touching = false

    private var cw: CGFloat { min(maxCardWidth, max(56, width * 0.17)).rounded() }
    private var height: CGFloat { cw * 4 / 3 + 64 }

    private var visible: [Card] {
        (session.run.fight?.handCards ?? []).filter { !$0.out }.compactMap { session.run.card($0.cardID) }
    }

    private var spacing: CGFloat {
        min(cw * 0.9, (width - cw - 6) / CGFloat(max(1, visible.count - 1)))
    }

    var body: some View {
        let cards = visible
        let poses = layout(cards)
        let freshOrder = cards.filter { session.freshIDs.contains($0.id) }.map(\.id)
        ZStack(alignment: .topLeading) {
            if cards.isEmpty {
                Text("손패가 비었어요")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            ForEach(Array(cards.enumerated()), id: \.element.id) { i, c in
                let p = poses[i]
                CardView(card: c, fireBonus: session.run.fireBonus, fontSize: cw * 0.42, badgeSize: 8, faceCorner: true)
                    .frame(width: cw)
                    // 그림자를 카드 안의 글자·배지마다 따로 그리지 않고 카드 한 장에 한 번만 그려요
                    .compositingGroup()
                    .shadow(color: .black.opacity(0.1), radius: 7, y: 6)
                    .matchedGeometryEffect(id: c.id, in: cardSpace)
                    .modifier(DealEffect(fresh: session.freshIDs.contains(c.id), order: freshOrder.firstIndex(of: c.id) ?? 0))
                    .scaleEffect(p.scale, anchor: UnitPoint(x: 0.5, y: 0.7))
                    .rotationEffect(.degrees(p.rot), anchor: UnitPoint(x: 0.5, y: 0.7))
                    .position(x: width / 2 + p.tx, y: cw * 2 / 3 + p.ty)
                    .zIndex(p.z)
                    .animation(.spring(response: 0.24, dampingFraction: 0.8), value: p)
                    // 수식 칸으로 올라갈 때는 손패 쪽 복사본을 바로 숨겨, 한 장만 날아가게 해요
                    .transition(.asymmetric(insertion: .opacity, removal: .identity))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(session.describe(c))
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { onSelect(c.id) }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .contentShape(Rectangle())
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .gesture(scrub(cards))
        .onContinuousHover { phase in
            guard !touching else { return }
            switch phase {
            case .active(let loc): focusID = session.busy ? nil : card(at: loc.x, in: cards)
            case .ended: focusID = nil
            }
        }
        .sensoryFeedback(.selection, trigger: focusID) { _, new in new != nil }
        .padding(.top, 6)
    }

    /// 누른 채로 훑기 → 뗄 때 선택. 짧게 탭해도 같은 방식으로 선택돼요
    private func scrub(_ cards: [Card]) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                guard !session.busy else { return }
                if !touching { touching = true }
                // 손패 아래로 끌어내리면 들었던 카드를 내려놓아요 (취소)
                // 값이 바뀔 때만 써서, 손가락이 같은 카드 위에 있는 동안은 손패를 다시 그리지 않아요
                let next = v.location.y > height + 24 ? nil : card(at: v.location.x, in: cards)
                if next != focusID { focusID = next }
            }
            .onEnded { _ in
                let picked = focusID
                touching = false
                focusID = nil
                if let picked, !session.busy { onSelect(picked) }
            }
    }

    /// 손가락 x 위치에서 가장 가까운 카드 (겹친 부채꼴에서도 흔들리지 않게 펼친 간격 기준으로 골라요)
    private func card(at x: CGFloat, in cards: [Card]) -> Int? {
        guard !cards.isEmpty else { return nil }
        let mid = CGFloat(cards.count - 1) / 2
        let i = Int(((x - width / 2) / spacing + mid).rounded())
        return cards[min(cards.count - 1, max(0, i))].id
    }

    private func layout(_ cards: [Card]) -> [FanPose] {
        let n = cards.count
        guard n > 0 else { return [] }
        let mid = CGFloat(n - 1) / 2
        let hi = cards.firstIndex { $0.id == focusID }
        let push = spacing < cw ? min(cw * 0.38, cw - spacing) : 0
        // 터치 중에는 손가락에 가리지 않게 더 높이 들어 올려요
        let lift = touching ? cw * 0.45 : 8
        return (0..<n).map { i in
            let d = CGFloat(i) - mid
            var pose = FanPose(tx: d * spacing, ty: d * d * 2.4 + 22, rot: Double(d) * min(5, 34 / Double(n)), scale: 1, z: Double(10 + i))
            if let hi {
                if i == hi {
                    pose.ty = -lift
                    pose.rot = 0
                    pose.scale = 1.28
                    pose.z = 60
                } else {
                    pose.tx += (i < hi ? -1 : 1) * push
                }
            }
            return pose
        }
    }
}

/// 새로 뽑힌 카드가 왼쪽 위에서 차례로 날아와요
struct DealEffect: ViewModifier {
    let fresh: Bool
    let order: Int
    @State private var shown = false

    func body(content: Content) -> some View {
        let hidden = fresh && !shown
        content
            .offset(x: hidden ? -40 : 0, y: hidden ? -280 : 0)
            .rotationEffect(.degrees(hidden ? -25 : 0))
            .scaleEffect(hidden ? 0.7 : 1)
            .opacity(hidden ? 0 : 1)
            .onAppear {
                guard fresh else { shown = true; return }
                withAnimation(.spring(response: 0.42, dampingFraction: 0.72).delay(Double(order) * 0.07)) {
                    shown = true
                }
            }
    }
}

/// 버린 카드가 날아가요
struct TossEffect: ViewModifier {
    let active: Bool
    let index: Int

    func body(content: Content) -> some View {
        content
            .offset(x: active ? 40 : 0, y: active ? -90 : 0)
            .rotationEffect(.degrees(active ? 18 : 0))
            .scaleEffect(active ? 0.8 : 1)
            .opacity(active ? 0 : 1)
            .animation(.easeIn(duration: 0.35).delay(Double(index) * 0.04), value: active)
    }
}
