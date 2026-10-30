import SwiftUI

/// 한 판 진행 화면 (지도 / 전투 / 상점 + 보상·게임 끝 오버레이)
struct GameView: View {
    let session: GameSession
    let onExit: () -> Void
    @State private var showDeck = false
    @State private var showSound = false
    @State private var showPick = false
    @Environment(\.verticalSizeClass) private var vSize

    var body: some View {
        let run = session.run
        // 가로 화면의 전투는 화면 폭을 다 쓰고 여백을 줄여 한 화면에 들어가게 해요
        let wideFight = vSize == .compact && run.phase == .fight
        ZStack(alignment: .top) {
            PaperBackground()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: wideFight ? 8 : 12) {
                        header(run)
                        switch run.phase {
                        case .map: MapView(session: session)
                        case .fight: FightView(session: session)
                        case .shop: ShopView(session: session)
                        }
                    }
                    .padding(.horizontal, 14)
                    // 가로 화면은 위쪽 안전 영역이 거의 없어서 위 여백을 따로 줘요
                    .padding(.top, wideFight ? 16 : 14)
                    .padding(.bottom, wideFight ? 6 : 14)
                    .frame(maxWidth: wideFight ? 1000 : 520)
                    .frame(maxWidth: .infinity)
                    .id("top")
                }
                .onChange(of: run.phase, initial: true) {
                    scroll(proxy, run: session.run)
                }
                .onChange(of: run.act) { scroll(proxy, run: session.run) }
            }

            if let reward = run.reward {
                RewardOverlay(session: session, reward: reward, showDeck: $showDeck)
            }
            if let over = run.over {
                GameOverOverlay(session: session, info: over, onExit: onExit) {
                    // 게임이 끝나고 새 게임을 시작해도 퍽을 다시 골라요
                    if PerkPickSheet.needed(session.profile) { showPick = true } else { session.newGame() }
                }
            }
            if let intro = session.intro {
                IntroOverlay(intro: intro)
                    .id(intro.id)
                    .zIndex(5)
            }
            ToastStack(toasts: session.toasts)
        }
        .animation(.easeOut(duration: 0.3), value: run.reward?.idx)
        .animation(.easeOut(duration: 0.3), value: run.over == nil)
        .animation(.easeInOut(duration: 0.25), value: session.intro?.id)
        .sheet(isPresented: $showDeck) { DeckSheet(session: session) }
        .sheet(isPresented: $showSound) { SoundSettingsSheet() }
        .sheet(isPresented: $showPick) {
            PerkPickSheet(getProfile: { session.profile },
                          setEquipped: { session.setEquipped($0) },
                          onStart: { session.newGame() })
        }
    }

    /// 지도에서는 갈 수 있는 칸으로, 그 외에는 맨 위로 스크롤해요
    private func scroll(_ proxy: ScrollViewProxy, run: RunState) {
        let landscape = vSize == .compact
        Task {
            try? await Task.sleep(for: .milliseconds(50))
            withAnimation {
                if run.phase == .map, landscape, let cur = run.curID {
                    // 가로 화면은 높이가 좁아서, 방금 지나온 층이 맨 위에 오고 그 아래로 다음 층이 보이게 해요
                    proxy.scrollTo(cur, anchor: UnitPoint(x: 0.5, y: 0.08))
                } else if run.phase == .map, let target = run.map.joined().first(where: { run.reachable($0) }) {
                    proxy.scrollTo(target.id, anchor: .center)
                } else {
                    proxy.scrollTo("top", anchor: .top)
                }
            }
        }
    }

    private func header(_ run: RunState) -> some View {
        HStack(spacing: 8) {
            Button {
                onExit()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            // 계산 연출 중에 나가면 끝나지 않은 작업이 슬롯을 덮어쓸 수 있어 막아요
            .disabled(session.busy && run.over == nil)
            .accessibilityLabel("메인 화면으로 (자동 저장됨)")
            Text("셈판").font(.hand(30)).foregroundStyle(Theme.ink)
            Spacer(minLength: 4)
            Text(run.whereText).font(.footnote).foregroundStyle(Theme.muted)
            HStack(spacing: 3) {
                Text("골드").font(.footnote).foregroundStyle(Theme.muted)
                Text(Fmt.n(run.gold)).font(.hand(22)).foregroundStyle(Theme.text).modifier(Highlight())
            }
            SoundButton { showSound = true }
            Button("덱 보기") { showDeck = true }.buttonStyle(ChipButtonStyle())
        }
        .lineLimit(1)
    }
}

#Preview("전투") {
    let session = GameSession(slot: 2, store: SaveStore())
    if session.run.phase == .map, let first = session.run.map.first?.first {
        session.enterNode(first)
    }
    return GameView(session: session) {}
}

#Preview("가로 보상", traits: .landscapeLeft) {
    let session = GameSession(slot: 2, store: SaveStore())
    session.run.lastGold = GoldBreakdown(g1: 5, g2: 4, g3: 6, g4: 6, gain: 21, over: 12, hp: 60,
                                         disc: 2, plays: 1, ratePlay: 6, rateDisc: 3, type: .mob)
    session.run.reward = RewardState(count: 1, idx: 1, offers: [
        Perk(kind: .handSize, glyph: "손+1", title: "손패 +1장", desc: "한 번에 들고 있는 카드가 늘어요"),
        Perk(kind: .plays, glyph: "계산", title: "계산 기회 +1", desc: "전투마다 한 번 더 계산할 수 있어요"),
        Perk(kind: .discards, glyph: "버림", title: "버리기 +1", desc: "전투마다 한 번 더 버릴 수 있어요")
    ])
    return GameView(session: session) {}
}

#Preview("가로 전투", traits: .landscapeLeft) {
    let session = GameSession(slot: 2, store: SaveStore())
    if session.run.phase == .map, let first = session.run.map.first?.first {
        session.enterNode(first)
    }
    return GameView(session: session) {}
}

/// 업적·도감 알림 배너
struct ToastStack: View {
    let toasts: [Toast]

    var body: some View {
        VStack(spacing: 6) {
            ForEach(toasts) { t in
                HStack(spacing: 10) {
                    Text(t.icon).font(.title2)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(t.title).font(.caption.weight(.semibold)).foregroundStyle(Theme.red)
                        Text(t.subtitle).font(.hand(18)).foregroundStyle(Theme.ink)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .frame(maxWidth: 360)
                .background(Theme.card, in: .rect(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.ink, lineWidth: 2))
                .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .animation(.spring(duration: 0.35), value: toasts)
        .allowsHitTesting(false)
    }
}
