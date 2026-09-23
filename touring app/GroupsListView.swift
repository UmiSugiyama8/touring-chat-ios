import SwiftUI

struct GroupsListView: View {
    @Binding var displayName: String
    @Binding var profileColorRawValue: String
    @Binding var profileIconRawValue: String
    @State private var groups: [TouringGroup] = []
    @State private var showingCreateGroup = false
    @State private var showingJoinGroup = false
    @State private var showingMyPage = false
    @State private var inviteCodeFromURL = ""
    @State private var copiedCodeMessage: String?
    @StateObject private var firebaseService = FirebaseGroupService()
    @ObservedObject private var watchConnectivityManager = PhoneWatchConnectivityManager.shared

    private var updatedTimeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d HH:mm"
        return formatter
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                VStack {
                if groups.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "person.2")
                            .font(.system(size: 60))
                            .foregroundColor(.orange)

                        Text("グループがまだありません")
                            .font(.headline)

                        Text("新しいグループを作成するか、\nコードで参加してください")
                            .font(.body)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.gray)
                    }
                    .frame(maxHeight: .infinity, alignment: .center)
                } else {
                    List(groups) { group in
                        NavigationLink(destination: GroupDetailView(group: group, displayName: displayName, firebaseService: firebaseService)) {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(alignment: .firstTextBaseline) {
                                    HStack(spacing: 6) {
                                        if GroupReadState.hasUnread(group) {
                                            Circle()
                                                .fill(Color.red)
                                                .frame(width: 8, height: 8)
                                        }

                                        Text(group.name)
                                            .font(.headline)
                                    }

                                    Spacer()

                                    if let lastMessageAt = group.lastMessageAt {
                                        Text(updatedTimeFormatter.string(from: lastMessageAt))
                                            .font(.caption2)
                                            .foregroundColor(.gray)
                                    }
                                }

                                Text(group.lastMessageText.isEmpty ? "まだメッセージはありません" : group.lastMessageText)
                                    .font(.subheadline)
                                    .foregroundColor(group.lastMessageText.isEmpty ? .gray : .primary)
                                    .lineLimit(1)

                                HStack(spacing: 8) {
                                    Label("\(group.memberCount)人", systemImage: "person.2.fill")
                                    Label("\(group.arrivedCount)/\(group.memberCount) 到着", systemImage: "checkmark.circle.fill")
                                        .foregroundColor(group.arrivedCount == group.memberCount && group.memberCount > 0 ? .green : .gray)
                                    Button {
                                        copyGroupCode(group.code)
                                    } label: {
                                        Label(group.code, systemImage: "doc.on.doc")
                                    }
                                    .buttonStyle(.plain)

                                    if !group.meetingPlaceName.isEmpty {
                                        Label(group.meetingPlaceName, systemImage: "mappin.and.ellipse")
                                            .lineLimit(1)
                                    }
                                }
                                .font(.caption)
                                .foregroundColor(.gray)
                            }
                            .padding(.vertical, 8)
                        }
                        .listRowBackground(GroupReadState.hasUnread(group) ? Color.orange.opacity(0.08) : Color(.systemBackground))
                    }
                    .listStyle(.insetGrouped)
                }

                HStack(spacing: 10) {
                    Button(action: { showingCreateGroup = true }) {
                        Label("作成", systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }

                    Button(action: { showingJoinGroup = true }) {
                        Label("参加", systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                }
                .padding()
            }

                if let copiedCodeMessage {
                    Text(copiedCodeMessage)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.78))
                        .cornerRadius(18)
                        .padding(.bottom, 92)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: copiedCodeMessage)
            .navigationTitle("グループ一覧")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingMyPage = true
                    } label: {
                        Image(systemName: profileIconRawValue)
                            .font(.title2)
                            .foregroundColor(ProfileColorOption(rawValue: profileColorRawValue)?.color ?? .orange)
                    }
                }
            }
            .sheet(isPresented: $showingCreateGroup) {
                CreateGroupView(
                    isPresented: $showingCreateGroup,
                    firebaseService: firebaseService,
                    displayName: displayName,
                    profileColorRawValue: profileColorRawValue,
                    profileIconRawValue: profileIconRawValue
                )
            }
            .sheet(isPresented: $showingJoinGroup) {
                JoinGroupView(
                    groups: $groups,
                    isPresented: $showingJoinGroup,
                    firebaseService: firebaseService,
                    displayName: displayName,
                    profileColorRawValue: profileColorRawValue,
                    profileIconRawValue: profileIconRawValue,
                    initialGroupCode: inviteCodeFromURL
                )
            }
            .sheet(isPresented: $showingMyPage) {
                MyPageView(
                    displayName: $displayName,
                    profileColorRawValue: $profileColorRawValue,
                    profileIconRawValue: $profileIconRawValue,
                    groups: groups,
                    firebaseService: firebaseService
                )
            }
            .onAppear {
                watchConnectivityManager.configure(displayName: displayName)
                firebaseService.listenGroups { fetchedGroups in
                    groups = fetchedGroups
                    watchConnectivityManager.sendGroups(fetchedGroups)
                }
            }
            .onChange(of: showingCreateGroup) { _, isShowing in
                if !isShowing {
                    firebaseService.listenGroups { fetchedGroups in
                        groups = fetchedGroups
                        watchConnectivityManager.sendGroups(fetchedGroups)
                    }
                }
            }
            .onChange(of: showingJoinGroup) { _, isShowing in
                if !isShowing {
                    inviteCodeFromURL = ""
                    firebaseService.listenGroups { fetchedGroups in
                        groups = fetchedGroups
                        watchConnectivityManager.sendGroups(fetchedGroups)
                    }
                }
            }
            .onChange(of: displayName) { _, newDisplayName in
                watchConnectivityManager.updateDisplayName(newDisplayName)
            }
            .onOpenURL { url in
                guard let code = InviteLinkParser.code(from: url) else { return }
                inviteCodeFromURL = code
                showingJoinGroup = true
            }
        }
    }

    private func copyGroupCode(_ code: String) {
        UIPasteboard.general.string = code
        copiedCodeMessage = "コードをコピーしました"

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            if copiedCodeMessage == "コードをコピーしました" {
                copiedCodeMessage = nil
            }
        }
    }
}
