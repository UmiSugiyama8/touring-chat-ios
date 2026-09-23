import SwiftUI

struct CreateGroupView: View {
    @Binding var isPresented: Bool
    @ObservedObject var firebaseService: FirebaseGroupService
    let displayName: String
    let profileColorRawValue: String
    let profileIconRawValue: String
    @State private var groupName = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                TextField("グループ名", text: $groupName)
                    .textFieldStyle(.roundedBorder)
                    .padding()

                Button(action: {
                    let trimmed = groupName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        firebaseService.createGroup(
                            name: trimmed,
                            displayName: displayName,
                            profileColorRawValue: profileColorRawValue,
                            profileIconRawValue: profileIconRawValue
                        ) {
                            isPresented = false
                        }
                    }
                }) {
                    Text("作成")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .cornerRadius(8)
                }
                .padding()
                .disabled(groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

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
        }
    }
}
