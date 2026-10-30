import AVFoundation
import Observation

/// 효과음 이름 (Sounds/*.wav, sound/gen.py가 만들어요)
enum SFX: String, CaseIterable {
    case hit1, hit2, hit3, hit4, tick, sparkle, luck, miss, coins, bell, fanfare, chime, swish, place, toss
}

/// 효과음과 배경음. 켜고 끈 설정은 기기에 기억해요
@Observable
final class Sound {
    static let shared = Sound()

    var musicOn: Bool {
        didSet { UserDefaults.standard.set(musicOn, forKey: "musicOn"); updateMusic() }
    }
    var sfxOn: Bool {
        didSet { UserDefaults.standard.set(sfxOn, forKey: "sfxOn") }
    }

    @ObservationIgnored private var pools: [SFX: [AVAudioPlayer]] = [:]
    @ObservationIgnored private var music: AVAudioPlayer?
    @ObservationIgnored private var lastSwish = Date.distantPast

    private init() {
        musicOn = UserDefaults.standard.object(forKey: "musicOn") as? Bool ?? true
        sfxOn = UserDefaults.standard.object(forKey: "sfxOn") as? Bool ?? true
        #if os(iOS) || os(visionOS)
        // 무음 모드를 따르고, 다른 앱 음악과 섞여요
        try? AVAudioSession.sharedInstance().setCategory(.ambient)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        for s in SFX.allCases {
            // 빠르게 겹쳐 나는 소리는 여러 개를 돌려 써요
            let count = [.swish, .tick, .place].contains(s) ? 4 : 2
            pools[s] = (0..<count).compactMap { _ in Self.load(s.rawValue) }
        }
        music = Self.load("bgm")
        music?.numberOfLoops = -1
        music?.volume = 0.32
    }

    private static func load(_ name: String) -> AVAudioPlayer? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav"),
              let p = try? AVAudioPlayer(contentsOf: url) else { return nil }
        p.enableRate = true
        p.prepareToPlay()
        return p
    }

    func play(_ s: SFX, volume: Float = 1, rate: Float = 1) {
        guard sfxOn, let pool = pools[s], let p = pool.first(where: { !$0.isPlaying }) ?? pool.first else { return }
        p.currentTime = 0
        p.volume = volume
        p.rate = rate
        p.play()
    }

    /// 카드를 훑을 때: 너무 자주 겹치지 않게 하고 음높이를 조금씩 바꿔요
    func swish() {
        guard Date().timeIntervalSince(lastSwish) > 0.06 else { return }
        lastSwish = Date()
        play(.swish, volume: 0.6, rate: .random(in: 0.92...1.08))
    }

    /// 피해 크기(적 체력 대비)에 따라 1~4단계. 화면 흔들림도 같은 단계를 써요
    static func hitLevel(_ dmg: Double, _ hp: Double) -> Int {
        dmg <= 0 ? 0 : dmg < hp * 0.15 ? 1 : dmg < hp * 0.4 ? 2 : dmg < hp ? 3 : 4
    }

    func updateMusic() {
        guard let music else { return }
        if musicOn {
            if !music.isPlaying {
                music.volume = 0
                music.play()
                music.setVolume(0.32, fadeDuration: 1.5)
            }
        } else {
            music.pause()
        }
    }
}
