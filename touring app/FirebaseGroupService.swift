import Foundation
import Combine
import FirebaseFirestore

// Sparkプランで動作するよう、Firestoreとセキュリティルールでデータを管理する。
final class FirebaseGroupService: ObservableObject {
    private let db = Firestore.firestore()
    private var groupsListeners: [ListenerRegistration] = []
    private var groupsByID: [UUID: TouringGroup] = [:]
    private var messagesListeners: [String: ListenerRegistration] = [:]
    private var membersListeners: [String: ListenerRegistration] = [:]
    private var indexedGroupIDs: Set<String> = []

    deinit {
        groupsListeners.forEach { $0.remove() }
        messagesListeners.values.forEach { $0.remove() }
        membersListeners.values.forEach { $0.remove() }
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

    private func profileData(
        displayName: String,
        profileColorRawValue: String,
        profileIconRawValue: String
    ) -> [String: Any] {
        [
            "displayName": String(displayName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40)),
            "profileColorRawValue": profileColorRawValue,
            "profileIconRawValue": profileIconRawValue,
            "deviceID": currentDeviceID(),
            "authUID": FirebaseAuthService.currentUID,
            "updatedAt": FieldValue.serverTimestamp(),
            // 古い版で保存した通知トークンは、プロフィール更新時に削除する。
            "fcmToken": FieldValue.delete()
        ]
    }

    func saveMemberInfo(
        groupID: String,
        displayName: String,
        profileColorRawValue: String,
        profileIconRawValue: String
    ) {
        FirebaseAuthService.signInIfNeeded { [weak self] isSignedIn in
            guard let self, isSignedIn else { return }
            let data = self.profileData(
                displayName: displayName,
                profileColorRawValue: profileColorRawValue,
                profileIconRawValue: profileIconRawValue
            )
            self.db.collection("groups")
                .document(groupID)
                .collection("members")
                .document(FirebaseAuthService.currentUID)
                .setData(data, merge: true) { error in
                    if let error {
                        print("Failed to save member profile: \(error.localizedDescription)")
                    }
                }
        }
    }

    func updateMyProfileInJoinedGroups(
        displayName: String,
        profileColorRawValue: String,
        profileIconRawValue: String
    ) {
        for groupID in loadJoinedGroupIDs() {
            saveMemberInfo(
                groupID: groupID,
                displayName: displayName,
                profileColorRawValue: profileColorRawValue,
                profileIconRawValue: profileIconRawValue
            )
        }
    }

    func leaveGroup(groupID: UUID, completion: (() -> Void)? = nil) {
        let groupIDString = groupID.uuidString
        FirebaseAuthService.signInIfNeeded { [weak self] isSignedIn in
            guard let self, isSignedIn else { return }

            let groupRef = self.db.collection("groups").document(groupIDString)
            let memberRef = groupRef.collection("members").document(FirebaseAuthService.currentUID)
            memberRef.getDocument(source: .server) { snapshot, error in
                guard error == nil, let data = snapshot?.data() else { return }
                let wasArrived = data["isArrived"] as? Bool ?? false
                let batch = self.db.batch()
                batch.deleteDocument(memberRef)
                batch.updateData([
                    "memberCount": FieldValue.increment(Int64(-1)),
                    "arrivedCount": FieldValue.increment(Int64(wasArrived ? -1 : 0)),
                    "updatedAt": FieldValue.serverTimestamp()
                ], forDocument: groupRef)
                batch.commit { error in
                    guard error == nil else {
                        print("Failed to leave group")
                        return
                    }
                    self.removeJoinedGroupID(groupIDString)
                    DispatchQueue.main.async { completion?() }
                }
            }
        }
    }

    private func authorizedJoinedGroupIDs(
        _ groupIDs: [String],
        completion: @escaping ([String]) -> Void
    ) {
        guard !groupIDs.isEmpty else {
            completion([])
            return
        }

        let dispatchGroup = DispatchGroup()
        let lock = NSLock()
        var authorizedIDs: [String] = []

        for groupID in groupIDs {
            dispatchGroup.enter()
            authorizeMembership(groupID: groupID) { isAuthorized in
                defer { dispatchGroup.leave() }
                guard isAuthorized else { return }
                lock.lock()
                authorizedIDs.append(groupID)
                lock.unlock()
            }
        }

        dispatchGroup.notify(queue: .main) {
            completion(authorizedIDs)
        }
    }

    private func authorizeMembership(groupID: String, completion: @escaping (Bool) -> Void) {
        let uid = FirebaseAuthService.currentUID
        guard !uid.isEmpty else {
            completion(false)
            return
        }

        let groupRef = db.collection("groups").document(groupID)
        let memberRef = groupRef.collection("members").document(uid)
        memberRef.getDocument { [weak self] snapshot, _ in
            guard let self else { return }
            if snapshot?.exists == true {
                if snapshot?.data()?["fcmToken"] != nil {
                    memberRef.updateData([
                        "fcmToken": FieldValue.delete(),
                        "updatedAt": FieldValue.serverTimestamp()
                    ])
                }
                completion(true)
                return
            }

            let legacyRef = groupRef.collection("members").document(currentDeviceID())
            legacyRef.getDocument { legacySnapshot, _ in
                if let legacyData = legacySnapshot?.data(),
                   legacyData["authUID"] as? String == uid {
                    var migratedData = legacyData
                    migratedData.removeValue(forKey: "fcmToken")
                    migratedData["authUID"] = uid
                    migratedData["deviceID"] = currentDeviceID()
                    migratedData["isArrived"] = legacyData["isArrived"] as? Bool ?? false
                    migratedData["updatedAt"] = FieldValue.serverTimestamp()

                    let batch = self.db.batch()
                    batch.setData(migratedData, forDocument: memberRef)
                    batch.deleteDocument(legacyRef)
                    batch.commit { error in
                        completion(error == nil)
                    }
                    return
                }

                // 古いデータでオーナーのメンバー文書だけ欠けた場合を復旧する。
                groupRef.getDocument { groupSnapshot, _ in
                    guard groupSnapshot?.data()?["ownerAuthUID"] as? String == uid else {
                        completion(false)
                        return
                    }

                    let defaults = UserDefaults.standard
                    var ownerData = self.profileData(
                        displayName: defaults.string(forKey: displayNameKey) ?? "ライダー",
                        profileColorRawValue: defaults.string(forKey: profileColorKey) ?? ProfileColorOption.orange.rawValue,
                        profileIconRawValue: defaults.string(forKey: profileIconKey) ?? ProfileIconOption.tortoiseFill.rawValue
                    )
                    ownerData.removeValue(forKey: "fcmToken")
                    ownerData["isArrived"] = false
                    ownerData["joinedAt"] = FieldValue.serverTimestamp()
                    memberRef.setData(ownerData) { error in
                        completion(error == nil)
                    }
                }
            }
        }
    }

    func listenGroups(onUpdate: @escaping ([TouringGroup]) -> Void) {
        groupsListeners.forEach { $0.remove() }
        groupsListeners.removeAll()
        groupsByID.removeAll()

        FirebaseAuthService.signInIfNeeded { [weak self] isSignedIn in
            guard let self, isSignedIn else {
                DispatchQueue.main.async { onUpdate([]) }
                return
            }

            let joinedIDs = self.loadJoinedGroupIDs()
            self.authorizedJoinedGroupIDs(joinedIDs) { [weak self] authorizedIDs in
                guard let self else { return }
                guard !authorizedIDs.isEmpty else {
                    onUpdate([])
                    return
                }

                // Firestoreの「in」検索は一度に30件までなので分割する。
                for start in stride(from: 0, to: authorizedIDs.count, by: 30) {
                    let end = min(start + 30, authorizedIDs.count)
                    let chunk = Array(authorizedIDs[start..<end])
                    let listener = self.db.collection("groups")
                        .whereField(FieldPath.documentID(), in: chunk)
                        .addSnapshotListener { [weak self] snapshot, error in
                            guard let self else { return }
                            if let error {
                                print("Failed to listen groups: \(error.localizedDescription)")
                                return
                            }

                            let fetched = snapshot?.documents.compactMap(self.group(from:)) ?? []
                            fetched.forEach { self.ensureCodeIndex(for: $0) }
                            DispatchQueue.main.async {
                                for idString in chunk {
                                    if let id = UUID(uuidString: idString) {
                                        self.groupsByID[id] = nil
                                    }
                                }
                                for group in fetched {
                                    self.groupsByID[group.id] = group
                                }
                                onUpdate(self.groupsByID.values.sorted {
                                    ($0.lastMessageAt ?? .distantPast) > ($1.lastMessageAt ?? .distantPast)
                                })
                            }
                        }
                    self.groupsListeners.append(listener)
                }
            }
        }
    }

    private func group(from document: QueryDocumentSnapshot) -> TouringGroup? {
        group(documentID: document.documentID, data: document.data())
    }

    private func group(documentID: String, data: [String: Any]) -> TouringGroup? {
        guard let id = UUID(uuidString: documentID),
              let name = data["name"] as? String,
              let code = data["code"] as? String else { return nil }

        return TouringGroup(
            id: id,
            name: name,
            code: code,
            ownerDeviceID: data["ownerDeviceID"] as? String ?? "",
            ownerAuthUID: data["ownerAuthUID"] as? String ?? "",
            memberCount: (data["memberCount"] as? NSNumber)?.intValue ?? 1,
            arrivedCount: (data["arrivedCount"] as? NSNumber)?.intValue ?? 0,
            lastMessageText: data["lastMessageText"] as? String ?? "",
            lastMessageAt: date(from: data["lastMessageAt"]),
            meetingPlaceName: data["meetingPlaceName"] as? String ?? "",
            meetingPlaceURL: data["meetingPlaceURL"] as? String ?? "",
            meetingTime: date(from: data["meetingTime"]),
            messages: []
        )
    }

    private func date(from value: Any?) -> Date? {
        if let timestamp = value as? Timestamp { return timestamp.dateValue() }
        return value as? Date
    }

    private func ensureCodeIndex(for group: TouringGroup) {
        let groupID = group.id.uuidString
        guard group.ownerAuthUID == FirebaseAuthService.currentUID,
              !indexedGroupIDs.contains(groupID) else { return }

        indexedGroupIDs.insert(groupID)
        let codeRef = db.collection("groupCodes").document(group.code)
        codeRef.getDocument { [weak self] snapshot, error in
            guard let self else { return }
            if let error {
                self.indexedGroupIDs.remove(groupID)
                print("Failed to check group code index: \(error.localizedDescription)")
                return
            }
            guard snapshot?.exists != true else { return }
            codeRef.setData([
                "groupID": groupID,
                "ownerAuthUID": FirebaseAuthService.currentUID,
                "createdAt": FieldValue.serverTimestamp()
            ]) { error in
                if let error {
                    self.indexedGroupIDs.remove(groupID)
                    print("Failed to create group code index: \(error.localizedDescription)")
                }
            }
        }
    }

    func createGroup(
        name: String,
        displayName: String,
        profileColorRawValue: String,
        profileIconRawValue: String,
        completion: ((Bool) -> Void)? = nil
    ) {
        FirebaseAuthService.signInIfNeeded { [weak self] isSignedIn in
            guard let self, isSignedIn else {
                completion?(false)
                return
            }

            let groupID = UUID().uuidString
            let code = String(format: "%06d", Int.random(in: 0...999_999))
            let groupRef = self.db.collection("groups").document(groupID)
            let memberRef = groupRef.collection("members").document(FirebaseAuthService.currentUID)
            let codeRef = self.db.collection("groupCodes").document(code)
            let batch = self.db.batch()

            batch.setData([
                "name": String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60)),
                "code": code,
                "ownerAuthUID": FirebaseAuthService.currentUID,
                "ownerDeviceID": currentDeviceID(),
                "memberCount": 1,
                "arrivedCount": 0,
                "lastMessageText": "",
                "createdAt": FieldValue.serverTimestamp()
            ], forDocument: groupRef)

            var ownerData = self.profileData(
                displayName: displayName,
                profileColorRawValue: profileColorRawValue,
                profileIconRawValue: profileIconRawValue
            )
            ownerData.removeValue(forKey: "fcmToken")
            ownerData["isArrived"] = false
            ownerData["joinedAt"] = FieldValue.serverTimestamp()
            batch.setData(ownerData, forDocument: memberRef)
            batch.setData([
                "groupID": groupID,
                "ownerAuthUID": FirebaseAuthService.currentUID,
                "createdAt": FieldValue.serverTimestamp()
            ], forDocument: codeRef)

            batch.commit { error in
                if let error {
                    print("Failed to create group: \(error.localizedDescription)")
                    DispatchQueue.main.async { completion?(false) }
                    return
                }
                self.indexedGroupIDs.insert(groupID)
                self.saveJoinedGroupID(groupID)
                DispatchQueue.main.async { completion?(true) }
            }
        }
    }

    func findGroupByCode(
        _ code: String,
        displayName: String,
        profileColorRawValue: String,
        profileIconRawValue: String,
        completion: @escaping (TouringGroup?) -> Void
    ) {
        FirebaseAuthService.signInIfNeeded { [weak self] isSignedIn in
            guard let self, isSignedIn else {
                completion(nil)
                return
            }

            self.db.collection("groupCodes").document(code).getDocument { codeSnapshot, error in
                if let error {
                    print("Failed to find group code: \(error.localizedDescription)")
                    DispatchQueue.main.async { completion(nil) }
                    return
                }
                guard let groupID = codeSnapshot?.data()?["groupID"] as? String,
                      UUID(uuidString: groupID) != nil else {
                    DispatchQueue.main.async { completion(nil) }
                    return
                }

                let groupRef = self.db.collection("groups").document(groupID)
                let memberRef = groupRef.collection("members").document(FirebaseAuthService.currentUID)
                var memberData = self.profileData(
                    displayName: displayName,
                    profileColorRawValue: profileColorRawValue,
                    profileIconRawValue: profileIconRawValue
                )
                memberData.removeValue(forKey: "fcmToken")
                memberData["isArrived"] = false
                memberData["joinedAt"] = FieldValue.serverTimestamp()
                memberData["joinCode"] = code

                func finishJoin() {
                    self.saveJoinedGroupID(groupID)
                    groupRef.getDocument { groupSnapshot, error in
                        guard error == nil,
                              let data = groupSnapshot?.data(),
                              let group = self.group(documentID: groupID, data: data) else {
                            DispatchQueue.main.async { completion(nil) }
                            return
                        }
                        DispatchQueue.main.async { completion(group) }
                    }
                }

                memberRef.getDocument { existingMember, error in
                    guard error == nil else {
                        DispatchQueue.main.async { completion(nil) }
                        return
                    }
                    if existingMember?.exists == true {
                        finishJoin()
                        return
                    }

                    let batch = self.db.batch()
                    batch.setData(memberData, forDocument: memberRef)
                    batch.updateData([
                        "memberCount": FieldValue.increment(Int64(1)),
                        "updatedAt": FieldValue.serverTimestamp()
                    ], forDocument: groupRef)
                    batch.commit { error in
                        if let error {
                            print("Failed to join group: \(error.localizedDescription)")
                            DispatchQueue.main.async { completion(nil) }
                            return
                        }
                        finishJoin()
                    }
                }
            }
        }
    }

    func listenMessages(for group: TouringGroup, onUpdate: @escaping ([ChatMessage]) -> Void) {
        let groupID = group.id.uuidString
        messagesListeners[groupID]?.remove()

        messagesListeners[groupID] = db.collection("groups")
            .document(groupID)
            .collection("messages")
            .order(by: "sentAt", descending: false)
            .addSnapshotListener { snapshot, error in
                if let error {
                    print("Failed to listen messages: \(error.localizedDescription)")
                    return
                }

                let messages = snapshot?.documents.compactMap { document -> ChatMessage? in
                    let data = document.data()
                    guard let text = data["text"] as? String,
                          let senderName = data["senderName"] as? String else { return nil }
                    return ChatMessage(
                        id: UUID(uuidString: document.documentID) ?? UUID(),
                        text: text,
                        senderName: senderName,
                        sentAt: self.date(from: data["sentAt"]) ?? Date(),
                        senderDeviceID: data["senderDeviceID"] as? String ?? "",
                        senderAuthUID: data["senderAuthUID"] as? String ?? ""
                    )
                } ?? []
                DispatchQueue.main.async { onUpdate(messages) }
            }
    }

    func listenMembers(for groupID: UUID, onUpdate: @escaping ([GroupMember]) -> Void) {
        let groupIDString = groupID.uuidString
        membersListeners[groupIDString]?.remove()
        membersListeners[groupIDString] = db.collection("groups")
            .document(groupIDString)
            .collection("members")
            .order(by: "updatedAt", descending: false)
            .addSnapshotListener { snapshot, error in
                if let error {
                    print("Failed to listen members: \(error.localizedDescription)")
                    return
                }

                let members = snapshot?.documents.compactMap { document -> GroupMember? in
                    let data = document.data()
                    guard let displayName = data["displayName"] as? String else { return nil }
                    return GroupMember(
                        id: document.documentID,
                        displayName: displayName,
                        profileColorRawValue: data["profileColorRawValue"] as? String ?? ProfileColorOption.orange.rawValue,
                        profileIconRawValue: data["profileIconRawValue"] as? String ?? ProfileIconOption.tortoiseFill.rawValue,
                        isArrived: data["isArrived"] as? Bool ?? false,
                        updatedAt: self.date(from: data["updatedAt"]) ?? Date()
                    )
                } ?? []
                DispatchQueue.main.async { onUpdate(members) }
            }
    }

    func sendMessage(
        groupID: UUID,
        text: String,
        senderName: String,
        completion: ((Bool) -> Void)? = nil
    ) {
        _ = senderName
        FirebaseAuthService.signInIfNeeded { [weak self] isSignedIn in
            guard let self, isSignedIn else {
                completion?(false)
                return
            }

            let groupRef = self.db.collection("groups").document(groupID.uuidString)
            let memberRef = groupRef.collection("members").document(FirebaseAuthService.currentUID)
            memberRef.getDocument { memberSnapshot, error in
                guard error == nil,
                      let memberData = memberSnapshot?.data(),
                      let verifiedName = memberData["displayName"] as? String,
                      let verifiedDeviceID = memberData["deviceID"] as? String else {
                    DispatchQueue.main.async { completion?(false) }
                    return
                }

                let messageID = UUID().uuidString
                let messageRef = groupRef.collection("messages").document(messageID)
                let safeText = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1000))
                guard !safeText.isEmpty else {
                    DispatchQueue.main.async { completion?(false) }
                    return
                }

                let batch = self.db.batch()
                batch.setData([
                    "text": safeText,
                    "senderName": verifiedName,
                    "senderDeviceID": verifiedDeviceID,
                    "senderAuthUID": FirebaseAuthService.currentUID,
                    "sentAt": FieldValue.serverTimestamp()
                ], forDocument: messageRef)
                batch.updateData([
                    "lastMessageText": safeText,
                    "lastMessageAt": FieldValue.serverTimestamp(),
                    "lastMessageID": messageID,
                    "updatedAt": FieldValue.serverTimestamp()
                ], forDocument: groupRef)
                batch.commit { error in
                    if let error {
                        print("Failed to send message: \(error.localizedDescription)")
                    }
                    DispatchQueue.main.async { completion?(error == nil) }
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
                "editedAt": FieldValue.serverTimestamp()
            ], merge: true) { error in
                if let error {
                    print("Failed to update message: \(error.localizedDescription)")
                }
            }
    }

    func deleteMessage(groupID: UUID, messageID: UUID) {
        db.collection("groups")
            .document(groupID.uuidString)
            .collection("messages")
            .document(messageID.uuidString)
            .delete { error in
                if let error {
                    print("Failed to delete message: \(error.localizedDescription)")
                }
            }
    }

    func updateMeetingInfo(
        groupID: UUID,
        placeName: String,
        placeURL: String,
        meetingTime: Date?,
        completion: (() -> Void)? = nil
    ) {
        var data: [String: Any] = [
            "meetingPlaceName": String(placeName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120)),
            "meetingPlaceURL": String(placeURL.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1000)),
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if let meetingTime {
            data["meetingTime"] = meetingTime
        } else {
            data["meetingTime"] = FieldValue.delete()
        }

        db.collection("groups").document(groupID.uuidString).setData(data, merge: true) { error in
            if let error {
                print("Failed to update meeting info: \(error.localizedDescription)")
            }
            DispatchQueue.main.async { completion?() }
        }
    }

    func updateArrivalStatus(groupID: UUID, isArrived: Bool) {
        FirebaseAuthService.signInIfNeeded { [weak self] isSignedIn in
            guard let self, isSignedIn else { return }
            let groupRef = self.db.collection("groups").document(groupID.uuidString)
            let memberRef = groupRef.collection("members").document(FirebaseAuthService.currentUID)

            memberRef.getDocument { snapshot, error in
                guard error == nil, let data = snapshot?.data() else { return }
                let previousValue = data["isArrived"] as? Bool ?? false
                guard previousValue != isArrived else { return }
                let delta: Int64 = isArrived ? 1 : -1

                let batch = self.db.batch()
                batch.updateData([
                    "isArrived": isArrived,
                    "updatedAt": FieldValue.serverTimestamp()
                ], forDocument: memberRef)
                batch.updateData([
                    "arrivedCount": FieldValue.increment(delta),
                    "updatedAt": FieldValue.serverTimestamp()
                ], forDocument: groupRef)
                batch.commit { error in
                    if let error {
                        print("Failed to update arrival status: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    func updateGroupName(groupID: UUID, newName: String, completion: (() -> Void)? = nil) {
        let safeName = String(newName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
        guard !safeName.isEmpty else { return }
        db.collection("groups")
            .document(groupID.uuidString)
            .setData([
                "name": safeName,
                "updatedAt": FieldValue.serverTimestamp()
            ], merge: true) { error in
                if let error {
                    print("Failed to update group name: \(error.localizedDescription)")
                }
                DispatchQueue.main.async { completion?() }
            }
    }

    func deleteGroup(groupID: UUID, completion: @escaping (Bool) -> Void) {
        let groupIDString = groupID.uuidString
        let finish: (Bool) -> Void = { success in
            DispatchQueue.main.async { completion(success) }
        }
        FirebaseAuthService.signInIfNeeded { [weak self] isSignedIn in
            guard let self, isSignedIn else {
                finish(false)
                return
            }
            let groupRef = self.db.collection("groups").document(groupIDString)
            let uid = FirebaseAuthService.currentUID
            groupRef.getDocument(source: .server) { groupSnapshot, error in
                guard error == nil,
                      let groupData = groupSnapshot?.data(),
                      groupData["ownerAuthUID"] as? String == uid,
                      let code = groupData["code"] as? String else {
                    finish(false)
                    return
                }

                // 最終ルールは削除中の新規投稿・参加を禁止する。失敗時も再試行できる。
                groupRef.updateData([
                    "isDeleting": true,
                    "updatedAt": FieldValue.serverTimestamp()
                ]) { error in
                    guard error == nil else {
                        finish(false)
                        return
                    }
                    self.deleteCollectionContents(groupRef.collection("messages")) { success in
                        guard success else {
                            finish(false)
                            return
                        }
                        self.deleteCollectionContents(
                            groupRef.collection("members"), keepingDocumentID: uid
                        ) { success in
                            guard success else {
                                finish(false)
                                return
                            }
                            let codeRef = self.db.collection("groupCodes").document(code)
                            codeRef.getDocument(source: .server) { codeSnapshot, error in
                                guard error == nil else {
                                    finish(false)
                                    return
                                }
                                let batch = self.db.batch()
                                if codeSnapshot?.exists == true {
                                    guard codeSnapshot?.data()?["groupID"] as? String == groupIDString else {
                                        finish(false)
                                        return
                                    }
                                    batch.deleteDocument(codeRef)
                                }
                                // 最後まで所有者メンバーを保持し、認可を維持する。
                                batch.deleteDocument(groupRef.collection("members").document(uid))
                                batch.deleteDocument(groupRef)
                                batch.commit { error in
                                    guard error == nil else {
                                        finish(false)
                                        return
                                    }
                                    self.removeJoinedGroupID(groupIDString)
                                    finish(true)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func deleteCollectionContents(
        _ collection: CollectionReference,
        keepingDocumentID: String? = nil,
        completion: @escaping (Bool) -> Void
    ) {
        collection.limit(to: 200).getDocuments(source: .server) { [weak self] snapshot, error in
            guard let self else { return }
            guard error == nil, let snapshot else {
                completion(false)
                return
            }
            let documents = snapshot.documents.filter { $0.documentID != keepingDocumentID }
            guard !documents.isEmpty else {
                completion(true)
                return
            }
            let batch = self.db.batch()
            documents.forEach { batch.deleteDocument($0.reference) }
            batch.commit { error in
                guard error == nil else {
                    completion(false)
                    return
                }
                self.deleteCollectionContents(
                    collection, keepingDocumentID: keepingDocumentID, completion: completion
                )
            }
        }
    }
}
