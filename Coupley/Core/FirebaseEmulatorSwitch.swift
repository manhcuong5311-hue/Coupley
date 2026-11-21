//
//  FirebaseEmulatorSwitch.swift
//  Coupley
//
//  DEBUG only: the `-useFirestoreEmulator` launch argument points Auth and
//  Firestore at the local Firebase emulators, under the `demo-coupley-rules`
//  project, before anything else touches Firebase. Release builds contain
//  none of this file.
//
//  Start the emulators from the repo root:
//    firebase emulators:start --only auth,firestore,functions --project demo-coupley-rules
//  then launch with `-useFirestoreEmulator` (scheme → Run → Arguments, or
//  `xcrun simctl launch <device> <bundle id> -useFirestoreEmulator`). A
//  physical device adds `-emulatorHost <the Mac's IP>`; a simulator shares
//  127.0.0.1 with the Mac.
//
//  The `demo-` project keeps everything offline: the real project's data is
//  unreachable, and the SDK's on-disk cache is per project id, so emulator
//  data never mixes with real data. Test accounts use the app's
//  email/password sign-up (Sign in with Apple and Google do not work against
//  the Auth emulator). There is no FCM token in this mode.
//

#if DEBUG

import Foundation
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore

enum FirebaseEmulatorSwitch {

    /// The emulators' project: the CLI's rules and function triggers apply
    /// to the app's writes, and the real project is never reached.
    static let projectID = "demo-coupley-rules"
    static let authPort = 9099
    static let firestorePort = 8080

    private static let requestArgument = "-useFirestoreEmulator"
    private static let hostArgument = "-emulatorHost"
    private static let defaultHost = "127.0.0.1"

    /// The `-useFirestoreEmulator` launch argument was passed.
    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains(requestArgument)
    }

    /// `-emulatorHost <ip>` (for a physical device), default "127.0.0.1".
    static var host: String {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: hostArgument),
              arguments.indices.contains(index + 1) else { return defaultHost }
        let value = arguments[index + 1].trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty, !value.hasPrefix("-") else { return defaultHost }
        return value
    }

    /// True once `configureFirebase()` ran (the Debug menu's Status row).
    static private(set) var isActive = false

    /// Replaces `FirebaseApp.configure()` when `isRequested`. Builds the
    /// options from GoogleService-Info.plist under the demo project, then
    /// points Auth (9099) and Firestore (8080) at `host` with SSL off before
    /// the first Auth or Firestore call.
    static func configureFirebase() {
        guard !isActive else { return }
        guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let options = FirebaseOptions(contentsOfFile: path) else {
            // Never fall back to the real project: an emulator run must not
            // be able to reach production data.
            fatalError("FirebaseEmulatorSwitch: GoogleService-Info.plist is missing or unreadable.")
        }
        options.projectID = projectID
        FirebaseApp.configure(options: options)

        let emulatorHost = host
        Auth.auth().useEmulator(withHost: emulatorHost, port: authPort)
        // Firestore's useEmulator(withHost:port:) sets only the host (SDK
        // 12.11): SSL stays on and every connection fails its handshake
        // against the emulator's plain port. Set both through settings,
        // before the first Firestore read or write.
        let firestore = Firestore.firestore()
        let settings = firestore.settings
        settings.host = "\(emulatorHost):\(firestorePort)"
        settings.isSSLEnabled = false
        firestore.settings = settings

        isActive = true
        print("[FirebaseEmulatorSwitch] Auth \(emulatorHost):\(authPort), Firestore \(emulatorHost):\(firestorePort), project \(projectID)")
    }
}

#endif
