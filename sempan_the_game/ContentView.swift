import SwiftUI

struct ContentView: View {
    @State private var store = SaveStore()
    @State private var session: GameSession?

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
        .onAppear { Sound.shared.updateMusic() }
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
