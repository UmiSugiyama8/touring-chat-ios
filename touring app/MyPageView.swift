import SwiftUI

struct MyPageView: View {
    @Binding var displayName: String
    @Binding var profileColorRawValue: String
    @Binding var profileIconRawValue: String
    let groups: [TouringGroup]
    @ObservedObject var firebaseService: FirebaseGroupService
    @Environment(\.dismiss) var dismiss

    @State private var showingProfileEditor = false
    @State private var showingNotificationSettings = false
    @State private var showingQuickMessageSettings = false
    @State private var showingHelp = false

    private let menuItems: [MyPageMenuItem] = [
        MyPageMenuItem(title: "プロフィール編集", systemImage: "pencil.circle.fill", color: .orange),
        MyPageMenuItem(title: "定型メッセージ編集", systemImage: "text.bubble.fill", color: .purple),
        MyPageMenuItem(title: "通知設定", systemImage: "bell.circle.fill", color: .blue),
        MyPageMenuItem(title: "利用上の注意", systemImage: "shield.lefthalf.filled", color: .red),
        MyPageMenuItem(title: "ヘルプ", systemImage: "questionmark.circle.fill", color: .green)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill((ProfileColorOption(rawValue: profileColorRawValue)?.color ?? .orange).opacity(0.2))
                                .frame(width: 96, height: 96)

                            Image(systemName: profileIconRawValue)
                                .font(.system(size: 42))
                                .foregroundColor(ProfileColorOption(rawValue: profileColorRawValue)?.color ?? .orange)
                        }

                        Text(displayName)
                            .font(.title2)
                            .fontWeight(.bold)

                        Text("ツーリングをもっと楽に")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .background(Color.orange.opacity(0.08))
                    .cornerRadius(18)
                    .padding(.horizontal)

                    HStack(spacing: 12) {
                        VStack(spacing: 8) {
                            Text("参加グループ")
                                .font(.caption)
                                .foregroundColor(.gray)
                            Text("\(groups.count)")
                                .font(.title)
                                .fontWeight(.bold)
                                .foregroundColor(.orange)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.systemBackground))
                        .cornerRadius(14)
                        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)

                        VStack(spacing: 8) {
                            Text("表示名")
                                .font(.caption)
                                .foregroundColor(.gray)
                            Text(displayName.isEmpty ? "未設定" : "設定済み")
                                .font(.headline)
                                .fontWeight(.bold)
                                .foregroundColor(.blue)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.systemBackground))
                        .cornerRadius(14)
                        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
                    }
                    .padding(.horizontal)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("メニュー")
                            .font(.headline)
                            .padding(.horizontal)

                        ForEach(menuItems) { item in
                            Button {
                                if item.title == "プロフィール編集" {
                                    showingProfileEditor = true
                                } else if item.title == "定型メッセージ編集" {
                                    showingQuickMessageSettings = true
                                } else if item.title == "通知設定" {
                                    showingNotificationSettings = true
                                } else if item.title == "利用上の注意" {
                                    showingHelp = true
                                } else if item.title == "ヘルプ" {
                                    showingHelp = true
                                }
                            } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: item.systemImage)
                                        .font(.title2)
                                        .foregroundColor(item.color)
                                        .frame(width: 30)

                                    Text(item.title)
                                        .font(.body)
                                        .foregroundColor(.primary)

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .foregroundColor(.gray)
                                }
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(14)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("アプリ情報")
                            .font(.headline)

                        Text("プロフィールや通知の設定を変更できます。")
                            .font(.body)
                            .foregroundColor(.gray)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(14)
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .navigationTitle("マイページ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingProfileEditor) {
                ProfileEditView(
                    displayName: $displayName,
                    profileColorRawValue: $profileColorRawValue,
                    profileIconRawValue: $profileIconRawValue,
                    isPresented: $showingProfileEditor,
                    firebaseService: firebaseService
                )
            }
            .sheet(isPresented: $showingNotificationSettings) {
                NotificationSettingsView(isPresented: $showingNotificationSettings)
            }
            .sheet(isPresented: $showingQuickMessageSettings) {
                QuickMessageSettingsView(isPresented: $showingQuickMessageSettings)
            }
            .sheet(isPresented: $showingHelp) {
                HelpView(isPresented: $showingHelp)
            }
        }
    }
}
