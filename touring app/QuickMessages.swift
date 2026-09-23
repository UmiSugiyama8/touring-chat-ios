import SwiftUI

let quickMessagesStorageKey = "quickMessages"

enum QuickMessageCategory: String, CaseIterable, Identifiable, Codable {
    case contact
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .contact: return "連絡"
        case .other: return "その他"
        }
    }
}

enum QuickMessageAction: String, Codable {
    case send
    case delay
    case location
}

enum QuickMessageTint: String, CaseIterable, Identifiable, Codable {
    case orange
    case green
    case red
    case blue
    case gray

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .orange: return "オレンジ"
        case .green: return "グリーン"
        case .red: return "レッド"
        case .blue: return "ブルー"
        case .gray: return "グレー"
        }
    }

    var color: Color {
        switch self {
        case .orange: return .orange
        case .green: return .green
        case .red: return .red
        case .blue: return .blue
        case .gray: return .gray
        }
    }
}

struct QuickMessage: Identifiable, Hashable, Codable {
    var id = UUID()
    var title: String
    var category: QuickMessageCategory
    var action: QuickMessageAction = .send
    var systemImage: String = "text.bubble.fill"
    var tint: QuickMessageTint = .orange
}

enum QuickMessageStore {
    static let defaultMessages: [QuickMessage] = [
        QuickMessage(title: "出発する", category: .contact, systemImage: "flag.fill", tint: .orange),
        QuickMessage(title: "到着", category: .contact, systemImage: "checkmark.circle.fill", tint: .green),
        QuickMessage(title: "遅れる", category: .contact, action: .delay, systemImage: "clock.badge.exclamationmark.fill", tint: .red),
        QuickMessage(title: "止まる", category: .contact, systemImage: "exclamationmark.triangle.fill", tint: .red),
        QuickMessage(title: "今ここにいる", category: .contact, action: .location, systemImage: "location.fill", tint: .blue),
        QuickMessage(title: "了解!", category: .contact, systemImage: "hand.thumbsup.fill", tint: .blue),
        QuickMessage(title: "はぐれた", category: .other, systemImage: "location.slash.fill", tint: .red),
        QuickMessage(title: "もう少しで出る", category: .other, systemImage: "clock.fill", tint: .orange),
        QuickMessage(title: "先に行ってて", category: .other, systemImage: "arrow.forward.circle.fill", tint: .blue),
        QuickMessage(title: "休憩しよう！", category: .other, systemImage: "cup.and.saucer.fill", tint: .orange),
        QuickMessage(title: "ガソスタ寄る", category: .other, systemImage: "fuelpump.fill", tint: .orange),
        QuickMessage(title: "コンビニ寄る", category: .other, systemImage: "cart.fill", tint: .orange),
        QuickMessage(title: "解散！", category: .other, systemImage: "figure.walk.departure", tint: .gray),
        QuickMessage(title: "通話かけて!", category: .other, systemImage: "phone.fill", tint: .blue)
    ]

    static func load() -> [QuickMessage] {
        guard let data = UserDefaults.standard.data(forKey: quickMessagesStorageKey),
              let messages = try? JSONDecoder().decode([QuickMessage].self, from: data) else {
            return defaultMessages
        }

        let normalizedMessages = normalized(messages)
        if normalizedMessages != messages {
            save(normalizedMessages)
        }
        return normalizedMessages
    }

    static func save(_ messages: [QuickMessage]) {
        guard let data = try? JSONEncoder().encode(messages) else { return }
        UserDefaults.standard.set(data, forKey: quickMessagesStorageKey)
    }

    static func reset() {
        save(defaultMessages)
    }

    private static func normalized(_ messages: [QuickMessage]) -> [QuickMessage] {
        var normalizedMessages = messages.map { message in
            var updatedMessage = message
            if updatedMessage.title == "はぐれた" {
                updatedMessage.category = .other
                updatedMessage.systemImage = "location.slash.fill"
                updatedMessage.tint = .red
            }
            return updatedMessage
        }

        if !normalizedMessages.contains(where: { $0.title == "了解!" }) {
            let replyMessage = QuickMessage(
                title: "了解!",
                category: .contact,
                systemImage: "hand.thumbsup.fill",
                tint: .blue
            )

            if let locationIndex = normalizedMessages.firstIndex(where: { $0.title == "今ここにいる" }) {
                normalizedMessages.insert(replyMessage, at: normalizedMessages.index(after: locationIndex))
            } else {
                normalizedMessages.append(replyMessage)
            }
        }

        return normalizedMessages
    }
}
