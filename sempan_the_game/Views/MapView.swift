import SwiftUI

/// 막 지도: 선으로 이어진 다음 칸으로만 갈 수 있어요
struct MapView: View {
    let session: GameSession
    private let rowH: CGFloat = 92

    var body: some View {
        let run = session.run
        VStack(alignment: .leading, spacing: 12) {
            Text(run.actName)
                .font(.hand(28))
                .foregroundStyle(Theme.ink)
            if !run.mapMsg.isEmpty {
                Text(run.mapMsg)
                    .font(.hand(19))
                    .foregroundStyle(Theme.red)
            }
            map(run)
            RulesBox(lines: [
                "선으로 이어진 다음 칸으로만 갈 수 있어요. 갈림길은 1~3갈래로 매번 달라져요. 칸 아래 숫자는 몹의 체력이에요.",
                "몹을 잡으면 골드를 받고 특전을 하나 골라요. 골드는 처치 보상, 넘친 피해(상한 있음), 남은 계산·버리기 횟수로 정해지고, 모두 적 체력에 비례해 커져요. 정예는 체력이 높지만 특전을 두 개 골라요. 상점에 들르면 싸우지 않으니 특전과 골드는 없어요.",
                "상점에서 숫자 카드는 숫자 카드와, 기호 카드는 기호 카드와 바꿔요. 가격도 적 체력과 함께 올라요.",
                "막이 오를 때마다 숫자를 더 크게 바꾸는 변신 강화가 하나씩 해금돼요. 2막 제곱, 3막 2의 거듭제곱, 4막 자연지수, 5막 팩토리얼, 6막 자기거듭제곱, 7막 슈퍼팩토리얼, 8막 하이퍼팩토리얼 순이에요. 6막부터는 × 카드를 ^ 카드로 진화시킬 수 있고, 보스가 테트레이션을 줘요.",
                "\(CFG.logAct - 1)막을 넘기면 차원 상승으로 로그 단계가 돼요. 체력은 10의 거듭제곱으로 바뀌고, 계산 결과의 자릿수(log₁₀)만큼 깎여요. 체력과 물가는 다시 1막처럼 시작해요."
            ])
        }
    }

    private func yOf(_ f: Int) -> CGFloat { (CGFloat(f) - 0.5) * rowH }

    private func nodeWidth(_ n: MapNode, _ width: CGFloat) -> CGFloat {
        n.type == .boss ? min(width * 0.4, 150) : min(width * 0.27, 100)
    }

    /// 칸 너비의 절반만큼 양 끝에서 떨어뜨려 칸이 화면 밖으로 나가지 않게 해요
    private func cx(_ n: MapNode, _ width: CGFloat) -> CGFloat {
        let half = nodeWidth(n, width) / 2 + 2
        return max(half, min(width - half, n.x / 100 * width))
    }

    private func map(_ run: RunState) -> some View {
        let height = CGFloat(CFG.actLen) * rowH
        let nodes = Array(run.map.joined())
        return GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .topLeading) {
                // 길
                Canvas { ctx, _ in
                    for n in nodes {
                        for id in n.next {
                            guard let m = run.node(id) else { continue }
                            var p = Path()
                            p.move(to: CGPoint(x: cx(n, w), y: yOf(n.floor)))
                            p.addLine(to: CGPoint(x: cx(m, w), y: yOf(m.floor)))
                            if run.visited.contains(n.id) && run.visited.contains(m.id) {
                                ctx.stroke(p, with: .color(Theme.red), lineWidth: 3)
                            } else if run.curID == n.id {
                                ctx.stroke(p, with: .color(Theme.ink), lineWidth: 2.5)
                            } else {
                                ctx.stroke(p, with: .color(Theme.edge), style: StrokeStyle(lineWidth: 2, dash: [3, 5]))
                            }
                        }
                    }
                }
                ForEach(1...CFG.actLen, id: \.self) { f in
                    Text("\(f)층")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.muted)
                        .position(x: 14, y: yOf(f))
                }
                ForEach(nodes) { n in
                    // id는 position보다 먼저 달아야 칸 자체의 위치로 스크롤돼요 (position은 지도 전체 크기를 차지해요)
                    nodeButton(n, run: run, width: w)
                        .id(n.id)
                        .position(x: cx(n, w), y: yOf(n.floor))
                }
            }
        }
        .frame(height: height)
    }

    private func nodeButton(_ n: MapNode, run: RunState, width: CGFloat) -> some View {
        let ok = run.reachable(n)
        let done = run.visited.contains(n.id)
        let past = !done && n.floor <= run.floor
        let nodeW = nodeWidth(n, width)
        let shape = RoundedRectangle(cornerRadius: 12)
        return Button {
            session.enterNode(n)
        } label: {
            VStack(spacing: 1) {
                Text(n.type.icon).font(.system(size: 20))
                Text(n.name)
                    .font(.system(size: 11, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                if n.type != .shop {
                    Text(run.hpText(run.hpFor(n.floor, n.type)))
                        .font(.hand(16))
                        .foregroundStyle(done ? Theme.hlText : Theme.red)
                }
            }
            .foregroundStyle(done ? Theme.hlText : Theme.text)
            .padding(.vertical, 6)
            .padding(.horizontal, 3)
            .frame(width: nodeW)
            .frame(minHeight: 62)
            .background(done ? Theme.hl : Theme.card, in: shape)
            .overlay(shape.stroke(done ? Theme.goldEdge : ok ? Theme.ink : Theme.edge, lineWidth: 2))
            .background { if ok { shape.fill(Theme.ink).offset(y: 3) } }
            .opacity(past ? 0.35 : 1)
            // 흐려진 칸 뒤로 길이 비치지 않도록 불투명한 바탕을 깔아요
            .background { shape.fill(Theme.paper) }
        }
        .buttonStyle(.plain)
        .disabled(!ok)
        .accessibilityLabel("\(n.floor)층 \(n.type.name) \(n.type == .shop ? "" : n.name)")
    }
}

/// 접히는 규칙 설명
struct RulesBox: View {
    let lines: [String]
    @State private var open = false

    var body: some View {
        DisclosureGroup(isExpanded: $open) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(lines, id: \.self) { Text($0) }
            }
            .font(.footnote)
            .foregroundStyle(Theme.muted)
            .padding(.top, 4)
        } label: {
            Text("규칙").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
        }
        .tint(Theme.ink)
    }
}
