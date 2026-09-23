import SwiftUI
import Combine
import WatchConnectivity

struct WatchGroup: Identifiable, Hashable {
    let id: String
    let name: String
    let memberCount: Int
    let arrivedCount: Int
    let lastMessageText: String
    let meetingPlaceName: String
    let meetingTime: Date?

    var arrivalText: String {
        "\(arrivedCount)/\(memberCount) 到着"
    }

    var avatarText: String {
        String(name.prefix(1))
    }
}

struct WatchQuickMessage: Identifiable {
    let id = UUID()
    let title: String
    let systemImage: String
    let color: Color
}

final class WatchConnectivityViewModel: NSObject, ObservableObject {
    @Published var groups: [WatchGroup] = []
    @Published var statusText = "iPhoneアプリを開くと同期されます"
    @Published var lastSentMessage = ""

    private let session: WCSession? = WCSession.isSupported() ? WCSession.default : nil

    override init() {
        super.init()
        activate()
    }

    func activate() {
        guard let session else { return }
        session.delegate = self
        session.activate()
    }

    func send(_ message: WatchQuickMessage, to group: WatchGroup) {
        let payload: [String: Any] = [
            "groupID": group.id,
            "text": message.title
        ]

        if let session, session.isReachable {
            statusText = "送信中..."
            session.sendMessage(payload) { reply in
                DispatchQueue.main.async {
                    let success = reply["success"] as? Bool ?? false
                    self.statusText = success ? "\(message.title) を送信しました" : "送信できませんでした"
                    self.lastSentMessage = success ? message.title : ""
                }
            } errorHandler: { error in
                DispatchQueue.main.async {
                    self.statusText = "送信できませんでした"
                    self.lastSentMessage = ""
                    print("Failed to send watch message: \(error)")
                }
            }
        } else {
            session?.transferUserInfo(payload)
            statusText = "iPhoneに送信予約しました"
            lastSentMessage = message.title
        }
    }

    private func updateGroups(from context: [String: Any]) {
        guard let payload = context["groups"] as? [[String: Any]] else { return }

        groups = payload.compactMap { item in
            guard let id = item["id"] as? String,
                  let name = item["name"] as? String else { return nil }

            let meetingTime: Date?
            if let interval = item["meetingTime"] as? TimeInterval {
                meetingTime = Date(timeIntervalSince1970: interval)
            } else {
                meetingTime = nil
            }

            return WatchGroup(
                id: id,
                name: name,
                memberCount: item["memberCount"] as? Int ?? 0,
                arrivedCount: item["arrivedCount"] as? Int ?? 0,
                lastMessageText: item["lastMessageText"] as? String ?? "",
                meetingPlaceName: item["meetingPlaceName"] as? String ?? "",
                meetingTime: meetingTime
            )
        }

        statusText = groups.isEmpty ? "グループがありません" : "同期済み"
    }
}

extension WatchConnectivityViewModel: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            if let error {
                self.statusText = "同期を開始できませんでした"
                print("Watch activation failed: \(error)")
            } else if !session.receivedApplicationContext.isEmpty {
                self.updateGroups(from: session.receivedApplicationContext)
            }
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        DispatchQueue.main.async {
            self.updateGroups(from: applicationContext)
        }
    }
}

struct ContentView: View {
    @StateObject private var viewModel = WatchConnectivityViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                if viewModel.groups.isEmpty {
                    EmptyWatchState(statusText: viewModel.statusText)
                } else {
                    VStack(spacing: 8) {
                        HStack {
                            Text("トーク")
                                .font(.system(size: 22, weight: .bold))

                            Spacer()

                            Text(viewModel.statusText)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 2)

                        ForEach(viewModel.groups) { group in
                            NavigationLink {
                                WatchGroupDetailView(group: group, viewModel: viewModel)
                            } label: {
                                WatchGroupCard(group: group)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.bottom, 8)
                }
            }
            .navigationTitle("トーク")
        }
    }
}

struct EmptyWatchState: View {
    let statusText: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "iphone.and.arrow.forward")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.orange)

            Text("iPhoneでtouring appを開くと、グループが表示されます")
                .font(.system(size: 17, weight: .semibold))
                .multilineTextAlignment(.center)
                .lineLimit(4)

            Text(statusText)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 150)
        .padding(.horizontal, 8)
    }
}

struct WatchGroupCard: View {
    let group: WatchGroup

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.green)
                    .frame(width: 42, height: 42)

                Text(group.avatarText)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(group.name)
                        .font(.system(size: 18, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Spacer(minLength: 0)

                    Text(group.arrivalText)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.green)
                }

                Text(group.lastMessageText.isEmpty ? "まだメッセージはありません" : group.lastMessageText)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 9)
        .padding(.horizontal, 8)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

struct WatchGroupDetailView: View {
    let group: WatchGroup
    @ObservedObject var viewModel: WatchConnectivityViewModel

    private let quickMessages = [
        WatchQuickMessage(title: "出発する", systemImage: "flag.fill", color: .orange),
        WatchQuickMessage(title: "到着", systemImage: "checkmark.circle.fill", color: .green),
        WatchQuickMessage(title: "遅れる", systemImage: "clock.badge.exclamationmark.fill", color: .red),
        WatchQuickMessage(title: "止まる", systemImage: "exclamationmark.triangle.fill", color: .red),
        WatchQuickMessage(title: "はぐれた", systemImage: "location.slash.fill", color: .red),
        WatchQuickMessage(title: "今ここにいる", systemImage: "location.fill", color: .blue)
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                WatchChatHeader(group: group)

                WatchChatBubble(text: group.lastMessageText.isEmpty ? "定型メッセージを選んで送信できます" : group.lastMessageText, isMine: false)

                if !viewModel.lastSentMessage.isEmpty {
                    WatchChatBubble(text: viewModel.lastSentMessage, isMine: true)
                }

                Text("クイック返信")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)

                ForEach(quickMessages) { message in
                    WatchQuickMessageButton(message: message) {
                        viewModel.send(message, to: group)
                    }
                }

                if !viewModel.lastSentMessage.isEmpty {
                    Text(viewModel.statusText)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 2)
                }
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 8)
        }
        .navigationTitle(group.name)
    }
}

struct WatchChatHeader: View {
    let group: WatchGroup

    var body: some View {
        HStack(spacing: 9) {
            ZStack {
                Circle()
                    .fill(Color.green)
                    .frame(width: 34, height: 34)

                Text(group.avatarText)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(group.name)
                    .font(.system(size: 18, weight: .bold))
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                    Text(group.arrivalText)
                }
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.green)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 2)
    }
}

struct WatchChatBubble: View {
    let text: String
    let isMine: Bool

    var body: some View {
        HStack {
            if isMine {
                Spacer(minLength: 28)
            }

            Text(text)
                .font(.system(size: 16, weight: .semibold))
                .lineLimit(4)
                .multilineTextAlignment(.leading)
                .padding(.vertical, 9)
                .padding(.horizontal, 11)
                .background(isMine ? Color.green : Color.white.opacity(0.16))
                .foregroundColor(isMine ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 15))

            if !isMine {
                Spacer(minLength: 28)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct WatchQuickMessageButton: View {
    let message: WatchQuickMessage
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: message.systemImage)
                    .font(.system(size: 18, weight: .bold))
                    .frame(width: 24)

                Text(message.title)
                    .font(.system(size: 18, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.horizontal, 10)
            .background(buttonColor)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private var buttonColor: Color {
        message.title == "到着" || message.title == "出発する" ? .green : message.color
    }
}

#Preview {
    ContentView()
}
