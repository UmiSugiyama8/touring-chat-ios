import Foundation
import Combine
import CoreLocation
import WatchConnectivity

final class PhoneWatchConnectivityManager: NSObject, ObservableObject {
    static let shared = PhoneWatchConnectivityManager()

    private let session: WCSession? = WCSession.isSupported() ? WCSession.default : nil
    private let firebaseService = FirebaseGroupService()
    private let locationSharingManager = LocationSharingManager()
    private var displayName = ""

    func configure(displayName: String) {
        self.displayName = displayName

        guard let session else { return }
        session.delegate = self
        session.activate()
    }

    func updateDisplayName(_ displayName: String) {
        self.displayName = displayName
    }

    func sendGroups(_ groups: [TouringGroup]) {
        guard let session else { return }

        let payload = groups.map { group -> [String: Any] in
            var item: [String: Any] = [
                "id": group.id.uuidString,
                "name": group.name,
                "memberCount": group.memberCount,
                "arrivedCount": group.arrivedCount,
                "lastMessageText": group.lastMessageText,
                "meetingPlaceName": group.meetingPlaceName
            ]

            if let meetingTime = group.meetingTime {
                item["meetingTime"] = meetingTime.timeIntervalSince1970
            }

            return item
        }

        do {
            try session.updateApplicationContext(["groups": payload])
        } catch {
            print("Failed to send groups to watch: \(error)")
        }
    }

    private func handleCommand(_ command: [String: Any], replyHandler: (([String: Any]) -> Void)? = nil) {
        guard let groupIDString = command["groupID"] as? String,
              let groupID = UUID(uuidString: groupIDString),
              let text = command["text"] as? String else {
            replyHandler?(["success": false, "message": "送信内容を確認できませんでした"])
            return
        }

        let senderName = displayName.isEmpty ? "Apple Watch" : displayName
        if text == "今ここにいる" {
            sendCurrentLocation(groupID: groupID, senderName: senderName, replyHandler: replyHandler)
            return
        }

        sendText(text, groupID: groupID, senderName: senderName, replyHandler: replyHandler)
    }

    private func sendCurrentLocation(groupID: UUID, senderName: String, replyHandler: (([String: Any]) -> Void)?) {
        locationSharingManager.requestCurrentLocation { [weak self] result in
            guard let self else { return }

            switch result {
            case .success(let location):
                let coordinate = location.coordinate
                let url = "https://maps.apple.com/?ll=\(coordinate.latitude),\(coordinate.longitude)"
                sendText("今ここにいる: \(url)", groupID: groupID, senderName: senderName, replyHandler: replyHandler)
            case .failure:
                replyHandler?(["success": false, "message": "現在地を取得できませんでした"])
            }
        }
    }

    private func sendText(_ text: String, groupID: UUID, senderName: String, replyHandler: (([String: Any]) -> Void)?) {
        firebaseService.sendMessage(groupID: groupID, text: text, senderName: senderName) { [weak self] success in
            guard success else {
                replyHandler?(["success": false, "message": "送信できませんでした"])
                return
            }

            if text == "到着" {
                self?.firebaseService.updateArrivalStatus(groupID: groupID, isArrived: true)
            }

            replyHandler?(["success": true, "message": "送信しました"])
        }
    }
}

extension PhoneWatchConnectivityManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error {
            print("Watch session activation failed: \(error)")
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        DispatchQueue.main.async {
            self.handleCommand(message)
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        DispatchQueue.main.async {
            self.handleCommand(message, replyHandler: replyHandler)
        }
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        DispatchQueue.main.async {
            self.handleCommand(userInfo)
        }
    }
}
