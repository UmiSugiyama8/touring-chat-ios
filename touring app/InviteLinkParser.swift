import Foundation

enum InviteLinkParser {
    static let scheme = "touringapp"

    static func inviteURL(for code: String) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "join"
        components.queryItems = [
            URLQueryItem(name: "code", value: code)
        ]

        return components.url ?? URL(string: "\(scheme)://join?code=\(code)")!
    }

    static func code(from url: URL) -> String? {
        guard url.scheme?.lowercased() == scheme else { return nil }
        guard url.host?.lowercased() == "join" else { return nil }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let queryCode = components?.queryItems?.first { $0.name == "code" }?.value
        let pathCode = url.pathComponents.dropFirst().first
        let code = queryCode ?? pathCode ?? ""
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)

        return trimmed.isEmpty ? nil : trimmed
    }
}
