import FirebaseAuth
import Foundation

enum FirebaseAuthService {
    static var currentUID: String {
        Auth.auth().currentUser?.uid ?? ""
    }

    static func signInIfNeeded(completion: ((Bool) -> Void)? = nil) {
        if Auth.auth().currentUser != nil {
            DispatchQueue.main.async {
                completion?(true)
            }
            return
        }

        Auth.auth().signInAnonymously { _, error in
            if let error {
                print("Failed to sign in anonymously: \(error)")
            }

            DispatchQueue.main.async {
                completion?(error == nil)
            }
        }
    }
}
