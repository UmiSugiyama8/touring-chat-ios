import Foundation

enum GroupReadState {
    static func markRead(groupID: UUID, at date: Date = Date()) {
        UserDefaults.standard.set(date, forKey: key(for: groupID))
    }

    static func hasUnread(_ group: TouringGroup) -> Bool {
        guard let lastMessageAt = group.lastMessageAt,
              !group.lastMessageText.isEmpty else {
            return false
        }

        let lastReadAt = UserDefaults.standard.object(forKey: key(for: group.id)) as? Date ?? .distantPast
        return lastMessageAt > lastReadAt
    }

    private static func key(for groupID: UUID) -> String {
        "lastReadAt-\(groupID.uuidString)"
    }
}
