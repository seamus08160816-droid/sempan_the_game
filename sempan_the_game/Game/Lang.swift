import Foundation
import Observation

/// 화면 언어 (한국어 / English). 고른 언어는 기기에 기억해요
@Observable
final class Lang {
    static let shared = Lang()

    /// "ko" 또는 "en"
    var code: String {
        didSet { UserDefaults.standard.set(code, forKey: "lang") }
    }

    var isKorean: Bool { code == "ko" }

    /// 날짜·숫자 표시에 쓰는 지역
    var locale: Locale { Locale(identifier: isKorean ? "ko_KR" : "en_US") }

    private init() {
        if let saved = UserDefaults.standard.string(forKey: "lang"), saved == "ko" || saved == "en" {
            code = saved
        } else {
            // 처음에는 기기 언어를 따라가요 (한국어 기기면 한국어, 아니면 영어)
            code = (Locale.preferredLanguages.first ?? "").hasPrefix("ko") ? "ko" : "en"
        }
    }

    func toggle() { code = isKorean ? "en" : "ko" }

    /// 날짜를 지금 언어로 (time이 false면 날짜만)
    func date(_ d: Date, time: Bool = true) -> String {
        d.formatted(Date.FormatStyle(date: .abbreviated, time: time ? .shortened : .omitted).locale(locale))
    }
}

/// 지금 언어에 맞는 글자를 골라요
func L(_ ko: String, _ en: String) -> String {
    Lang.shared.isKorean ? ko : en
}
