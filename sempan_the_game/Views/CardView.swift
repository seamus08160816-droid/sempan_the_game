import SwiftUI

/// 카드 한 장 (3:4 비율). 숫자/기호, 강화 배지, 변신 표기를 보여줘요
struct CardView: View {
    let card: Card
    var fireBonus: Double = 10
    var fontSize: CGFloat = 30
    var badgeSize: CGFloat = 9
    var shadow = true
    /// 겹쳐 쥔 손패처럼 숫자를 왼쪽 위 모서리에 표시해요
    var faceCorner = false

    private var isGold: Bool { card.enh.contains(.gold) }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8)
        ZStack {
            face
                .font(.hand(fontSize))
                .foregroundStyle(isGold ? Theme.hlText : card.kind == .op ? Theme.red : Theme.ink)
                .minimumScaleFactor(0.4)
                .lineLimit(1)
                .padding(.horizontal, 2)
                .padding(.bottom, faceCorner ? 0 : fontSize * 0.35)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: faceCorner ? .topLeading : .center)
                .padding(.leading, faceCorner ? fontSize * 0.15 : 0)
                .padding(.top, faceCorner ? fontSize * 0.08 : 0)
            badges
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 3)
                .padding(.horizontal, 2)
        }
        .aspectRatio(3 / 4, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .background(isGold ? Theme.hl : card.kind == .op ? Theme.op : Theme.card, in: shape)
        .overlay {
            if card.tr != nil { shape.inset(by: 2).stroke(Theme.hl, lineWidth: 3) }
        }
        .overlay { border(shape) }
        .background {
            if shadow { shape.fill(Theme.edge).offset(y: 3) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(card.label)
    }

    @ViewBuilder
    private func border(_ shape: RoundedRectangle) -> some View {
        if isGold {
            shape.stroke(Theme.goldEdge, lineWidth: 1.5)
        } else if card.enh.contains(.fire) {
            shape.stroke(Theme.red, lineWidth: 2)
        } else if card.enh.contains(.luck) {
            shape.stroke(Theme.ink, style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
        } else {
            shape.stroke(Theme.edge, lineWidth: 1.5)
        }
    }

    @ViewBuilder
    private var face: some View {
        let small = Font.hand(fontSize * 0.6)
        if card.kind == .op {
            Text(card.op?.symbol ?? "")
        } else if let tr = card.tr {
            switch tr {
            case .sq:
                Text("\(card.v)\(Text("2").font(small).baselineOffset(fontSize * 0.4))")
            case .pow2:
                Text("\(Text("2").font(small))\(Text("\(card.v)").font(small).baselineOffset(fontSize * 0.4))")
            case .exp:
                Text("\(Text("e").font(small))\(Text("\(card.v)").font(small).baselineOffset(fontSize * 0.4))")
            case .fact:
                Text("\(card.v)\(Text("!").font(small))")
            }
        } else {
            Text("\(card.v)")
        }
    }

    private var badges: some View {
        HStack(spacing: 2) {
            ForEach(card.enh, id: \.self) { e in
                badge(e)
            }
            if card.up > 0 {
                Text("▲\(card.up * 3)")
                    .badgeStyle(size: badgeSize, fg: Theme.ink, bg: Theme.paper, border: Theme.edge)
            }
        }
        .minimumScaleFactor(0.5)
        .lineLimit(1)
    }

    @ViewBuilder
    private func badge(_ e: Enh) -> some View {
        let label = e.badge + (e == .stack ? "+\(Fmt.n(card.bonus))" : "") + (e == .fire ? Fmt.n(fireBonus) : "")
        if e.isOpPerk {
            Text(label).badgeStyle(size: badgeSize, fg: .white, bg: Theme.red, border: Theme.red)
        } else if e == .gold {
            Text(label).badgeStyle(size: badgeSize, fg: Theme.hl, bg: Theme.hlText, border: Theme.hlText)
        } else if e == .fire {
            Text(label).badgeStyle(size: badgeSize, fg: Theme.red, bg: Theme.paper, border: Theme.red)
        } else {
            Text(label).badgeStyle(size: badgeSize, fg: Theme.text, bg: Theme.paper, border: Theme.edge)
        }
    }
}

extension Text {
    func badgeStyle(size: CGFloat, fg: Color, bg: Color, border: Color) -> some View {
        self.font(.system(size: size, weight: .semibold))
            .foregroundStyle(fg)
            .padding(.horizontal, 3)
            .background(bg, in: .rect(cornerRadius: 3))
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(border, lineWidth: 1))
    }
}

/// 카드 자리 표시 (빈 칸)
struct GhostCard: View {
    var label: String = ""

    var body: some View {
        RoundedRectangle(cornerRadius: 7)
            .stroke(Theme.edge, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            .aspectRatio(3 / 4, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay { Text(label).font(.caption2).foregroundStyle(Theme.muted) }
    }
}

#Preview {
    var gold = Card.number(1, 7)
    gold.enh = [.gold, .fire]
    var amp = Card.symbol(2, .add)
    amp.enh = [.stack]
    amp.bonus = 8
    var tr = Card.number(3, 5)
    tr.tr = .pow2
    tr.up = 1
    return HStack {
        CardView(card: .number(0, 9))
        CardView(card: gold)
        CardView(card: amp)
        CardView(card: tr)
        CardView(card: .symbol(4, .mul))
    }
    .padding()
    .background(PaperBackground())
}
