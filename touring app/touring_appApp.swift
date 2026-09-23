import SwiftUI
import FirebaseCore

@main
struct TouringApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            StartView()
        }
    }
}

struct ContentView: View {
    var body: some View {
        VStack {
            Text("ツーリングメッセージ")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("準備中...")
                .foregroundColor(.gray)
        }
        .padding()
    }
}
