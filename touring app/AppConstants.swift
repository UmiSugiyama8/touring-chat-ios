import Foundation

let displayNameKey = "displayName"
let profileColorKey = "profileColor"
let profileIconKey = "profileIcon"
let notifyArrivalKey = "notifyArrival"
let notifyDelayKey = "notifyDelay"
let notifyTroubleKey = "notifyTrouble"
let notifyGroupUpdateKey = "notifyGroupUpdate"
let groupsStorageKey = "touringGroups"
let joinedGroupIDsKey = "joinedGroupIDs"
let deviceIDKey = "deviceID"
let hasSeenTutorialKey = "hasSeenTutorial"
let termsAgreementVersionKey = "termsAgreementVersion"
let currentTermsAgreementVersion = "2026-05-25"

func currentDeviceID() -> String {
    if let savedID = UserDefaults.standard.string(forKey: deviceIDKey) {
        return savedID
    }

    let newID = UUID().uuidString
    UserDefaults.standard.set(newID, forKey: deviceIDKey)
    return newID
}
