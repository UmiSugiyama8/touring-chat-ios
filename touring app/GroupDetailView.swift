import SwiftUI
import CoreLocation
import UIKit

struct GroupDetailView: View {
    let group: TouringGroup
    let displayName: String
    @ObservedObject var firebaseService: FirebaseGroupService
    @State private var messages: [ChatMessage] = []
    @State private var members: [GroupMember] = []
    @State private var newMessage = ""
    @State private var showingDelayPicker = false
    @State private var latestMessageID = UUID()
    @State private var hasLoadedInitialMessages = false
    @State private var showingLeaveConfirm = false
    @State private var showingGroupInfo = false
    @State private var showingLocationError = false
    @State private var showingSendError = false
    @State private var sendErrorMessage = ""
    @State private var safetyModeEnabled = false
    @State private var editingMessage: ChatMessage?
    @State private var editedMessageText = ""
    @State private var selectedQuickMessageCategory = QuickMessageCategory.contact
    @State private var quickMessages = QuickMessageStore.load()
    @StateObject private var locationSharingManager = LocationSharingManager()
    @FocusState private var isMessageFieldFocused: Bool
    @Environment(\.dismiss) var dismiss

    private var selectedQuickMessages: [QuickMessage] {
        quickMessages.filter { $0.category == selectedQuickMessageCategory }
    }

    private var arrivedMembers: [GroupMember] {
        members.filter(\.isArrived)
    }

    private var messageTimeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }

    var body: some View {
        mainContent
            .onAppear {
                setupListeners()
            }
            .navigationTitle(group.name)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        safetyModeEnabled.toggle()
                    } label: {
                        Image(systemName: safetyModeEnabled ? "shield.fill" : "shield")
                            .foregroundColor(safetyModeEnabled ? .green : .primary)
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingGroupInfo = true
                    } label: {
                        Image(systemName: "person.2.circle.fill")
                            .font(.title2)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingDelayPicker) {
                DelayPickerView(isPresented: $showingDelayPicker) { selectedMessage in
                    sendTextMessage(selectedMessage, clearsInput: false)
                }
            }
            .sheet(isPresented: $showingGroupInfo) {
                GroupInfoView(
                    group: group,
                    firebaseService: firebaseService,
                    displayName: displayName,
                    showingLeaveConfirm: $showingLeaveConfirm,
                    isPresented: $showingGroupInfo,
                    onDeleteGroup: {
                        dismiss()
                    }
                )
            }
            .alert("グループを退出しますか？", isPresented: $showingLeaveConfirm) {
                Button("キャンセル", role: .cancel) {}
                Button("退出", role: .destructive) {
                    firebaseService.leaveGroup(groupID: group.id) {
                        dismiss()
                    }
                }
            } message: {
                Text("退出すると、この端末のグループ一覧から削除されます。参加コードを入力すれば再参加できます。")
            }
            .alert("現在地を送れません", isPresented: $showingLocationError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(locationSharingManager.errorMessage ?? "位置情報の許可を確認してください。")
            }
            .alert("送信できませんでした", isPresented: $showingSendError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(sendErrorMessage)
            }
            .alert("メッセージを編集", isPresented: Binding(
                get: { editingMessage != nil },
                set: { if !$0 { editingMessage = nil } }
            )) {
                TextField("メッセージ", text: $editedMessageText)
                Button("キャンセル", role: .cancel) {
                    editingMessage = nil
                }
                Button("保存") {
                    saveEditedMessage()
                }
            }
    }

    private var mainContent: some View {
        VStack {
            ArrivalStatusBar(members: members, arrivedMembers: arrivedMembers)

            if safetyModeEnabled {
                SafetyModeBanner()
            }

            messagesList

            Divider()

            inputSection
            if !isMessageFieldFocused {
                quickMessagesSection
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isMessageFieldFocused)
    }

    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(messages.enumerated()), id: \.offset) { index, message in
                        chatRow(for: message)
                            .padding(.horizontal)
                            .padding(.vertical, 2)
                            .id(index)
                    }
                }
            }
            .onChange(of: messages.count) { _, _ in
                if let lastIndex = messages.indices.last {
                    withAnimation {
                        proxy.scrollTo(lastIndex, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var inputSection: some View {
        Group {
            if !safetyModeEnabled {
                MessageInputBar(text: $newMessage, isFocused: $isMessageFieldFocused) { text in
                    sendTextMessage(text)
                }
            }
        }
    }

    private var quickMessagesSection: some View {
        QuickMessagesPanel(
            selectedCategory: $selectedQuickMessageCategory,
            messages: selectedQuickMessages,
            onSelect: sendQuickMessage
        )
    }

    private func chatRow(for message: ChatMessage) -> some View {
        ChatMessageRow(
            message: message,
            isMe: isMyMessage(message),
            timeText: messageTimeFormatter.string(from: message.sentAt),
            canEdit: isMyMessage(message),
            onOpenMap: {
                openMapIfNeeded(from: message.text)
            },
            onEdit: {
                editingMessage = message
                editedMessageText = message.text
            },
            onDelete: {
                firebaseService.deleteMessage(groupID: group.id, messageID: message.id)
            },
            onCopy: {
                UIPasteboard.general.string = message.text
            }
        )
    }

    private func setupListeners() {
        quickMessages = QuickMessageStore.load()
        GroupReadState.markRead(groupID: group.id, at: group.lastMessageAt ?? Date())
        firebaseService.listenMessages(for: group) { fetchedMessages in
            let previousMessageIDs = Set(messages.map { $0.id })
            messages = fetchedMessages
            GroupReadState.markRead(groupID: group.id)

            guard hasLoadedInitialMessages else {
                hasLoadedInitialMessages = true
                return
            }

            let newMessages = fetchedMessages.filter { !previousMessageIDs.contains($0.id) }
            for message in newMessages where !isMyMessage(message) {
                LocalNotificationManager.shared.notifyNewMessage(
                    groupName: group.name
                )
            }
        }

        firebaseService.listenMembers(for: group.id) { fetchedMembers in
            members = fetchedMembers
        }
    }

    private func isMyMessage(_ message: ChatMessage) -> Bool {
        if !message.senderAuthUID.isEmpty {
            return message.senderAuthUID == FirebaseAuthService.currentUID
        }
        return message.senderDeviceID == currentDeviceID()
    }

    private func saveEditedMessage() {
        guard let editingMessage else { return }
        let trimmed = editedMessageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        firebaseService.updateMessage(groupID: group.id, messageID: editingMessage.id, newText: trimmed)
        self.editingMessage = nil
    }

    private func sendCurrentLocation() {
        locationSharingManager.requestCurrentLocation { result in
            switch result {
            case .success(let location):
                let coordinate = location.coordinate
                let url = "https://maps.apple.com/?ll=\(coordinate.latitude),\(coordinate.longitude)"
                sendTextMessage("今ここにいる: \(url)", clearsInput: false)
            case .failure:
                showingLocationError = true
            }
        }
    }

    private func sendQuickMessage(_ message: QuickMessage) {
        if message.action == .delay {
            showingDelayPicker = true
            return
        }

        if message.action == .location {
            sendCurrentLocation()
            return
        }

        sendTextMessage(message.title, clearsInput: false)
    }

    private func sendTextMessage(_ text: String, clearsInput: Bool = true) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        firebaseService.sendMessage(groupID: group.id, text: trimmed, senderName: displayName) { success in
            guard success else {
                sendErrorMessage = "通信状況を確認して、もう一度送信してください。"
                showingSendError = true
                return
            }

            if trimmed == "到着" {
                firebaseService.updateArrivalStatus(groupID: group.id, isArrived: true)
            }

            latestMessageID = UUID()
            if clearsInput {
                newMessage = ""
                isMessageFieldFocused = false
            }
        }
    }

    private func openMapIfNeeded(from text: String) {
        guard let url = mapURL(from: text) else { return }
        UIApplication.shared.open(url)
    }

    private func mapURL(from text: String) -> URL? {
        guard let range = text.range(of: "https://maps.apple.com/") else { return nil }
        let urlText = String(text[range.lowerBound...])
        return URL(string: urlText)
    }

    private func messageStyle(for message: ChatMessage) -> MessageStyle {
        MessageStyle(text: message.text)
    }
}

struct ChatMessageRow: View {
    let message: ChatMessage
    let isMe: Bool
    let timeText: String
    let canEdit: Bool
    let onOpenMap: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onCopy: () -> Void

    private var style: MessageStyle {
        MessageStyle(text: message.text)
    }

    var body: some View {
        HStack(alignment: .bottom) {
            if isMe {
                Spacer(minLength: 50)
            }

            VStack(alignment: isMe ? .trailing : .leading, spacing: 4) {
                if !isMe {
                    Text(message.senderName)
                        .font(.caption)
                        .foregroundColor(.gray)
                        .padding(.leading, 4)
                }

                HStack(alignment: .bottom, spacing: 6) {
                    if isMe {
                        messageTime
                    }

                    messageBubble

                    if !isMe {
                        messageTime
                    }
                }
            }

            if !isMe {
                Spacer(minLength: 50)
            }
        }
    }

    private var messageTime: some View {
        Text(timeText)
            .font(.caption2)
            .foregroundColor(.gray)
    }

    private var messageBubble: some View {
        HStack(spacing: 6) {
            if let iconName = style.iconName {
                Image(systemName: iconName)
            }

            Text(message.text)
        }
        .font(.body)
        .foregroundColor(style.foregroundColor(isMe: isMe))
        .padding(.vertical, 9)
        .padding(.horizontal, 12)
        .background(style.backgroundColor(isMe: isMe))
        .cornerRadius(16)
        .onTapGesture(perform: onOpenMap)
        .contextMenu {
            if canEdit {
                Button(action: onEdit) {
                    Label("編集", systemImage: "pencil")
                }

                Button(role: .destructive, action: onDelete) {
                    Label("削除", systemImage: "trash")
                }
            }

            Button(action: onCopy) {
                Label("コピー", systemImage: "doc.on.doc")
            }
        }
    }
}

struct MessageInputBar: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    let onSend: (String) -> Void

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        HStack(spacing: 10) {
            TextField("メッセージを入力", text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.title3)
                .focused(isFocused)
                .submitLabel(.send)
                .onSubmit {
                    onSend(trimmedText)
                }

            Button {
                onSend(trimmedText)
            } label: {
                Text("送信")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 18)
                    .background(Color.orange)
                    .cornerRadius(10)
            }
            .disabled(trimmedText.isEmpty)
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 2)
    }
}

struct QuickMessagesPanel: View {
    @Binding var selectedCategory: QuickMessageCategory
    let messages: [QuickMessage]
    let onSelect: (QuickMessage) -> Void

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("定型メッセージ", selection: $selectedCategory) {
                ForEach(QuickMessageCategory.allCases) { category in
                    Text(category.title).tag(category)
                }
            }
            .pickerStyle(.segmented)

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(messages) { message in
                    QuickMessageButton(message: message) {
                        onSelect(message)
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .background(Color(.systemBackground))
    }
}

struct QuickMessageButton: View {
    let message: QuickMessage
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(message.title, systemImage: message.systemImage)
                .font(.body)
                .fontWeight(.semibold)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 54)
                .padding(.horizontal, 8)
                .background(message.tint.color)
                .foregroundColor(.white)
                .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }
}

struct ArrivalStatusBar: View {
    let members: [GroupMember]
    let arrivedMembers: [GroupMember]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("\(arrivedMembers.count)/\(members.count) 到着", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.green)

                Spacer()
            }

            if arrivedMembers.isEmpty {
                Text("まだ到着済みのメンバーはいません")
                    .font(.caption)
                    .foregroundColor(.gray)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(arrivedMembers) { member in
                            Label(member.displayName, systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.green.opacity(0.12))
                                .foregroundColor(.green)
                                .cornerRadius(10)
                        }
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }
}

struct SafetyModeBanner: View {
    var body: some View {
        Label("安全モード中: 停車して周囲の安全を確認してから操作してください", systemImage: "shield.fill")
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundColor(.green)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.green.opacity(0.1))
    }
}

struct MessageStyle {
    let text: String

    var iconName: String? {
        if text.contains("遅れる") { return "clock.badge.exclamationmark.fill" }
        if text.contains("止まる") { return "exclamationmark.triangle.fill" }
        if text.contains("はぐれた") { return "location.slash.fill" }
        if text.contains("到着") { return "checkmark.circle.fill" }
        if text.contains("今ここにいる") || text.contains("maps.apple.com") { return "location.fill" }
        if text.contains("出発") { return "flag.fill" }
        return nil
    }

    func backgroundColor(isMe: Bool) -> Color {
        if text.contains("遅れる") || text.contains("止まる") || text.contains("はぐれた") {
            return .red
        }
        if text.contains("到着") {
            return .green
        }
        if text.contains("今ここにいる") || text.contains("maps.apple.com") {
            return .blue
        }
        if isMe {
            return .orange
        }
        return Color(.systemGray5)
    }

    func foregroundColor(isMe: Bool) -> Color {
        if isMe || text.contains("遅れる") || text.contains("止まる") || text.contains("はぐれた") || text.contains("到着") || text.contains("今ここにいる") || text.contains("maps.apple.com") {
            return .white
        }
        return .primary
    }
}
