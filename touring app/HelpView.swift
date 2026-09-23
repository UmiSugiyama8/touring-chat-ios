import SwiftUI

struct HelpView: View {
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HelpSection(title: "利用上の注意") {
                        TermsCard()
                    }

                    HelpSection(title: "このアプリについて") {
                        HelpRow(iconName: "message.fill", title: "状況共有", text: "仲間に今の状況を伝えます。")
                        HelpRow(iconName: "figure.outdoor.cycle", title: "ツーリング向け", text: "出発、到着、遅れを短く送れます。")
                        HelpRow(iconName: "exclamationmark.triangle.fill", title: "トラブル連絡", text: "停止や困りごともすぐ共有できます。")
                    }

                    HelpSection(title: "使い方") {
                        HelpRow(iconName: "person.fill", title: "1. 表示名を設定", text: "仲間に見える名前を決めます。")
                        HelpRow(iconName: "person.3.fill", title: "2. グループ参加", text: "作成するか、6桁コードで入ります。")
                        HelpRow(iconName: "bubble.left.and.bubble.right.fill", title: "3. メッセージ送信", text: "自由入力か定型文で送れます。")
                        HelpRow(iconName: "location.fill", title: "4. 現在地を共有", text: "今ここにいるボタンで場所を送れます。")
                        HelpRow(iconName: "gearshape.fill", title: "5. 設定変更", text: "マイページから変更できます。")
                    }

                    HelpSection(title: "グループ一覧") {
                        HelpRow(iconName: "text.bubble.fill", title: "最後の連絡", text: "最近のメッセージを一覧で確認できます。")
                        HelpRow(iconName: "person.2.fill", title: "参加人数", text: "グループの人数が表示されます。")
                        HelpRow(iconName: "number", title: "参加コード", text: "コードも一覧から確認できます。")
                    }

                    HelpSection(title: "困ったとき") {
                        HelpRow(iconName: "number", title: "コードで入れない", text: "6桁かどうか確認してください。")
                        HelpRow(iconName: "arrow.clockwise", title: "反映されない", text: "保存し直して画面を閉じます。")
                        HelpRow(iconName: "location.slash.fill", title: "場所を送れない", text: "iPhoneの位置情報許可を確認してください。")
                    }
                }
                .padding()
            }
            .navigationTitle("ヘルプ")
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

struct HelpSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            VStack(spacing: 10) {
                content
            }
        }
    }
}

struct HelpRow: View {
    let iconName: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: iconName)
                .font(.body)
                .foregroundColor(.orange)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text(text)
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}
