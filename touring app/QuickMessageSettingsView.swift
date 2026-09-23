import SwiftUI

struct QuickMessageSettingsView: View {
    @Binding var isPresented: Bool
    @State private var messages = QuickMessageStore.load()
    @State private var showingAddMessage = false
    @State private var editingMessage: QuickMessage?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("並び替えは編集ボタンからできます。追加したメッセージは通常の定型文として送信されます。")
                        .font(.footnote)
                        .foregroundColor(.gray)
                }

                ForEach(QuickMessageCategory.allCases) { category in
                    Section(category.title) {
                        ForEach(messages(for: category)) { message in
                            Button {
                                editingMessage = message
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: message.systemImage)
                                        .foregroundColor(message.tint.color)
                                        .frame(width: 24)

                                    Text(message.title)
                                        .foregroundColor(.primary)

                                    Spacer()

                                    if message.action != .send {
                                        Text(message.action == .delay ? "時間選択" : "現在地")
                                            .font(.caption2)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 3)
                                            .background(message.tint.color)
                                            .cornerRadius(6)
                                    }
                                }
                            }
                        }
                        .onDelete { offsets in
                            deleteMessages(at: offsets, in: category)
                        }
                        .onMove { source, destination in
                            moveMessages(from: source, to: destination, in: category)
                        }
                    }
                }

                Section {
                    Button(role: .destructive) {
                        QuickMessageStore.reset()
                        messages = QuickMessageStore.load()
                    } label: {
                        Label("初期設定に戻す", systemImage: "arrow.counterclockwise")
                    }
                }
            }
            .navigationTitle("定型メッセージ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("閉じる") {
                        isPresented = false
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingAddMessage = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddMessage) {
                QuickMessageEditView(message: nil) { newMessage in
                    messages.append(newMessage)
                    save()
                }
            }
            .sheet(item: $editingMessage) { message in
                QuickMessageEditView(message: message) { updatedMessage in
                    if let index = messages.firstIndex(where: { $0.id == updatedMessage.id }) {
                        messages[index] = updatedMessage
                        save()
                    }
                }
            }
        }
    }

    private func messages(for category: QuickMessageCategory) -> [QuickMessage] {
        messages.filter { $0.category == category }
    }

    private func deleteMessages(at offsets: IndexSet, in category: QuickMessageCategory) {
        let categoryMessages = messages(for: category)
        let deleteIDs = offsets.map { categoryMessages[$0].id }
        messages.removeAll { deleteIDs.contains($0.id) }
        save()
    }

    private func moveMessages(from source: IndexSet, to destination: Int, in category: QuickMessageCategory) {
        var categoryMessages = messages(for: category)
        categoryMessages.move(fromOffsets: source, toOffset: destination)

        var reordered: [QuickMessage] = []
        for currentCategory in QuickMessageCategory.allCases {
            if currentCategory == category {
                reordered += categoryMessages
            } else {
                reordered += messages(for: currentCategory)
            }
        }

        messages = reordered
        save()
    }

    private func save() {
        QuickMessageStore.save(messages)
    }
}

struct QuickMessageEditView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var category: QuickMessageCategory
    @State private var systemImage: String
    @State private var tint: QuickMessageTint

    private let originalMessage: QuickMessage?
    private let onSave: (QuickMessage) -> Void
    private let iconOptions = ["text.bubble.fill", "flag.fill", "checkmark.circle.fill", "clock.fill", "exclamationmark.triangle.fill", "location.fill", "cup.and.saucer.fill", "fuelpump.fill", "cart.fill", "phone.fill"]

    init(message: QuickMessage?, onSave: @escaping (QuickMessage) -> Void) {
        originalMessage = message
        self.onSave = onSave
        _title = State(initialValue: message?.title ?? "")
        _category = State(initialValue: message?.category ?? .contact)
        _systemImage = State(initialValue: message?.systemImage ?? "text.bubble.fill")
        _tint = State(initialValue: message?.tint ?? .orange)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("メッセージ") {
                    TextField("例: 少し待ってて", text: $title)
                    Picker("表示場所", selection: $category) {
                        ForEach(QuickMessageCategory.allCases) { category in
                            Text(category.title).tag(category)
                        }
                    }
                }

                Section("見た目") {
                    Picker("色", selection: $tint) {
                        ForEach(QuickMessageTint.allCases) { tint in
                            Label(tint.displayName, systemImage: "circle.fill")
                                .foregroundColor(tint.color)
                                .tag(tint)
                        }
                    }

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 48))], spacing: 12) {
                        ForEach(iconOptions, id: \.self) { icon in
                            Button {
                                systemImage = icon
                            } label: {
                                Image(systemName: icon)
                                    .font(.title3)
                                    .foregroundColor(systemImage == icon ? .white : tint.color)
                                    .frame(width: 44, height: 44)
                                    .background(systemImage == icon ? tint.color : Color(.systemGray6))
                                    .cornerRadius(10)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }

                if originalMessage?.action != nil && originalMessage?.action != .send {
                    Section("動き") {
                        Text("このメッセージには専用の動きがあります。文言、表示場所、見た目だけ変更できます。")
                            .font(.footnote)
                            .foregroundColor(.gray)
                    }
                }
            }
            .navigationTitle(originalMessage == nil ? "追加" : "編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") {
                        save()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var message = originalMessage ?? QuickMessage(title: trimmed, category: category)
        message.title = trimmed
        message.category = category
        message.systemImage = systemImage
        message.tint = tint
        onSave(message)
        dismiss()
    }
}
