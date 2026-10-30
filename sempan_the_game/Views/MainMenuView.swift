import SwiftUI

/// 메인 화면: 저장 슬롯 선택, 시작하기, 업적, 카드 도감
struct MainMenuView: View {
    let store: SaveStore
    let onStart: (_ slot: Int, _ fresh: Bool) -> Void

    @AppStorage("selectedSlot") private var selected = 0
    @State private var confirmNewGame = false
    @State private var confirmDelete: Int?
    @State private var showAchievements = false
    @State private var showCollection = false

    private var profile: SlotProfile { store.profile(selected) }

    var body: some View {
        ZStack {
            PaperBackground()
            ScrollView {
                VStack(spacing: 18) {
                    title
                    slots
                    startButtons
                    progressButtons
                }
                .padding(20)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .confirmationDialog("슬롯 \(selected + 1)에 진행 중인 게임이 있어요", isPresented: $confirmNewGame, titleVisibility: .visible) {
            Button("새 게임 시작 (진행 중인 판은 사라져요)", role: .destructive) { onStart(selected, true) }
            Button("취소", role: .cancel) {}
        }
        .alert("슬롯 \((confirmDelete ?? 0) + 1)을 지울까요?", isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } })) {
            Button("지우기", role: .destructive) {
                if let i = confirmDelete { store.delete(i) }
                confirmDelete = nil
            }
            Button("취소", role: .cancel) { confirmDelete = nil }
        } message: {
            Text("진행 중인 게임, 기록, 업적, 카드 도감이 모두 지워져요.")
        }
        .sheet(isPresented: $showAchievements) { AchievementsView(profile: profile, slot: selected) }
        .sheet(isPresented: $showCollection) { CollectionView(profile: profile, slot: selected) }
    }

    private var title: some View {
        VStack(spacing: 6) {
            Text("셈판")
                .font(.hand(72))
                .foregroundStyle(Theme.ink)
                .padding(.top, 30)
            Text("숫자와 기호로 수식을 만들어 몹을 쓰러뜨리는 카드 로그라이크")
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
            HStack(spacing: 6) {
                ForEach([Card.number(-1, 7), .symbol(-2, .mul), .number(-3, 3)]) { c in
                    CardView(card: c, fontSize: 26, shadow: true).frame(width: 44)
                }
                Text("= 21").font(.hand(30)).foregroundStyle(Theme.red)
            }
            .padding(.top, 8)
            .accessibilityHidden(true)
        }
    }

    // MARK: 저장 슬롯

    private var slots: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("저장 슬롯").font(.footnote.weight(.semibold)).foregroundStyle(Theme.muted)
            ForEach(0..<SaveStore.slotCount, id: \.self) { i in
                slotRow(i)
            }
        }
    }

    private func slotRow(_ i: Int) -> some View {
        let p = store.slots[i]
        let isSelected = selected == i
        return Button { selected = i } label: {
            HStack(spacing: 12) {
                Text("\(i + 1)")
                    .font(.hand(28))
                    .foregroundStyle(isSelected ? Theme.paper : Theme.ink)
                    .frame(width: 44, height: 44)
                    .background(isSelected ? Theme.ink : Theme.card, in: .circle)
                    .overlay(Circle().stroke(Theme.ink, lineWidth: 2))
                VStack(alignment: .leading, spacing: 2) {
                    if let p {
                        if let run = p.run {
                            Text("진행 중 · \(run.whereText)").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                            Text("골드 \(Fmt.n(run.gold)) · 처치 \(run.kills) · 덱 \(run.deck.count)장")
                                .font(.caption).foregroundStyle(Theme.muted)
                        } else {
                            Text("진행 중인 게임 없음").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                        }
                        Text("최고 \(p.bestDepth)층 · 업적 \(p.achievements.count)/\(Achievements.all.count) · 도감 \(p.collection.intersection(CardCatalog.allKeys).count)/\(CardCatalog.entries.count)")
                            .font(.caption).foregroundStyle(Theme.muted)
                        Text("저장: \(p.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption2).foregroundStyle(Theme.muted)
                    } else {
                        Text("빈 슬롯").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.muted)
                        Text("새 게임을 시작할 수 있어요").font(.caption).foregroundStyle(Theme.muted)
                    }
                }
                Spacer(minLength: 0)
                if p != nil {
                    Button {
                        confirmDelete = i
                    } label: {
                        Image(systemName: "trash").foregroundStyle(Theme.red).frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("슬롯 \(i + 1) 지우기")
                }
            }
            .padding(10)
            .background(Theme.card, in: .rect(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(isSelected ? Theme.ink : Theme.edge, lineWidth: isSelected ? 2.5 : 2))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: 시작하기

    @ViewBuilder
    private var startButtons: some View {
        let hasRun = store.slots[selected]?.run != nil
        VStack(spacing: 10) {
            if hasRun {
                Button("이어하기") { onStart(selected, false) }
                    .buttonStyle(MainButtonStyle())
                Button("새 게임") { confirmNewGame = true }
                    .buttonStyle(MainButtonStyle(filled: false))
            } else {
                Button("시작하기") { onStart(selected, true) }
                    .buttonStyle(MainButtonStyle())
            }
        }
        .font(.title3)
    }

    // MARK: 업적 · 도감

    private var progressButtons: some View {
        HStack(spacing: 10) {
            progressTile(icon: "🏆", title: "업적", value: "\(profile.achievements.count)/\(Achievements.all.count)") {
                showAchievements = true
            }
            progressTile(icon: "🃏", title: "카드 도감", value: "\(profile.collection.intersection(CardCatalog.allKeys).count)/\(CardCatalog.entries.count)") {
                showCollection = true
            }
        }
    }

    private func progressTile(icon: String, title: String, value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(icon).font(.largeTitle)
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                Text(value).font(.hand(20)).foregroundStyle(Theme.red)
                Text("슬롯 \(selected + 1)").font(.caption2).foregroundStyle(Theme.muted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Theme.card, in: .rect(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.ink, lineWidth: 2))
            .background { RoundedRectangle(cornerRadius: 12).fill(Theme.ink).offset(y: 3) }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 업적 화면

struct AchievementsView: View {
    let profile: SlotProfile
    let slot: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                SheetHeader(title: "업적", subtitle: "슬롯 \(slot + 1) · \(profile.achievements.count)/\(Achievements.all.count) 달성") { dismiss() }
                statsBox
                ForEach(Achievements.all) { a in
                    let date = profile.achievements[a.id]
                    HStack(spacing: 12) {
                        Text(date == nil ? "🔒" : a.icon)
                            .font(.title)
                            .frame(width: 44, height: 44)
                            .background(date == nil ? Theme.paper : Theme.hl, in: .circle)
                            .grayscale(date == nil ? 1 : 0)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(a.title).font(.body.weight(.semibold)).foregroundStyle(date == nil ? Theme.muted : Theme.ink)
                            Text(a.desc).font(.footnote).foregroundStyle(Theme.muted)
                            if let date {
                                Text("\(date.formatted(date: .abbreviated, time: .omitted)) 달성")
                                    .font(.caption2).foregroundStyle(Theme.red)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(10)
                    .background(Theme.card, in: .rect(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(date == nil ? Theme.edge : Theme.ink, lineWidth: 2))
                }
            }
            .padding(18)
        }
        .background(PaperBackground())
    }

    private var statsBox: some View {
        let s = profile.stats
        return Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
            row("최고 기록", "\(profile.bestDepth)층, 한 방 \(Fmt.n(profile.bestSingle))")
            row("끝낸 게임", "\(s.runsFinished)판")
            row("누적 처치", "\(s.kills)마리 (정예 \(s.eliteKills), 보스 \(s.bossKills))")
            row("최고 한 방", Fmt.n(s.maxHit))
            row("상점 구매", "\(s.cardsBought)장")
        }
        .font(.footnote)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: .rect(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.edge, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
    }

    private func row(_ t: String, _ v: String) -> some View {
        GridRow {
            Text(t).foregroundStyle(Theme.muted)
            Text(v).foregroundStyle(Theme.text).bold()
        }
    }
}

// MARK: - 카드 도감

struct CollectionView: View {
    let profile: SlotProfile
    let slot: Int
    @Environment(\.dismiss) private var dismiss
    @State private var info = "카드를 누르면 설명이 보여요. 덱에 들어온 카드가 도감에 기록돼요."

    var body: some View {
        let found = profile.collection.intersection(CardCatalog.allKeys).count
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                SheetHeader(title: "카드 도감", subtitle: "슬롯 \(slot + 1) · \(found)/\(CardCatalog.entries.count) 수집") { dismiss() }
                ProgressView(value: profile.collectionProgress).tint(Theme.red)
                Text(info)
                    .font(.footnote)
                    .foregroundStyle(Theme.text)
                    .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(Theme.card, in: .rect(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.edge, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
                section("숫자", prefix: "num-")
                section("기호", prefix: "op-")
                section("강화", prefix: "enh-")
                section("변신", prefix: "tr-")
            }
            .padding(18)
        }
        .background(PaperBackground())
    }

    private func section(_ title: String, prefix: String) -> some View {
        let entries = CardCatalog.entries.filter { $0.key.hasPrefix(prefix) }
        return VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.footnote.weight(.semibold)).foregroundStyle(Theme.muted)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 56), spacing: 8)], spacing: 8) {
                ForEach(entries) { e in
                    let owned = profile.collection.contains(e.key)
                    Button {
                        info = owned ? "\(e.title): \(e.desc)" : "아직 발견하지 못한 카드예요."
                    } label: {
                        VStack(spacing: 3) {
                            if owned {
                                CardView(card: e.sample, fontSize: 26, badgeSize: 7)
                            } else {
                                GhostCard(label: "?")
                                    .overlay { Text("?").font(.hand(26)).foregroundStyle(Theme.edge) }
                            }
                            Text(owned ? e.title : "???")
                                .font(.system(size: 9))
                                .foregroundStyle(Theme.muted)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(owned ? e.title : "미발견 카드")
                }
            }
        }
    }
}

struct SheetHeader: View {
    let title: String
    let subtitle: String
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.hand(32)).foregroundStyle(Theme.red)
                Spacer()
                Button("닫기", action: onClose).buttonStyle(ChipButtonStyle())
            }
            Text(subtitle).font(.subheadline).foregroundStyle(Theme.muted)
        }
    }
}

#Preview {
    MainMenuView(store: SaveStore()) { _, _ in }
}
