import SwiftUI
import CoreText
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// 원본 CSS 변수를 옮긴 색상 (라이트/다크 자동 전환)
enum Theme {
    static let paper = dynamic(0xF7F8F3, 0x1C2723)
    static let grid = dynamic(0xDCE6EF, 0x26342E)
    static let ink = dynamic(0x1D2F6F, 0xB3CBFF)
    static let text = dynamic(0x22252B, 0xECEFE8)
    static let muted = dynamic(0x5E6573, 0xA3AEA7)
    static let red = dynamic(0xD3302A, 0xFF6B5E)
    static let hl = dynamic(0xF5E23B, 0xE8D53A)
    static let hlText = Color(hex: 0x2A2600)
    static let goldEdge = Color(hex: 0xB9A400)
    static let card = dynamic(0xFFFFFF, 0x26332E)
    static let edge = dynamic(0xC3CEDB, 0x3E4F47)
    static let op = dynamic(0xE8EEF8, 0x2C3B45)

    private static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        #if canImport(UIKit)
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
        #elseif canImport(AppKit)
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(hex: dark) : NSColor(hex: light)
        })
        #else
        Color(hex: light)
        #endif
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

#if canImport(UIKit)
extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
#elseif canImport(AppKit)
extension NSColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
#endif

extension Font {
    /// 번들에 포함된 Gaegu 글꼴을 한 번만 등록 (Info.plist 설정 없이 iOS/macOS 모두 동작)
    private static let registerGaegu: Void = {
        for name in ["Gaegu-Light", "Gaegu-Regular", "Gaegu-Bold"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }()

    /// 원본과 같은 손글씨 글꼴 Gaegu (Light / Regular / Bold)
    static func hand(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        _ = registerGaegu
        let name: String
        switch weight {
        case .ultraLight, .thin, .light: name = "Gaegu-Light"
        case .regular: name = "Gaegu-Regular"
        default: name = "Gaegu-Bold"
        }
        return .custom(name, size: size)
    }
}

/// 모눈종이 배경
struct PaperBackground: View {
    var body: some View {
        Canvas { ctx, size in
            var path = Path()
            let step: CGFloat = 22
            var x: CGFloat = 0
            while x <= size.width { path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height)); x += step }
            var y: CGFloat = 0
            while y <= size.height { path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y)); y += step }
            ctx.stroke(path, with: .color(Theme.grid), lineWidth: 1)
        }
        .background(Theme.paper)
        .ignoresSafeArea()
    }
}

// MARK: - 버튼 스타일

struct MainButtonStyle: ButtonStyle {
    var filled = true
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .padding(.horizontal, 10)
            .foregroundStyle(filled ? Theme.paper : Theme.ink)
            .background(filled ? Theme.ink : Theme.card, in: .rect(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.ink, lineWidth: 2))
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
            .offset(y: configuration.isPressed ? 2 : 0)
    }
}

struct ChipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Theme.card, in: .capsule)
            .overlay(Capsule().stroke(Theme.ink, lineWidth: 2))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// 흔들림 효과
struct ShakeEffect: GeometryEffect {
    var animatableData: CGFloat
    /// 흔들림 세기 1~4
    var level = 2

    func effectValue(size: CGSize) -> ProjectionTransform {
        let t = animatableData - animatableData.rounded(.down)
        let amp: CGFloat = [0, 2, 5, 9, 14][max(0, min(4, level))]
        let dx = sin(t * .pi * 6) * amp * (1 - t)
        let dy = level >= 3 ? sin(t * .pi * 8) * amp * 0.35 * (1 - t) : 0
        let rot = level >= 3 ? sin(t * .pi * 6) * 0.012 * (1 - t) : 0
        return ProjectionTransform(CGAffineTransform(translationX: dx, y: dy).rotated(by: rot))
    }
}

/// 형광펜 밑줄
struct Highlight: ViewModifier {
    func body(content: Content) -> some View {
        content.background(alignment: .bottom) {
            Theme.hl.frame(height: 10).offset(y: -2)
        }
    }
}

/// 반투명 배경 위의 시트
struct OverlaySheet<Content: View>: View {
    /// 시트의 최대 너비 (가로 화면에서 두 칸으로 나눌 때 넓혀요)
    var maxWidth: CGFloat = 460
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            ScrollView {
                content
                    .padding(18)
                    .frame(maxWidth: maxWidth)
                    .background { PaperBackground().clipShape(.rect(cornerRadius: 14)) }
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.ink, lineWidth: 2))
                    .padding(16)
                    .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .defaultScrollAnchor(.center)
        }
        .transition(.opacity)
    }
}
