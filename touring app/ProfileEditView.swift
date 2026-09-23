import SwiftUI

struct ProfileEditView: View {
    @Binding var displayName: String
    @Binding var profileColorRawValue: String
    @Binding var profileIconRawValue: String
    @Binding var isPresented: Bool
    @ObservedObject var firebaseService: FirebaseGroupService
    @State private var editedName = ""
    @State private var selectedColorRawValue = ProfileColorOption.orange.rawValue
    @State private var selectedIconRawValue = ProfileIconOption.tortoiseFill.rawValue
    @State private var showingSavedAlert = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Text("表示名を編集")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("ツーリング仲間に表示される名前を変更できます")
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.gray)

                    TextField("新しい表示名を入力", text: $editedName)
                        .textFieldStyle(.roundedBorder)
                        .padding(.horizontal)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("アイコンカラー")
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            ForEach(ProfileColorOption.allCases) { option in
                                Button {
                                    selectedColorRawValue = option.rawValue
                                } label: {
                                    VStack(spacing: 8) {
                                        Circle()
                                            .fill(option.color)
                                            .frame(width: 44, height: 44)
                                            .overlay {
                                                if selectedColorRawValue == option.rawValue {
                                                    Image(systemName: "checkmark")
                                                        .font(.headline)
                                                        .foregroundColor(.white)
                                                }
                                            }

                                        Text(option.displayName)
                                            .font(.caption)
                                            .foregroundColor(.primary)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(Color(.systemGray6))
                                    .cornerRadius(12)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("アイコン")
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            ForEach(ProfileIconOption.allCases) { option in
                                Button {
                                    selectedIconRawValue = option.rawValue
                                } label: {
                                    VStack(spacing: 8) {
                                        ZStack {
                                            Circle()
                                                .fill((ProfileColorOption(rawValue: selectedColorRawValue)?.color ?? .orange).opacity(0.2))
                                                .frame(width: 52, height: 52)

                                            Image(systemName: option.rawValue)
                                                .font(.title2)
                                                .foregroundColor(ProfileColorOption(rawValue: selectedColorRawValue)?.color ?? .orange)
                                        }
                                        .overlay {
                                            if selectedIconRawValue == option.rawValue {
                                                RoundedRectangle(cornerRadius: 16)
                                                    .stroke(ProfileColorOption(rawValue: selectedColorRawValue)?.color ?? .orange, lineWidth: 2)
                                            }
                                        }

                                        Text(option.displayName)
                                            .font(.caption)
                                            .foregroundColor(.primary)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(Color(.systemGray6))
                                    .cornerRadius(12)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.top, 30)
                .padding(.bottom, 20)
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    let trimmed = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    displayName = trimmed
                    UserDefaults.standard.set(trimmed, forKey: displayNameKey)
                    profileColorRawValue = selectedColorRawValue
                    UserDefaults.standard.set(selectedColorRawValue, forKey: profileColorKey)
                    profileIconRawValue = selectedIconRawValue
                    UserDefaults.standard.set(selectedIconRawValue, forKey: profileIconKey)

                    firebaseService.updateMyProfileInJoinedGroups(
                        displayName: trimmed,
                        profileColorRawValue: selectedColorRawValue,
                        profileIconRawValue: selectedIconRawValue
                    )

                    showingSavedAlert = true
                } label: {
                    Text("保存")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange)
                        .cornerRadius(10)
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
                .background(.regularMaterial)
                .disabled(editedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .navigationTitle("プロフィール編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("キャンセル") {
                        isPresented = false
                    }
                }
            }
            .onAppear {
                editedName = displayName
                selectedColorRawValue = profileColorRawValue
                selectedIconRawValue = profileIconRawValue
            }
            .alert("保存しました", isPresented: $showingSavedAlert) {
                Button("OK") {
                    isPresented = false
                }
            } message: {
                Text("表示名を更新しました")
            }
        }
    }
}
