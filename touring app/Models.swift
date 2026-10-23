import Foundation
//データの設計図
/*Identifiable
「このデータには見分けるためのIDがあります」という意味。
Hashable
「このデータを比較したり、まとめて管理しやすくできます」という意味。
Codable
「このデータを保存したり、読み込んだりできる形に変換できます」という意味。*/

struct ChatMessage: Identifiable, Hashable, Codable {
    var id = UUID()
    var text: String
    var senderName: String
    var sentAt: Date = Date()
    var senderDeviceID: String = ""
    var senderAuthUID: String = ""
}


struct TouringGroup: Identifiable, Hashable, Codable {
    var id = UUID()
    var name: String
    var code: String
    var ownerDeviceID: String = ""
    var ownerAuthUID: String = ""
    var memberCount: Int = 1
    var arrivedCount: Int = 0
    var lastMessageText: String = ""
    var lastMessageAt: Date?
    var meetingPlaceName: String = ""
    var meetingPlaceURL: String = ""
    var meetingTime: Date?
    var messages: [ChatMessage] = []
}

struct GroupMember: Identifiable, Hashable {
    var id: String
    var displayName: String
    var profileColorRawValue: String
    var profileIconRawValue: String
    var isArrived: Bool = false
    var updatedAt: Date
}
