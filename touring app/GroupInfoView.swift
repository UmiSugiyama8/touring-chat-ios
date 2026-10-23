import SwiftUI
import CoreLocation
import UIKit

struct GroupInfoView: View {
    let group: TouringGroup
    @ObservedObject var firebaseService: FirebaseGroupService
    let displayName: String
    @Binding var showingLeaveConfirm: Bool
    @Binding var isPresented: Bool
    let onDeleteGroup: () -> Void
    @State private var members: [GroupMember] = []
    @State private var showingRename = false
    @State private var showingDeleteConfirm = false
    @State private var isDeleting = false
    @State private var showingDeleteError = false
    @State private var showingMeetingEditor = false
    @State private var editedGroupName = ""
    @State private var copiedCodeMessage: String?

    private var memberCountText: String {
        "\(members.count)人"
    }

    private var isOwner: Bool {
        if !group.ownerAuthUID.isEmpty {
            return group.ownerAuthUID == FirebaseAuthService.currentUID
        }
        return group.ownerDeviceID == currentDeviceID()
    }

    private var currentMember: GroupMember? {
        members.first { $0.id == FirebaseAuthService.currentUID }
    }

    private var meetingTimeText: String {
        guard let meetingTime = group.meetingTime else { return "未設定" }
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d HH:mm"
        return formatter.string(from: meetingTime)
    }

    private var inviteURL: URL {
        InviteLinkParser.inviteURL(for: group.code)
    }

    private var inviteMessage: String {
        "\(group.name) に参加してね。リンクを開くと参加コードが入力されます。"
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                List {
                    Section("集合場所") {
                        if group.meetingPlaceName.isEmpty {
                            Text("まだ集合場所が設定されていません")
                                .foregroundColor(.gray)
                        } else {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(group.meetingPlaceName)
                                    .font(.headline)

                                Text("集合時間: \(meetingTimeText)")
                                    .font(.caption)
                                    .foregroundColor(.gray)

                                if let url = safeAppleMapsURL(from: group.meetingPlaceURL) {
                                    Button {
                                        UIApplication.shared.open(url)
                                    } label: {
                                        Label("地図で開く", systemImage: "map.fill")
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }

                        Button {
                            showingMeetingEditor = true
                        } label: {
                            Label(group.meetingPlaceName.isEmpty ? "集合場所を設定" : "集合場所を変更", systemImage: "mappin.and.ellipse")
                        }
                    }

                    Section("参加コード") {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(group.code)
                                    .font(.system(size: 32, weight: .bold, design: .rounded))
                                    .textSelection(.enabled)

                                Text("この6桁コードを相手に教えると参加できます")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }

                            Spacer()

                            Button {
                                copyGroupCode()
                            } label: {
                                Image(systemName: "doc.on.doc")
                            }
                        }
                        .padding(.vertical, 6)

                        ShareLink(item: inviteURL, subject: Text("\(group.name) の招待"), message: Text(inviteMessage)) {
                            Label("招待URLを共有", systemImage: "square.and.arrow.up")
                        }
                    }

                    Section("参加メンバー \(memberCountText)") {
                        if let currentMember {
                            Button {
                                firebaseService.updateArrivalStatus(groupID: group.id, isArrived: !currentMember.isArrived)
                            } label: {
                                Label(currentMember.isArrived ? "未到着に戻す" : "到着済みにする", systemImage: currentMember.isArrived ? "arrow.uturn.backward.circle.fill" : "checkmark.circle.fill")
                                    .foregroundColor(currentMember.isArrived ? .orange : .green)
                            }
                        }

                        if members.isEmpty {
                            Text("まだメンバー情報がありません")
                                .foregroundColor(.gray)
                        } else {
                            ForEach(members) { member in
                                let isMe = member.id == FirebaseAuthService.currentUID

                                HStack(spacing: 12) {
                                    ZStack(alignment: .bottomTrailing) {
                                        Circle()
                                            .fill((ProfileColorOption(rawValue: member.profileColorRawValue)?.color ?? .orange).opacity(0.18))
                                            .frame(width: 42, height: 42)

                                        Image(systemName: member.profileIconRawValue)
                                            .font(.system(size: 22))
                                            .foregroundColor(ProfileColorOption(rawValue: member.profileColorRawValue)?.color ?? .orange)

                                        if isMe {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.caption)
                                                .foregroundColor(.blue)
                                                .background(Circle().fill(Color(.systemBackground)))
                                        }
                                    }

                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            Text(member.displayName)
                                                .font(.body)
                                                .fontWeight(isMe ? .bold : .regular)

                                            if isMe {
                                                Text("あなた")
                                                    .font(.caption2)
                                                    .fontWeight(.bold)
                                                    .foregroundColor(.white)
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(Color.blue)
                                                    .cornerRadius(6)
                                            }

                                            if member.isArrived {
                                                Text("到着済み")
                                                    .font(.caption2)
                                                    .fontWeight(.bold)
                                                    .foregroundColor(.white)
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(Color.green)
                                                    .cornerRadius(6)
                                            }
                                        }
                                    }

                                    Spacer()
                                }
                                .padding(.vertical, 4)
                                .listRowBackground(isMe ? Color.blue.opacity(0.08) : Color.clear)
                            }
                        }
                    }

                    if isOwner {
                        Section("管理") {
                            Button {
                                editedGroupName = group.name
                                showingRename = true
                            } label: {
                                Label("グループ名を変更", systemImage: "pencil")
                            }

                            Button(role: .destructive) {
                                showingDeleteConfirm = true
                            } label: {
                                Label(isDeleting ? "削除中…" : "グループを削除", systemImage: "trash")
                            }
                            .disabled(isDeleting)
                        }
                    }

                    if !isOwner {
                        Section {
                            Button(role: .destructive) {
                                isPresented = false
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                    showingLeaveConfirm = true
                                }
                            } label: {
                                HStack {
                                    Spacer()
                                    Text("このグループを退出")
                                        .fontWeight(.semibold)
                                    Spacer()
                                }
                            }
                        }
                    }
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
                        .padding(.bottom, 28)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: copiedCodeMessage)
            .navigationTitle(group.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("閉じる") {
                        isPresented = false
                    }
                }
            }
            .onAppear {
                firebaseService.listenMembers(for: group.id) { fetchedMembers in
                    members = fetchedMembers
                }
            }
            .alert("グループ名を変更", isPresented: $showingRename) {
                TextField("グループ名", text: $editedGroupName)
                Button("キャンセル", role: .cancel) {}
                Button("保存") {
                    let trimmed = editedGroupName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    firebaseService.updateGroupName(groupID: group.id, newName: trimmed)
                }
            } message: {
                Text("新しいグループ名を入力してください。")
            }
            .alert("グループを削除しますか？", isPresented: $showingDeleteConfirm) {
                Button("キャンセル", role: .cancel) {}
                Button("削除", role: .destructive) {
                    isDeleting = true
                    firebaseService.deleteGroup(groupID: group.id) { success in
                        isDeleting = false
                        guard success else {
                            showingDeleteError = true
                            return
                        }
                        isPresented = false
                        onDeleteGroup()
                    }
                }
            } message: {
                Text("この操作は取り消せません。グループとメッセージ、メンバー情報を削除します。")
            }
            .alert("削除を完了できませんでした", isPresented: $showingDeleteError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("通信状況を確認して、もう一度グループを削除してください。削除中のグループでは新規投稿・参加を停止します。")
            }
            .sheet(isPresented: $showingMeetingEditor) {
                MeetingInfoEditView(group: group, firebaseService: firebaseService, isPresented: $showingMeetingEditor)
            }
        }
    }

    private func copyGroupCode() {
        UIPasteboard.general.string = group.code
        copiedCodeMessage = "コードをコピーしました"

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            if copiedCodeMessage == "コードをコピーしました" {
                copiedCodeMessage = nil
            }
        }
    }

    private func safeAppleMapsURL(from text: String) -> URL? {
        guard let url = URL(string: text),
              url.scheme == "https",
              url.host == "maps.apple.com" else { return nil }
        return url
    }
}

struct MeetingInfoEditView: View {
    let group: TouringGroup
    @ObservedObject var firebaseService: FirebaseGroupService
    @Binding var isPresented: Bool
    @State private var placeName: String
    @State private var placeURL: String
    @State private var hasMeetingTime: Bool
    @State private var meetingTime: Date
    @State private var showingLocationError = false
    @State private var showingURLValidationError = false
    @StateObject private var locationSharingManager = LocationSharingManager()

    init(group: TouringGroup, firebaseService: FirebaseGroupService, isPresented: Binding<Bool>) {
        self.group = group
        self.firebaseService = firebaseService
        _isPresented = isPresented
        _placeName = State(initialValue: group.meetingPlaceName)
        _placeURL = State(initialValue: group.meetingPlaceURL)
        _hasMeetingTime = State(initialValue: group.meetingTime != nil)
        _meetingTime = State(initialValue: group.meetingTime ?? Date())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("集合場所") {
                    TextField("例: 仙台駅 東口", text: $placeName)
                    TextField("地図URL", text: $placeURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)

                    Button {
                        setMeetingPlaceFromCurrentLocation()
                    } label: {
                        Label(locationSharingManager.isLoading ? "現在地を取得中..." : "現在地を集合場所にする", systemImage: "location.fill")
                    }
                    .disabled(locationSharingManager.isLoading)
                }

                Section("集合時間") {
                    Toggle("時間を設定する", isOn: $hasMeetingTime)
                    if hasMeetingTime {
                        DatePicker("集合時間", selection: $meetingTime)
                    }
                }
            }
            .navigationTitle("集合場所")
            .navigationBarTitleDisplayMode(.inline)
            .alert("現在地を取得できません", isPresented: $showingLocationError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(locationSharingManager.errorMessage ?? "位置情報の許可を確認してください。")
            }
            .alert("地図URLを確認してください", isPresented: $showingURLValidationError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("空欄にするか、https://maps.apple.com で始まるURLを入力してください。")
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("キャンセル") {
                        isPresented = false
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") {
                        let trimmedURL = placeURL.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard isValidMeetingURL(trimmedURL) else {
                            showingURLValidationError = true
                            return
                        }
                        firebaseService.updateMeetingInfo(
                            groupID: group.id,
                            placeName: placeName.trimmingCharacters(in: .whitespacesAndNewlines),
                            placeURL: trimmedURL,
                            meetingTime: hasMeetingTime ? meetingTime : nil
                        ) {
                            isPresented = false
                        }
                    }
                }
            }
        }
    }

    private func setMeetingPlaceFromCurrentLocation() {
        locationSharingManager.requestCurrentLocation { result in
            switch result {
            case .success(let location):
                let coordinate = location.coordinate
                placeName = "現在地"
                placeURL = "https://maps.apple.com/?ll=\(coordinate.latitude),\(coordinate.longitude)"
            case .failure:
                showingLocationError = true
            }
        }
    }

    private func isValidMeetingURL(_ text: String) -> Bool {
        guard !text.isEmpty else { return true }
        guard let url = URL(string: text) else { return false }
        return url.scheme == "https" && url.host == "maps.apple.com"
    }
}
