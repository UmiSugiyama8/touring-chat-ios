import Foundation
import Combine
import FirebaseFirestore
//実際に Firebase に保存・読み込みしている Firebaseと会話する係

final class FirebaseGroupService: ObservableObject {
    private let db = Firestore.firestore() //Firestoreを使います
    private var groupsListener: ListenerRegistration?
    private var messagesListeners: [String: ListenerRegistration] = [:]
    deinit {
        groupsListener?.remove()
        messagesListeners.values.forEach { $0.remove() }
    }

    func loadJoinedGroupIDs() -> [String] {
        UserDefaults.standard.stringArray(forKey: joinedGroupIDsKey) ?? []
    }

    func saveJoinedGroupID(_ groupID: String) {
        var ids = loadJoinedGroupIDs()
        if !ids.contains(groupID) {
            ids.append(groupID)
            UserDefaults.standard.set(ids, forKey: joinedGroupIDsKey)
        }
    }

    func removeJoinedGroupID(_ groupID: String) {
        var ids = loadJoinedGroupIDs()
        ids.removeAll { $0 == groupID }
        UserDefaults.standard.set(ids, forKey: joinedGroupIDsKey)
    }

    func saveMemberInfo(groupID: String, displayName: String, profileColorRawValue: String, profileIconRawValue: String) {
        LocalNotificationManager.shared.fetchFCMToken { token in
            var data: [String: Any] = [
                "displayName": displayName,
                "profileColorRawValue": profileColorRawValue,
                "profileIconRawValue": profileIconRawValue,
                "deviceID": currentDeviceID(),
                "authUID": FirebaseAuthService.currentUID,
                "updatedAt": Date()
            ]

            if let token = token {
                data["fcmToken"] = token
            }

            self.db.collection("groups")
                .document(groupID)
                .collection("members")
                .document(currentDeviceID())
                .setData(data, merge: true) { error in
                    if let error = error {
                        print("Failed to save member info: \(error)")
                    } else {
                        print("Saved member info for group: \(groupID)")
                    }
                }
        }
    }

    func updateMyProfileInJoinedGroups(displayName: String, profileColorRawValue: String, profileIconRawValue: String) {
        let joinedIDs = loadJoinedGroupIDs()
        guard !joinedIDs.isEmpty else { return }

        LocalNotificationManager.shared.fetchFCMToken { token in
            for groupID in joinedIDs {
                var data: [String: Any] = [
                    "displayName": displayName,
                    "profileColorRawValue": profileColorRawValue,
                    "profileIconRawValue": profileIconRawValue,
                    "deviceID": currentDeviceID(),
                    "authUID": FirebaseAuthService.currentUID,
                    "isArrived": false,
                    "updatedAt": Date()
                ]

                if let token = token {
                    data["fcmToken"] = token
                }

                self.db.collection("groups")
                    .document(groupID)
                    .collection("members")
                    .document(currentDeviceID())
                    .setData(data, merge: true) { error in
                        if let error = error {
                            print("Failed to update profile in group \(groupID): \(error)")
                        } else {
                            print("Updated profile in group: \(groupID)")
                        }
                    }
            }
        }
    }

    func leaveGroup(groupID: UUID, completion: (() -> Void)? = nil) {
        let groupIDString = groupID.uuidString
        removeJoinedGroupID(groupIDString)

        db.collection("groups")
            .document(groupIDString)
            .setData(["memberCount": FieldValue.increment(Int64(-1))], merge: true)

        db.collection("groups")
            .document(groupIDString)
            .collection("members")
            .document(currentDeviceID())
            .delete { error in
                if let error = error {
                    print("Failed to delete member info: \(error)")
                } else {
                    print("Left group: \(groupIDString)")
                }

                DispatchQueue.main.async {
                    completion?()
                }
            }
    }

    func listenGroups(onUpdate: @escaping ([TouringGroup]) -> Void) {
        groupsListener?.remove()

        if FirebaseAuthService.currentUID.isEmpty {
            FirebaseAuthService.signInIfNeeded { [weak self] isSignedIn in
                guard isSignedIn else {
                    onUpdate([])
                    return
                }
                self?.listenGroups(onUpdate: onUpdate)
            }
            return
        }

        let joinedIDs = loadJoinedGroupIDs()
        if joinedIDs.isEmpty {
            DispatchQueue.main.async {
                onUpdate([])
            }
            return
        }

        groupsListener = db.collection("groups")
            .whereField(FieldPath.documentID(), in: joinedIDs)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    print("Failed to listen groups: \(error)")
                    return
                }

                let groups = snapshot?.documents.compactMap { document -> TouringGroup? in
                    let data = document.data()
                    guard let name = data["name"] as? String,
                          let code = data["code"] as? String else { return nil }
                    let ownerDeviceID = data["ownerDeviceID"] as? String ?? ""
                    let memberCount = data["memberCount"] as? Int ?? 1
                    let arrivedCount = data["arrivedCount"] as? Int ?? 0
                    let lastMessageText = data["lastMessageText"] as? String ?? ""
                    let meetingPlaceName = data["meetingPlaceName"] as? String ?? ""
                    let meetingPlaceURL = data["meetingPlaceURL"] as? String ?? ""
                    let lastMessageAt: Date?
                    if let timestamp = data["lastMessageAt"] as? Timestamp {
                        lastMessageAt = timestamp.dateValue()
                    } else if let date = data["lastMessageAt"] as? Date {
                        lastMessageAt = date
                    } else {
                        lastMessageAt = nil
                    }
                    let meetingTime: Date?
                    if let timestamp = data["meetingTime"] as? Timestamp {
                        meetingTime = timestamp.dateValue()
                    } else if let date = data["meetingTime"] as? Date {
                        meetingTime = date
                    } else {
                        meetingTime = nil
                    }

                    return TouringGroup(
                        id: UUID(uuidString: document.documentID) ?? UUID(),
                        name: name,
                        code: code,
                        ownerDeviceID: ownerDeviceID,
                        memberCount: memberCount,
                        arrivedCount: arrivedCount,
                        lastMessageText: lastMessageText,
                        lastMessageAt: lastMessageAt,
                        meetingPlaceName: meetingPlaceName,
                        meetingPlaceURL: meetingPlaceURL,
                        meetingTime: meetingTime,
                        messages: []
                    )
                } ?? []

                DispatchQueue.main.async {
                    onUpdate(groups.sorted {
                        ($0.lastMessageAt ?? .distantPast) > ($1.lastMessageAt ?? .distantPast)
                    })
                }
            }
    }

    func createGroup(name: String, displayName: String, profileColorRawValue: String, profileIconRawValue: String, completion: (() -> Void)? = nil) {
        FirebaseAuthService.signInIfNeeded { [weak self] isSignedIn in
            guard let self, isSignedIn else {
                DispatchQueue.main.async {
                    completion?()
                }
                return
            }

            let groupID = UUID()
            let code = String(format: "%06d", Int.random(in: 0...999999))

            self.db.collection("groups").document(groupID.uuidString).setData([
                "name": name,
                "code": code,
                "ownerDeviceID": currentDeviceID(),
                "ownerAuthUID": FirebaseAuthService.currentUID,
                "memberCount": 1,
                "arrivedCount": 0,
                "createdAt": Date()
            ]) { error in
                if let error = error {
                    print("Failed to create group: \(error)")
                } else {
                    self.saveJoinedGroupID(groupID.uuidString)
                    self.saveMemberInfo(groupID: groupID.uuidString, displayName: displayName, profileColorRawValue: profileColorRawValue, profileIconRawValue: profileIconRawValue)
                    print("Created group: \(name), code: \(code)")
                    DispatchQueue.main.async {
                        completion?()
                    }
                }
            }
        }
    }

    func findGroupByCode(_ code: String, displayName: String, profileColorRawValue: String, profileIconRawValue: String, completion: @escaping (TouringGroup?) -> Void) {
        if FirebaseAuthService.currentUID.isEmpty {
            FirebaseAuthService.signInIfNeeded { [weak self] isSignedIn in
                guard isSignedIn else {
                    completion(nil)
                    return
                }
                self?.findGroupByCode(code, displayName: displayName, profileColorRawValue: profileColorRawValue, profileIconRawValue: profileIconRawValue, completion: completion)
            }
            return
        }

        db.collection("groups")
            .whereField("code", isEqualTo: code)
            .limit(to: 1)
            .getDocuments { snapshot, error in
                if let error = error {
                    print("Failed to find group by code: \(error)")
                    DispatchQueue.main.async {
                        completion(nil)
                    }
                    return
                }

                guard let document = snapshot?.documents.first else {
                    DispatchQueue.main.async {
                        completion(nil)
                    }
                    return
                }

                let data = document.data()
                guard let name = data["name"] as? String,
                      let code = data["code"] as? String else {
                    DispatchQueue.main.async {
                        completion(nil)
                    }
                    return
                }

                let alreadyJoined = self.loadJoinedGroupIDs().contains(document.documentID)
                self.saveJoinedGroupID(document.documentID)
                self.saveMemberInfo(groupID: document.documentID, displayName: displayName, profileColorRawValue: profileColorRawValue, profileIconRawValue: profileIconRawValue)
                if !alreadyJoined {
                    self.db.collection("groups")
                        .document(document.documentID)
                        .setData(["memberCount": FieldValue.increment(Int64(1))], merge: true)
                }
                let ownerDeviceID = data["ownerDeviceID"] as? String ?? ""
                let memberCount = data["memberCount"] as? Int ?? 1
                let arrivedCount = data["arrivedCount"] as? Int ?? 0
                let lastMessageText = data["lastMessageText"] as? String ?? ""
                let meetingPlaceName = data["meetingPlaceName"] as? String ?? ""
                let meetingPlaceURL = data["meetingPlaceURL"] as? String ?? ""
                let lastMessageAt: Date?
                if let timestamp = data["lastMessageAt"] as? Timestamp {
                    lastMessageAt = timestamp.dateValue()
                } else if let date = data["lastMessageAt"] as? Date {
                    lastMessageAt = date
                } else {
                    lastMessageAt = nil
                }
                let meetingTime: Date?
                if let timestamp = data["meetingTime"] as? Timestamp {
                    meetingTime = timestamp.dateValue()
                } else if let date = data["meetingTime"] as? Date {
                    meetingTime = date
                } else {
                    meetingTime = nil
                }
                let group = TouringGroup(
                    id: UUID(uuidString: document.documentID) ?? UUID(),
                    name: name,
                    code: code,
                    ownerDeviceID: ownerDeviceID,
                    memberCount: alreadyJoined ? memberCount : memberCount + 1,
                    arrivedCount: arrivedCount,
                    lastMessageText: lastMessageText,
                    lastMessageAt: lastMessageAt,
                    meetingPlaceName: meetingPlaceName,
                    meetingPlaceURL: meetingPlaceURL,
                    meetingTime: meetingTime,
                    messages: []
                )
                DispatchQueue.main.async {
                    completion(group)
                }
            }
    }

    func listenMessages(for group: TouringGroup, onUpdate: @escaping ([ChatMessage]) -> Void) {
        let groupID = group.id.uuidString
        messagesListeners[groupID]?.remove()

        if FirebaseAuthService.currentUID.isEmpty {
            FirebaseAuthService.signInIfNeeded { [weak self] isSignedIn in
                guard isSignedIn else {
                    onUpdate([])
                    return
                }
                self?.listenMessages(for: group, onUpdate: onUpdate)
            }
            return
        }

        messagesListeners[groupID] = db.collection("groups")
            .document(groupID)
            .collection("messages")
            .order(by: "sentAt", descending: false)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    print("Failed to listen messages: \(error)")
                    return
                }

                let messages = snapshot?.documents.compactMap { document -> ChatMessage? in
                    let data = document.data()
                    guard let text = data["text"] as? String,
                          let senderName = data["senderName"] as? String else { return nil }

                    let sentAt: Date
                    if let timestamp = data["sentAt"] as? Timestamp {
                        sentAt = timestamp.dateValue()
                    } else if let date = data["sentAt"] as? Date {
                        sentAt = date
                    } else {
                        sentAt = Date()
                    }
                    let senderDeviceID = data["senderDeviceID"] as? String ?? ""
                    return ChatMessage(id: UUID(uuidString: document.documentID) ?? UUID(), text: text, senderName: senderName, sentAt: sentAt, senderDeviceID: senderDeviceID)
                } ?? []

                DispatchQueue.main.async {
                    onUpdate(messages)
                }
            }
    }

    func listenMembers(for groupID: UUID, onUpdate: @escaping ([GroupMember]) -> Void) {
        if FirebaseAuthService.currentUID.isEmpty {
            FirebaseAuthService.signInIfNeeded { [weak self] isSignedIn in
                guard isSignedIn else {
                    onUpdate([])
                    return
                }
                self?.listenMembers(for: groupID, onUpdate: onUpdate)
            }
            return
        }

        db.collection("groups")
            .document(groupID.uuidString)
            .collection("members")
            .order(by: "updatedAt", descending: false)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    print("Failed to listen members: \(error)")
                    return
                }

                let members = snapshot?.documents.compactMap { document -> GroupMember? in
                    let data = document.data()
                    guard let displayName = data["displayName"] as? String else { return nil }

                    let updatedAt: Date
                    if let timestamp = data["updatedAt"] as? Timestamp {
                        updatedAt = timestamp.dateValue()
                    } else if let date = data["updatedAt"] as? Date {
                        updatedAt = date
                    } else {
                        updatedAt = Date()
                    }

                    let profileColorRawValue = data["profileColorRawValue"] as? String ?? ProfileColorOption.orange.rawValue
                    let profileIconRawValue = data["profileIconRawValue"] as? String ?? ProfileIconOption.tortoiseFill.rawValue
                    let isArrived = data["isArrived"] as? Bool ?? false

                    return GroupMember(
                        id: document.documentID,
                        displayName: displayName,
                        profileColorRawValue: profileColorRawValue,
                        profileIconRawValue: profileIconRawValue,
                        isArrived: isArrived,
                        updatedAt: updatedAt
                    )
                } ?? []

                DispatchQueue.main.async {
                    onUpdate(members)
                }
            }
    }

    func sendMessage(groupID: UUID, text: String, senderName: String, completion: ((Bool) -> Void)? = nil) {
        FirebaseAuthService.signInIfNeeded { [weak self] isSignedIn in
            guard let self, isSignedIn else {
                completion?(false)
                return
            }

            let messageID = UUID()
            self.db.collection("groups")
                .document(groupID.uuidString)
                .collection("messages")
                .document(messageID.uuidString)
                .setData([
                    "text": text,
                    "senderName": senderName,
                    "senderDeviceID": currentDeviceID(),
                    "senderAuthUID": FirebaseAuthService.currentUID,
                    "sentAt": Date()
                ]) { error in
                    if let error = error {
                        print("Failed to send message: \(error)")
                        DispatchQueue.main.async {
                            completion?(false)
                        }
                    } else {
                        print("Sent message to group \(groupID): \(text)")
                        self.db.collection("groups")
                            .document(groupID.uuidString)
                            .setData([
                                "lastMessageText": text,
                                "lastMessageAt": Date()
                            ], merge: true)
                        DispatchQueue.main.async {
                            completion?(true)
                        }
                    }
                }
        }
    }

    func updateMessage(groupID: UUID, messageID: UUID, newText: String) {
        db.collection("groups")
            .document(groupID.uuidString)
            .collection("messages")
            .document(messageID.uuidString)
            .setData([
                "text": newText,
                "editedAt": Date()
            ], merge: true) { error in
                if let error = error {
                    print("Failed to update message: \(error)")
                }
            }

        db.collection("groups")
            .document(groupID.uuidString)
            .setData([
                "lastMessageText": newText,
                "lastMessageAt": Date()
            ], merge: true)
    }

    func deleteMessage(groupID: UUID, messageID: UUID) {
        db.collection("groups")
            .document(groupID.uuidString)
            .collection("messages")
            .document(messageID.uuidString)
            .delete { error in
                if let error = error {
                    print("Failed to delete message: \(error)")
                }
            }
    }

    func updateMeetingInfo(groupID: UUID, placeName: String, placeURL: String, meetingTime: Date?, completion: (() -> Void)? = nil) {
        var data: [String: Any] = [
            "meetingPlaceName": placeName,
            "meetingPlaceURL": placeURL,
            "updatedAt": Date()
        ]

        if let meetingTime {
            data["meetingTime"] = meetingTime
        } else {
            data["meetingTime"] = FieldValue.delete()
        }

        db.collection("groups")
            .document(groupID.uuidString)
            .setData(data, merge: true) { error in
                if let error = error {
                    print("Failed to update meeting info: \(error)")
                }

                DispatchQueue.main.async {
                    completion?()
                }
            }
    }

    func updateArrivalStatus(groupID: UUID, isArrived: Bool) {
        let memberRef = db.collection("groups")
            .document(groupID.uuidString)
            .collection("members")
            .document(currentDeviceID())

        memberRef.getDocument { snapshot, error in
            if let error = error {
                print("Failed to fetch arrival status: \(error)")
                return
            }

            let wasArrived = snapshot?.data()?["isArrived"] as? Bool ?? false
            let delta = (isArrived ? 1 : 0) - (wasArrived ? 1 : 0)

            memberRef.setData([
                "isArrived": isArrived,
                "updatedAt": Date()
            ], merge: true) { error in
                if let error = error {
                    print("Failed to update arrival status: \(error)")
                    return
                }

                if delta != 0 {
                    self.db.collection("groups")
                        .document(groupID.uuidString)
                        .setData(["arrivedCount": FieldValue.increment(Int64(delta))], merge: true)
                }
            }
        }
    }

    func updateGroupName(groupID: UUID, newName: String, completion: (() -> Void)? = nil) {
        db.collection("groups")
            .document(groupID.uuidString)
            .setData([
                "name": newName,
                "updatedAt": Date()
            ], merge: true) { error in
                if let error = error {
                    print("Failed to update group name: \(error)")
                } else {
                    print("Updated group name: \(newName)")
                }

                DispatchQueue.main.async {
                    completion?()
                }
            }
    }

    func deleteGroup(groupID: UUID, completion: (() -> Void)? = nil) {
        let groupIDString = groupID.uuidString
        removeJoinedGroupID(groupIDString)

        db.collection("groups")
            .document(groupIDString)
            .delete { error in
                if let error = error {
                    print("Failed to delete group: \(error)")
                } else {
                    print("Deleted group: \(groupIDString)")
                }

                DispatchQueue.main.async {
                    completion?()
                }
            }
    }
}
