import SwiftUI

struct CreateGroupView: View {
    @Binding var isPresented: Bool
    @ObservedObject var firebaseService: FirebaseGroupService
    let displayName: String
    let profileColorRawValue: String
    let profileIconRawValue: String
    @State private var groupName = ""
    @State private var isCreating = false
    @State private var showCreateError = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                TextField("グループ名", text: $groupName)
                    .textFieldStyle(.roundedBorder)
                    .padding()

                Button(action: {
                    let trimmed = groupName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        isCreating = true
                        firebaseService.createGroup(
                            name: trimmed,
                            displayName: displayName,
                            profileColorRawValue: profileColorRawValue,
                            profileIconRawValue: profileIconRawValue
                        ) { success in
                            isCreating = false
                            if success {
                                isPresented = false
                            } else {
                                showCreateError = true
                            }
                        }
                    }
                }) {
                    Text(isCreating ? "作成中..." : "作成")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .cornerRadius(8)
                }
                .padding()
                .disabled(groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCreating)

                Spacer()
            }
            .navigationTitle("グループを作成")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("キャンセル") {
                        isPresented = false
                    }
                }
            }
            .alert("作成できません", isPresented: $showCreateError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("通信状況を確認して、もう一度お試しください。")
            }
        }
    }
}
