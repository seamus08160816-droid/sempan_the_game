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
    @State private var showSound = false
    @State private var showPerks = false
    @State private var showPick = false

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
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 6) {
                LangButton()
                SoundButton { showSound = true }
            }
            .padding(20)
        }
        .sheet(isPresented: $showSound) { SoundSettingsSheet() }
        .confirmationDialog(L("슬롯 \(selected + 1)에 진행 중인 게임이 있어요", "Slot \(selected + 1) has a game in progress"), isPresented: $confirmNewGame, titleVisibility: .visible) {
            Button(L("새 게임 시작 (진행 중인 판은 사라져요)", "Start a new game (the current run will be lost)"), role: .destructive) { begin() }
            Button(L("취소", "Cancel"), role: .cancel) {}
        }
        .alert(L("슬롯 \((confirmDelete ?? 0) + 1)을 지울까요?", "Delete slot \((confirmDelete ?? 0) + 1)?"), isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } })) {
            Button(L("지우기", "Delete"), role: .destructive) {
                if let i = confirmDelete { store.delete(i) }
                confirmDelete = nil
            }
            Button(L("취소", "Cancel"), role: .cancel) { confirmDelete = nil }
        } message: {
            Text(L("진행 중인 게임, 기록, 업적, 카드 도감이 모두 지워져요.", "The game in progress, records, achievements and collection will all be deleted."))
        }
        .sheet(isPresented: $showAchievements) { AchievementsView(profile: profile, slot: selected) }
        .sheet(isPresented: $showCollection) { CollectionView(profile: profile, slot: selected) }
        .sheet(isPresented: $showPerks) { PerkSheet(store: store, slot: selected) }
        .sheet(isPresented: $showPick) {
            PerkPickSheet(getProfile: { store.profile(selected) },
                          setEquipped: { list in store.update(selected) { $0.equipped = list } },
                          onStart: { onStart(selected, true) })
        }
    }

    private var title: some View {
        VStack(spacing: 6) {
            Text(L("셈판", "Sempan"))
                .font(.hand(72))
                .foregroundStyle(Theme.ink)
                .padding(.top, 30)
            Text(L("숫자와 기호로 수식을 만들어 몹을 쓰러뜨리는 카드 로그라이크", "A card roguelike where you build equations from numbers and operators to defeat monsters"))
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
            Text(L("저장 슬롯", "Save slots")).font(.footnote.weight(.semibold)).foregroundStyle(Theme.muted)
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
                            Text(L("진행 중 · \(run.whereText)", "In progress · \(run.whereText)")).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                            Text(L("골드 \(Fmt.n(run.gold)) · 처치 \(run.kills) · 덱 \(run.deck.count)장", "Gold \(Fmt.n(run.gold)) · Kills \(run.kills) · Deck \(run.deck.count)"))
                                .font(.caption).foregroundStyle(Theme.muted)
                        } else {
                            Text(L("진행 중인 게임 없음", "No game in progress")).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                        }
                        Text(L("최고 \(p.bestDepth)층 · 업적 \(p.achievements.count)/\(Achievements.all.count) · 도감 \(p.collection.intersection(CardCatalog.allKeys).count)/\(CardCatalog.entries.count)", "Best floor \(p.bestDepth) · Achievements \(p.achievements.count)/\(Achievements.all.count) · Collection \(p.collection.intersection(CardCatalog.allKeys).count)/\(CardCatalog.entries.count)"))
                            .font(.caption).foregroundStyle(Theme.muted)
                        Text(L("저장: \(Lang.shared.date(p.updatedAt))", "Saved: \(Lang.shared.date(p.updatedAt))"))
                            .font(.caption2).foregroundStyle(Theme.muted)
                    } else {
                        Text(L("빈 슬롯", "Empty slot")).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.muted)
                        Text(L("새 게임을 시작할 수 있어요", "Ready for a new game")).font(.caption).foregroundStyle(Theme.muted)
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
                    .accessibilityLabel(L("슬롯 \(i + 1) 지우기", "Delete slot \(i + 1)"))
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

    /// 해금한 퍽이 있으면 먼저 고르고 시작해요
    private func begin() {
        if PerkPickSheet.needed(profile) { showPick = true } else { onStart(selected, true) }
    }

    @ViewBuilder
    private var startButtons: some View {
        let hasRun = store.slots[selected]?.run != nil
        VStack(spacing: 10) {
            if hasRun {
                Button(L("이어하기", "Continue")) { onStart(selected, false) }
                    .buttonStyle(MainButtonStyle())
                Button(L("새 게임", "New game")) { confirmNewGame = true }
                    .buttonStyle(MainButtonStyle(filled: false))
            } else {
                Button(L("시작하기", "Start")) { begin() }
                    .buttonStyle(MainButtonStyle())
            }
        }
        .font(.title3)
    }

    // MARK: 업적 · 도감

    private var progressButtons: some View {
        HStack(spacing: 10) {
            progressTile(icon: "🏆", title: L("업적", "Achievements"), value: "\(profile.achievements.count)/\(Achievements.all.count)") {
                showAchievements = true
            }
            progressTile(icon: "🃏", title: L("카드 도감", "Collection"), value: "\(profile.collection.intersection(CardCatalog.allKeys).count)/\(CardCatalog.entries.count)") {
                showCollection = true
            }
            progressTile(icon: "🎒", title: L("퍽", "Perks"), value: "\((profile.perksUnlocked ?? []).count)/\(MetaPerk.allCases.count)") {
                showPerks = true
            }
        }
    }

    private func progressTile(icon: String, title: String, value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(icon).font(.largeTitle)
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                Text(value).font(.hand(20)).foregroundStyle(Theme.red)
                Text(L("슬롯 \(selected + 1)", "Slot \(selected + 1)")).font(.caption2).foregroundStyle(Theme.muted)
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
                SheetHeader(title: L("업적", "Achievements"), subtitle: L("슬롯 \(slot + 1) · \(profile.achievements.count)/\(Achievements.all.count) 달성", "Slot \(slot + 1) · \(profile.achievements.count)/\(Achievements.all.count) unlocked")) { dismiss() }
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
                                Text(L("\(Lang.shared.date(date, time: false)) 달성", "Unlocked \(Lang.shared.date(date, time: false))"))
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
            row(L("최고 기록", "Best run"), L("\(profile.bestDepth)층, 한 방 \(Fmt.n(profile.bestSingle))", "Floor \(profile.bestDepth), best hit \(Fmt.n(profile.bestSingle))"))
            row(L("끝낸 게임", "Runs finished"), L("\(s.runsFinished)판", "\(s.runsFinished)"))
            row(L("누적 처치", "Total kills"), L("\(s.kills)마리 (정예 \(s.eliteKills), 보스 \(s.bossKills))", "\(s.kills) (elites \(s.eliteKills), bosses \(s.bossKills))"))
            row(L("최고 한 방", "Best hit"), Fmt.n(s.maxHit))
            row(L("상점 구매", "Cards bought"), L("\(s.cardsBought)장", "\(s.cardsBought)"))
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
    @State private var info: String?

    var body: some View {
        let found = profile.collection.intersection(CardCatalog.allKeys).count
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                SheetHeader(title: L("카드 도감", "Collection"), subtitle: L("슬롯 \(slot + 1) · \(found)/\(CardCatalog.entries.count) 수집", "Slot \(slot + 1) · \(found)/\(CardCatalog.entries.count) collected")) { dismiss() }
                ProgressView(value: profile.collectionProgress).tint(Theme.red)
                Text(info ?? L("카드를 누르면 설명이 보여요. 덱에 들어온 카드가 도감에 기록돼요.", "Tap a card to see what it does. Cards that enter your deck are added to the collection."))
                    .font(.footnote)
                    .foregroundStyle(Theme.text)
                    .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(Theme.card, in: .rect(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.edge, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
                section(L("숫자", "Numbers"), prefix: "num-")
                section(L("기호", "Operators"), prefix: "op-")
                section(L("강화", "Enhancements"), prefix: "enh-")
                section(L("변신", "Transformations"), prefix: "tr-")
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
                        info = owned ? "\(e.title): \(e.desc)" : L("아직 발견하지 못한 카드예요.", "You haven't found this card yet.")
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
                    .accessibilityLabel(owned ? e.title : L("미발견 카드", "Undiscovered card"))
                }
            }
        }
    }
}

// MARK: - 퍽

/// 퍽 보기 (메인 화면): 진행 중인 판의 퍽은 판이 끝날 때까지 바꿀 수 없어요
struct PerkSheet: View {
    let store: SaveStore
    let slot: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let p = store.profile(slot)
        let unlocked = p.perksUnlocked ?? []
        let mine = p.run?.perks ?? []
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                SheetHeader(title: L("퍽", "Perks"), subtitle: L("슬롯 \(slot + 1) · 해금 \(unlocked.count)/\(MetaPerk.allCases.count)", "Slot \(slot + 1) · \(unlocked.count)/\(MetaPerk.allCases.count) unlocked")) { dismiss() }
                Text((p.run != nil
                      ? L("이번 판에 장착한 퍽은 \(mine.count)개예요. 판이 끝나야 바꿀 수 있어요.", "This run has \(mine.count) perks equipped. You can change them when the run ends.")
                      : L("새 게임을 시작할 때 \(MetaPerk.slots)개까지 골라요.", "Choose up to \(MetaPerk.slots) when you start a new game."))
                     + L(" 더 깊이 내려갈수록 하나씩 해금돼요 (최고 \(MetaPerk.depthText(max(1, p.stats.maxDepth ?? 0))))."," Go deeper to unlock more (best: \(MetaPerk.depthText(max(1, p.stats.maxDepth ?? 0))))).")
                )
                .font(.footnote).foregroundStyle(Theme.muted)
                ForEach(MetaPerk.allCases) { k in
                    let open = unlocked.contains(k.rawValue)
                    PerkRow(perk: k, open: open, on: mine.contains(k.rawValue),
                            tag: !open ? L("\(MetaPerk.depthText(k.depth)) 도달 시 해금", "Unlocks at \(MetaPerk.depthText(k.depth))") : mine.contains(k.rawValue) ? L("이번 판", "This run") : "")
                }
            }
            .padding(18)
        }
        .background(PaperBackground())
    }
}

/// 새 게임을 시작하기 전에 이번 판에 쓸 퍽을 골라요 (판이 끝날 때까지 못 바꿔요)
struct PerkPickSheet: View {
    let getProfile: () -> SlotProfile
    let setEquipped: ([String]) -> Void
    let onStart: () -> Void
    @Environment(\.dismiss) private var dismiss

    /// 해금한 퍽이 하나라도 있으면 시작 전에 골라요
    static func needed(_ p: SlotProfile) -> Bool { !(p.perksUnlocked ?? []).isEmpty }

    var body: some View {
        let p = getProfile()
        let unlocked = p.perksUnlocked ?? []
        // 지난번 고른 것을 기본으로, 해금한 것만 남겨요
        let eq = Array((p.equipped ?? []).filter { unlocked.contains($0) }.prefix(MetaPerk.slots))
        let locked = MetaPerk.allCases.count - unlocked.count
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                SheetHeader(title: L("퍽 고르기", "Choose perks"), subtitle: L("이번 판에 쓸 퍽을 \(MetaPerk.slots)개까지 골라요 (\(eq.count)/\(MetaPerk.slots)). 판이 끝날 때까지 바꿀 수 없어요.", "Choose up to \(MetaPerk.slots) perks for this run (\(eq.count)/\(MetaPerk.slots)). They can't be changed until the run ends.")) { dismiss() }
                ForEach(MetaPerk.allCases.filter { unlocked.contains($0.rawValue) }) { k in
                    let on = eq.contains(k.rawValue)
                    Button {
                        var next = eq
                        if let i = next.firstIndex(of: k.rawValue) { next.remove(at: i) }
                        else if next.count < MetaPerk.slots { next.append(k.rawValue) }
                        setEquipped(next)
                        Sound.shared.play(.place)
                    } label: {
                        PerkRow(perk: k, open: true, on: on, tag: on ? L("장착", "Equipped") : eq.count >= MetaPerk.slots ? "" : L("고르기", "Choose"))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
                if locked > 0 {
                    Text(L("아직 잠긴 퍽 \(locked)개는 더 깊이 내려가면 해금돼요.", "Go deeper to unlock the \(locked) locked perks.")).font(.footnote).foregroundStyle(Theme.muted)
                }
                Button(eq.isEmpty ? L("퍽 없이 시작", "Start without perks") : L("이 퍽 \(eq.count)개로 시작", "Start with these \(eq.count) perks")) {
                    setEquipped(eq)
                    dismiss()
                    onStart()
                }
                .buttonStyle(MainButtonStyle())
            }
            .padding(18)
        }
        .background(PaperBackground())
    }
}

struct PerkRow: View {
    let perk: MetaPerk
    let open: Bool
    let on: Bool
    let tag: String

    var body: some View {
        HStack(spacing: 12) {
            Text(open ? perk.icon : "🔒")
                .font(.title2)
                .frame(width: 44, height: 44)
                .background(on ? Theme.hl : Theme.paper, in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(perk.name).font(.body.weight(.semibold)).foregroundStyle(Theme.ink)
                Text(perk.desc).font(.footnote).foregroundStyle(Theme.muted).multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
            Text(tag).font(.caption.weight(.semibold)).foregroundStyle(Theme.red)
        }
        .padding(10)
        .background(Theme.card, in: .rect(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(on ? Theme.ink : Theme.edge, lineWidth: 2))
        .opacity(open ? 1 : 0.55)
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
                Button(L("닫기", "Close"), action: onClose).buttonStyle(ChipButtonStyle())
            }
            Text(subtitle).font(.subheadline).foregroundStyle(Theme.muted)
        }
    }
}

#Preview {
    MainMenuView(store: SaveStore()) { _, _ in }
}
