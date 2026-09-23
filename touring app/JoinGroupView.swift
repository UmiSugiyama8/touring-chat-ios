import SwiftUI

struct JoinGroupView: View {
    @Binding var groups: [TouringGroup]
    @Binding var isPresented: Bool
    @ObservedObject var firebaseService: FirebaseGroupService
    let displayName: String
    let profileColorRawValue: String
    let profileIconRawValue: String
    @State private var groupCode = ""
    @State private var showJoinError = false
    @State private var joinErrorMessage = ""
    @State private var isSearching = false

    init(
        groups: Binding<[TouringGroup]>,
        isPresented: Binding<Bool>,
        firebaseService: FirebaseGroupService,
        displayName: String,
        profileColorRawValue: String,
        profileIconRawValue: String,
        initialGroupCode: String = ""
    ) {
        _groups = groups
        _isPresented = isPresented
        self.firebaseService = firebaseService
        self.displayName = displayName
        self.profileColorRawValue = profileColorRawValue
        self.profileIconRawValue = profileIconRawValue
        _groupCode = State(initialValue: initialGroupCode)
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("6桁のグループコードを入力")
                    .font(.body)
                    .foregroundColor(.gray)
                
                TextField("000000", text: $groupCode)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numberPad)
                    .padding()
                
                Button(action: {
                    let trimmedCode = groupCode.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmedCode.count != 6 {
                        joinErrorMessage = "参加コードは6桁で入力してください"
                        showJoinError = true
                        return
                    }

                    isSearching = true
                    firebaseService.findGroupByCode(
                        trimmedCode,
                        displayName: displayName,
                        profileColorRawValue: profileColorRawValue,
                        profileIconRawValue: profileIconRawValue
                    ) { foundGroup in
                        isSearching = false

                        guard let foundGroup = foundGroup else {
                            joinErrorMessage = "その参加コードのグループは存在しません"
                            showJoinError = true
                            return
                        }

                        if !groups.contains(where: { $0.id == foundGroup.id }) {
                            groups.append(foundGroup)
                        }

                        isPresented = false
                    }
                }) {
                    Text(isSearching ? "検索中..." : "参加する")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(8)
                }
                .padding()
                .disabled(groupCode.count != 6 || isSearching)
                
                Spacer()
            }
            .navigationTitle("グループに参加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("キャンセル") {
                        isPresented = false
                    }
                }
            }
            .alert("参加できません", isPresented: $showJoinError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(joinErrorMessage)
            }
        }
    }

}
