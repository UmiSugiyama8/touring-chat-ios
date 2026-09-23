import SwiftUI

struct StartView: View {
    @State private var displayName = UserDefaults.standard.string(forKey: displayNameKey) ?? ""
    @State private var profileColorRawValue = UserDefaults.standard.string(forKey: profileColorKey) ?? ProfileColorOption.orange.rawValue
    @State private var profileIconRawValue = UserDefaults.standard.string(forKey: profileIconKey) ?? ProfileIconOption.tortoiseFill.rawValue
    @State private var isLoggedIn = false
    @State private var showingNameInput = true
    @State private var showingTutorial = !UserDefaults.standard.bool(forKey: hasSeenTutorialKey) || UserDefaults.standard.string(forKey: termsAgreementVersionKey) != currentTermsAgreementVersion
    @ObservedObject private var watchConnectivityManager = PhoneWatchConnectivityManager.shared
    
    var body: some View {
        if showingNameInput {
            VStack(spacing: 20) {
                Text("🏍️")
                    .font(.system(size: 60))
                    .foregroundColor(.orange)
                
                Text("ようこそ！")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("ツーリング仲間から見えるあなたの名前を\n入力してください")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.gray)
                
                TextField("表示名を入力", text: $displayName)
                    .textFieldStyle(.roundedBorder)
                    .padding()
                
                Button(action: {
                    let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        displayName = trimmed
                        UserDefaults.standard.set(trimmed, forKey: displayNameKey)
                        isLoggedIn = true
                        showingNameInput = false
                    }
                }) {
                    Text("はじめる")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange)
                        .cornerRadius(8)
                }
                .padding()
                
                Spacer()
            }
            .padding()
            .onAppear {
                LocalNotificationManager.shared.requestPermission()
                FirebaseAuthService.signInIfNeeded()
                watchConnectivityManager.configure(displayName: displayName)

                let savedName = UserDefaults.standard.string(forKey: displayNameKey) ?? ""
                if !savedName.isEmpty {
                    displayName = savedName
                    watchConnectivityManager.updateDisplayName(savedName)
                    isLoggedIn = true
                    showingNameInput = false
                }
            }
        } else {
            GroupsListView(displayName: $displayName, profileColorRawValue: $profileColorRawValue, profileIconRawValue: $profileIconRawValue)
                .sheet(isPresented: $showingTutorial) {
                    TutorialView(isPresented: $showingTutorial)
                }
                .onAppear {
                    FirebaseAuthService.signInIfNeeded()
                    watchConnectivityManager.configure(displayName: displayName)
                }
                .onChange(of: displayName) { _, newDisplayName in
                    watchConnectivityManager.updateDisplayName(newDisplayName)
                }
        }
    }
}

struct TutorialView: View {
    @Binding var isPresented: Bool
    @State private var acceptedTerms = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("利用上の同意")
                        .font(.title2)
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text("ツーリングチャットを安全に使うため、以下の内容を確認してください。")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .fixedSize(horizontal: false, vertical: true)

                    TermsCard()

                    Toggle(isOn: $acceptedTerms) {
                        Text("上記の内容を確認し、安全に停止して周囲の安全が確認できる時だけ利用することに同意します")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .toggleStyle(.switch)
                    .padding()
                    .background(acceptedTerms ? Color.green.opacity(0.1) : Color(.secondarySystemBackground))
                    .cornerRadius(14)
                }
                .padding()
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    guard acceptedTerms else { return }
                    UserDefaults.standard.set(true, forKey: hasSeenTutorialKey)
                    UserDefaults.standard.set(currentTermsAgreementVersion, forKey: termsAgreementVersionKey)
                    UserDefaults.standard.set(Date(), forKey: "termsAgreedAt")
                    isPresented = false
                } label: {
                    Text("同意してはじめる")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(acceptedTerms ? Color.orange : Color.gray.opacity(0.45))
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .disabled(!acceptedTerms)
                .padding()
                .background(Color(.systemBackground))
            }
            .navigationTitle("確認")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct TermsCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            TermsRow(
                iconName: "exclamationmark.triangle.fill",
                iconColor: .red,
                title: "運転中の操作禁止",
                text: "バイクや車の運転中にスマートフォンやApple Watchを操作しないでください。操作は赤信号や一時停止中など、完全に停止し、周囲の安全が確認できる時だけ行ってください。"
            )

            TermsRow(
                iconName: "location.fill",
                iconColor: .blue,
                title: "位置情報の取り扱い",
                text: "現在地共有や集合場所設定を利用する場合、位置情報がグループ内のメンバーに共有されることがあります。共有する前に、送信先と内容を確認してください。"
            )

            TermsRow(
                iconName: "text.bubble.fill",
                iconColor: .green,
                title: "メッセージとグループ情報",
                text: "表示名、グループ情報、メッセージ内容、到着状況などは、アプリ機能の提供のためFirebase Firestoreに保存されます。開発者は通常メッセージを閲覧しませんが、不具合対応や不正利用調査など必要な場合に限り確認することがあります。"
            )

            TermsRow(
                iconName: "shield.lefthalf.filled",
                iconColor: .orange,
                title: "利用者の責任",
                text: "本アプリはツーリング中の連絡を補助するものです。交通ルール、安全確認、端末操作の判断は利用者自身の責任で行ってください。"
            )

            TermsRow(
                iconName: "doc.text.fill",
                iconColor: .gray,
                title: "規約とプライバシーポリシー",
                text: "アプリの利用により、利用上の注意、免責事項、プライバシーポリシーの内容に同意したものとします。内容は必要に応じて変更される場合があります。"
            )
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(14)
    }
}

struct TermsRow: View {
    let iconName: String
    let iconColor: Color
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: iconName)
                .font(.title3)
                .foregroundColor(iconColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(text)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct TutorialRow: View {
    let iconName: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: iconName)
                .font(.title2)
                .foregroundColor(.orange)
                .frame(width: 34)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(text)
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
