import SwiftUI

struct ContentView: View {
    @State private var store = SaveStore()
    @State private var session: GameSession?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            if let session {
                GameView(session: session) {
                    self.session = nil
                }
                .transition(.move(edge: .trailing))
            } else {
                MainMenuView(store: store) { slot, fresh in
                    start(slot: slot, fresh: fresh)
                }
                .transition(.move(edge: .leading))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: session == nil)
        // 언어를 바꾸면 화면 전체를 다시 그려요 (L()로 만든 글자도 새 언어로)
        .id(Lang.shared.code)
        .onAppear { Sound.shared.updateMusic() }
        // 백그라운드로 가거나 다른 앱이 앞에 오면 소리를 꺼요
        .onChange(of: scenePhase) { _, phase in Sound.shared.setActive(phase == .active) }
        #if os(macOS)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in Sound.shared.setActive(false) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in Sound.shared.setActive(true) }
        #endif
    }

    /// 슬롯을 열어요. 저장된 판이 있으면 이어하고, fresh면 새 판을 시작해요
    private func start(slot: Int, fresh: Bool) {
        let hadRun = store.profile(slot).run != nil
        let s = GameSession(slot: slot, store: store)
        if fresh && hadRun { s.newGame() }
        session = s
    }
}

#Preview {
    ContentView()
}
