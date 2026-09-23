import SwiftUI

struct NotificationSettingsView: View {
    @Binding var isPresented: Bool
    @AppStorage(notifyArrivalKey) private var notifyArrival = true
    @AppStorage(notifyDelayKey) private var notifyDelay = true
    @AppStorage(notifyTroubleKey) private var notifyTrouble = true
    @AppStorage(notifyGroupUpdateKey) private var notifyGroupUpdate = true

    var body: some View {
        NavigationStack {
            Form {
                Section("通知を受け取る") {
                    Toggle("到着・出発の通知", isOn: $notifyArrival)
                    Toggle("遅れる連絡の通知", isOn: $notifyDelay)
                    Toggle("トラブル・停止の通知", isOn: $notifyTrouble)
                    Toggle("グループ更新の通知", isOn: $notifyGroupUpdate)
                }

                Section("通知の種類") {
                    SettingInfoRow(iconName: "flag.checkered", title: "到着・出発", text: "集合や移動開始の連絡を見逃しにくくします。")
                    SettingInfoRow(iconName: "clock.fill", title: "遅れる連絡", text: "合流時間が変わった時に気づきやすくします。")
                    SettingInfoRow(iconName: "exclamationmark.triangle.fill", title: "トラブル・停止", text: "困った時の連絡を優先して確認できます。")
                    SettingInfoRow(iconName: "person.3.fill", title: "グループ更新", text: "メンバーやグループの変更を確認できます。")
                }

                Section("位置情報") {
                    SettingInfoRow(iconName: "location.fill", title: "今ここにいる", text: "チャット画面から現在地リンクを送れます。")
                    SettingInfoRow(iconName: "hand.raised.fill", title: "許可が必要", text: "初回だけ位置情報の許可を求めます。")
                }
            }
            .navigationTitle("通知設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("閉じる") {
                        isPresented = false
                    }
                }
            }
        }
    }
}

struct SettingInfoRow: View {
    let iconName: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: iconName)
                .foregroundColor(.orange)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text(text)
                    .font(.caption)
                    .foregroundColor(.gray)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }
}
