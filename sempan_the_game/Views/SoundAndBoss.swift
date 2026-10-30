import SwiftUI

// MARK: - 소리 설정

/// 헤더·메인 화면 오른쪽 위의 소리 버튼
struct SoundButton: View {
    let action: () -> Void

    var body: some View {
        let on = Sound.shared.musicOn || Sound.shared.sfxOn
        Button(action: action) {
            Image(systemName: on ? "speaker.wave.2.fill" : "speaker.slash.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .frame(width: 32, height: 32)
                .background(Theme.card, in: .circle)
                .overlay(Circle().stroke(Theme.ink, lineWidth: 2))
                .opacity(on ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("소리 설정")
    }
}

struct SoundSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable private var sound = Sound.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SheetHeader(title: "소리", subtitle: "이 기기에서만 기억해요.") { dismiss() }
            row("배경음", "잔잔한 모눈종이 음악", $sound.musicOn)
            row("효과음", "카드, 계산, 동전, 종소리", $sound.sfxOn)
            Spacer(minLength: 0)
        }
        .padding(18)
        .background(PaperBackground())
        .presentationDetents([.medium])
    }

    private func row(_ title: String, _ desc: String, _ isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold)).foregroundStyle(Theme.ink)
                Text(desc).font(.caption).foregroundStyle(Theme.muted)
            }
        }
        .tint(Theme.ink)
        .padding(12)
        .background(Theme.card, in: .rect(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.edge, lineWidth: 2))
    }
}

// MARK: - 보스 등장

/// 보스 앞: 어두운 화면에 붉은 띠가 미끄러져 들어오고 이름판이 꽂혀요 (종소리는 GameSession이 내요)
struct BossIntroOverlay: View {
    let node: MapNode
    let act: Int
    let hp: Double
    @State private var bands = false
    @State private var slam = false
    @State private var quake = 0

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                Color(hex: 0x0D1430).opacity(0.94)
                Color(hex: 0xD3302A)
                    .frame(width: w * 1.3, height: h * 0.3)
                    .rotationEffect(.degrees(-6))
                    .offset(x: bands ? 0 : -w * 1.4)
                Color(hex: 0xF5E23B)
                    .frame(width: w * 1.3, height: h * 0.03)
                    .rotationEffect(.degrees(-6))
                    .offset(x: bands ? 0 : w * 1.4, y: h * 0.165)
                VStack(spacing: 4) {
                    Text("👑").font(.system(size: 60))
                    Text(node.name)
                        .font(.hand(52))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.35), radius: 0, y: 4)
                    Text("\(act)막 보스 · 체력 \(Fmt.n(hp))")
                        .font(.subheadline.weight(.semibold))
                        .tracking(1.5)
                        .foregroundStyle(Color(hex: 0xF5E23B))
                }
                .scaleEffect(slam ? 1 : 2.6)
                .opacity(slam ? 1 : 0)
                .modifier(ShakeEffect(animatableData: CGFloat(quake), level: 4))
            }
            .frame(width: w, height: h)
        }
        .ignoresSafeArea()
        .transition(.opacity)
        .accessibilityElement(children: .combine)
        .task {
            withAnimation(.timingCurve(0.2, 0.9, 0.3, 1, duration: 0.35)) { bands = true }
            try? await Task.sleep(for: .milliseconds(350))
            withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) { slam = true }
            try? await Task.sleep(for: .milliseconds(270))
            withAnimation(.linear(duration: 0.7)) { quake = 1 }
        }
    }
}
