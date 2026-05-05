import Foundation
import os
import Security
import WebKit

// MARK: - CookieArchiveWriteCoordinator

/// Tracks the last persisted archive so identical cookie backups can be skipped safely.
final class CookieArchiveWriteCoordinator: @unchecked Sendable {
    private let lock = NSLock()
    private var lastSavedArchiveData: Data?
    private var pendingArchiveData: Data?

    @discardableResult
    func beginSaveIfNeeded(_ data: Data) -> Bool {
        self.lock.lock()
        defer { self.lock.unlock() }

        guard self.pendingArchiveData != data, self.lastSavedArchiveData != data else {
            return false
        }

        self.pendingArchiveData = data
        return true
    }

    func finishSave(_ data: Data, success: Bool) {
        self.lock.lock()
        defer { self.lock.unlock() }

        if self.pendingArchiveData == data {
            self.pendingArchiveData = nil
        }

        if success {
            self.lastSavedArchiveData = data
        }
    }

    func seedPersistedArchive(_ data: Data?) {
        self.lock.lock()
        defer { self.lock.unlock() }

        self.lastSavedArchiveData = data

        if data == nil || self.pendingArchiveData == data {
            self.pendingArchiveData = nil
        }
    }
}

// MARK: - AuthCookieImportResult

struct AuthCookieImportResult: Equatable {
    let importedCount: Int
    let importedCookieNames: [String]
}

// MARK: - ManualCookieCandidate

private struct ManualCookieCandidate {
    let name: String
    let value: String
    let domain: String
    let path: String
    let expiresDate: Date?
    let isSecure: Bool
}

// MARK: - AuthCookieImportError

enum AuthCookieImportError: LocalizedError, Equatable {
    case emptyInput
    case noSupportedCookies
    case missingPrimaryAuthCookie

    var errorDescription: String? {
        switch self {
        case .emptyInput:
            "Paste one or more YouTube or Google auth cookies first."
        case .noSupportedCookies:
            "No supported YouTube Music auth cookies were found. Include SAPISID or __Secure-3PAPISID from Safari."
        case .missingPrimaryAuthCookie:
            "The import needs SAPISID or __Secure-3PAPISID so YouTube Music API requests can be signed."
        }
    }
}

// MARK: - KeychainCookieStorage

/// Securely stores auth cookies in the macOS Keychain.
/// Provides encryption at rest and app-specific access control.
enum KeychainCookieStorage {
    private static let logger = DiagnosticsLogger.webKit
    private static let writeCoordinator = CookieArchiveWriteCoordinator()

    /// Keychain service identifier for cookie storage.
    private static let service = "com.melboonchan.boombox.auth-cookies"

    /// Keychain account identifier.
    private static let account = "youtube-music-cookies"

    /// Cookie names required for YouTube Music authentication.
    static let authCookieNames = Set([
        "SAPISID", "__Secure-3PAPISID", "__Secure-1PAPISID",
        "__Secure-3PSID", "__Secure-1PSID", "SID", "HSID", "SSID", "APISID",
        "SIDCC", "__Secure-3PSIDCC", "__Secure-1PSIDCC", "LOGIN_INFO",
    ])

    private static let defaultManualImportDomain = ".youtube.com"

    static func isValidAuthCookie(_ cookie: HTTPCookie, now: Date = Date()) -> Bool {
        guard self.authCookieNames.contains(cookie.name) else { return false }
        guard self.isAllowedAuthCookieDomain(cookie.domain) else { return false }
        if let expiresDate = cookie.expiresDate, expiresDate < now {
            return false
        }
        return true
    }

    static func isAllowedAuthCookieDomain(_ domain: String) -> Bool {
        var normalizedDomain = domain
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        while normalizedDomain.hasPrefix(".") {
            normalizedDomain.removeFirst()
        }

        return normalizedDomain == "youtube.com"
            || normalizedDomain == "google.com"
            || normalizedDomain.hasSuffix(".youtube.com")
            || normalizedDomain.hasSuffix(".google.com")
    }

    static func makeManualAuthCookies(from rawText: String) throws -> [HTTPCookie] {
        let trimmedText = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            throw AuthCookieImportError.emptyInput
        }

        let candidates = Self.parseManualCookieCandidates(from: trimmedText)
        let now = Date()
        var cookiesByKey: [String: HTTPCookie] = [:]
        var orderedKeys: [String] = []

        for candidate in candidates {
            guard let cookie = Self.makeManualCookie(from: candidate),
                  Self.isValidAuthCookie(cookie, now: now)
            else {
                continue
            }

            let key = "\(cookie.domain)|\(cookie.path)|\(cookie.name)"
            if cookiesByKey[key] == nil {
                orderedKeys.append(key)
            }
            cookiesByKey[key] = cookie
        }

        let cookies = orderedKeys.compactMap { cookiesByKey[$0] }
        guard !cookies.isEmpty else {
            throw AuthCookieImportError.noSupportedCookies
        }

        return cookies
    }

    private static func parseManualCookieCandidates(from rawText: String) -> [ManualCookieCandidate] {
        rawText
            .components(separatedBy: .newlines)
            .flatMap { line -> [ManualCookieCandidate] in
                let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedLine.isEmpty, !trimmedLine.hasPrefix("#") else { return [] }

                if trimmedLine.lowercased().hasPrefix("cookie:") {
                    let cookieHeader = String(trimmedLine.dropFirst("cookie:".count))
                    return Self.parseCookiePairs(from: cookieHeader)
                }

                if trimmedLine.contains("\t"),
                   let netscapeCookie = Self.parseNetscapeCookieLine(trimmedLine)
                {
                    return [netscapeCookie]
                }

                return Self.parseCookiePairs(from: trimmedLine)
            }
    }

    private static func parseNetscapeCookieLine(_ line: String) -> ManualCookieCandidate? {
        let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 7 else { return nil }

        let domain = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let path = parts[2].trimmingCharacters(in: .whitespacesAndNewlines)
        let isSecure = parts[3].caseInsensitiveCompare("TRUE") == .orderedSame
        let expiresDate: Date? = if let timestamp = TimeInterval(parts[4]), timestamp > 0 {
            Date(timeIntervalSince1970: timestamp)
        } else {
            nil
        }

        return ManualCookieCandidate(
            name: parts[5].trimmingCharacters(in: .whitespacesAndNewlines),
            value: parts[6].trimmingCharacters(in: .whitespacesAndNewlines),
            domain: domain,
            path: path,
            expiresDate: expiresDate,
            isSecure: isSecure
        )
    }

    private static func parseCookiePairs(from text: String) -> [ManualCookieCandidate] {
        let defaultExpiration = Date(timeIntervalSinceNow: 60 * 60 * 24 * 180)

        return text
            .split(separator: ";", omittingEmptySubsequences: true)
            .compactMap { pair -> ManualCookieCandidate? in
                let trimmedPair = pair.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let equalsIndex = trimmedPair.firstIndex(of: "=") else { return nil }

                let name = trimmedPair[..<equalsIndex].trimmingCharacters(in: .whitespacesAndNewlines)
                let valueStart = trimmedPair.index(after: equalsIndex)
                let value = trimmedPair[valueStart...].trimmingCharacters(in: .whitespacesAndNewlines)

                return ManualCookieCandidate(
                    name: String(name),
                    value: String(value),
                    domain: Self.defaultManualImportDomain,
                    path: "/",
                    expiresDate: defaultExpiration,
                    isSecure: true
                )
            }
    }

    private static func makeManualCookie(from candidate: ManualCookieCandidate) -> HTTPCookie? {
        let invalidCharacters = CharacterSet.controlCharacters.union(.newlines)
        let name = candidate.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = candidate.value.trimmingCharacters(in: .whitespacesAndNewlines)
        let domain = candidate.domain.trimmingCharacters(in: .whitespacesAndNewlines)
        let path = candidate.path.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !name.isEmpty,
              !value.isEmpty,
              !domain.isEmpty,
              value.unicodeScalars.allSatisfy({ !invalidCharacters.contains($0) }),
              Self.isAllowedAuthCookieDomain(domain)
        else {
            return nil
        }

        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: name,
            .value: value,
            .domain: domain,
            .path: path.isEmpty ? "/" : path,
        ]

        if candidate.isSecure || name.hasPrefix("__Secure-") {
            properties[.secure] = "TRUE"
        }

        if let expiresDate = candidate.expiresDate {
            properties[.expires] = expiresDate
        }

        return HTTPCookie(properties: properties)
    }

    /// Creates the serialized archive we persist to Keychain.
    /// Returns nil if there are no valid auth cookies to store.
    static func makeArchiveData(from cookies: [HTTPCookie]) -> (data: Data, cookieCount: Int)? {
        let now = Date()
        let authCookies = cookies.filter { cookie in
            Self.isValidAuthCookie(cookie, now: now)
        }

        guard !authCookies.isEmpty else { return nil }

        let cookieData = authCookies.compactMap { cookie -> Data? in
            guard let properties = cookie.properties else { return nil }
            var stringProperties: [String: Any] = [:]
            for (key, value) in properties {
                stringProperties[key.rawValue] = value
            }
            // Note: Cookie properties dictionary contains types like String, Date, Number, Bool
            // which all support NSSecureCoding. However, using requiringSecureCoding: false here
            // because [String: Any] doesn't directly conform to NSSecureCoding.
            // The unarchive side uses explicit class allowlists for security.
            return try? NSKeyedArchiver.archivedData(
                withRootObject: stringProperties,
                requiringSecureCoding: false
            )
        }

        guard !cookieData.isEmpty,
              let data = try? NSKeyedArchiver.archivedData(
                  withRootObject: cookieData as NSArray,
                  requiringSecureCoding: true
              )
        else {
            Self.logger.error("Failed to serialize cookies for Keychain")
            return nil
        }

        return (data: data, cookieCount: cookieData.count)
    }

    /// Saves YouTube auth cookies to the Keychain.
    static func saveCookies(_ cookies: [HTTPCookie]) {
        guard let archive = makeArchiveData(from: cookies) else { return }

        _ = Self.saveArchiveData(archive.data, cookieCount: archive.cookieCount)
    }

    /// Saves an already-serialized cookie archive to the Keychain.
    @discardableResult
    static func saveArchiveData(_ data: Data, cookieCount: Int) -> Bool {
        guard self.writeCoordinator.beginSaveIfNeeded(data) else {
            self.logger.debug("Skipping Keychain cookie save because archive is already saved or a write is in progress")
            return false
        }

        // Update existing item or add new one (atomic upsert)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if status == errSecItemNotFound {
            var newQuery = query
            for (key, value) in attributes {
                newQuery[key] = value
            }
            status = SecItemAdd(newQuery as CFDictionary, nil)
        }

        let didSave = status == errSecSuccess
        self.writeCoordinator.finishSave(data, success: didSave)

        if didSave {
            Self.logger.debug("Saved \(cookieCount) auth cookies to Keychain")
            return true
        } else {
            Self.logger.error("Failed to save cookies to Keychain: \(status)")
            return false
        }
    }

    /// Returns `true` if a Keychain item exists for our cookie storage.
    static func hasCookieItem() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
            kSecReturnData as String: false,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    /// Loads the raw serialized cookie archive data from Keychain.
    static func loadArchiveData() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            Self.writeCoordinator.seedPersistedArchive(nil)
            if status == errSecItemNotFound {
                Self.logger.info("No cookies found in Keychain (first run or signed out)")
            } else {
                Self.logger.error("Failed to load cookies from Keychain: \(status)")
            }
            return nil
        }

        guard let data = result as? Data else {
            Self.writeCoordinator.seedPersistedArchive(nil)
            Self.logger.error("Loaded Keychain cookie item had an unexpected type")
            return nil
        }

        Self.writeCoordinator.seedPersistedArchive(data)
        return data
    }

    /// Decodes cookies from a serialized archive created by `makeArchiveData(from:)`.
    static func decodeCookies(from archiveData: Data) -> [HTTPCookie] {
        guard let cookieDataArray = try? NSKeyedUnarchiver.unarchivedObject(
            ofClasses: [NSArray.self, NSData.self],
            from: archiveData
        ) as? [Data]
        else {
            self.logger.error("Failed to decode cookie archive data")
            return []
        }

        let cookies = cookieDataArray.compactMap { cookieData -> HTTPCookie? in
            guard let stringProperties = try? NSKeyedUnarchiver.unarchivedObject(
                ofClasses: [NSDictionary.self, NSString.self, NSDate.self, NSNumber.self],
                from: cookieData
            ) as? [String: Any] else {
                return nil
            }

            var convertedProperties: [HTTPCookiePropertyKey: Any] = [:]
            for (key, value) in stringProperties {
                convertedProperties[HTTPCookiePropertyKey(key)] = value
            }
            return HTTPCookie(properties: convertedProperties)
        }

        if !cookies.isEmpty {
            Self.logger.info("Loaded \(cookies.count) auth cookies from Keychain")
        }
        return cookies
    }

    /// Retrieves YouTube auth cookies from the Keychain.
    /// Returns the cookies if found, nil otherwise.
    static func loadCookies() -> [HTTPCookie]? {
        guard let archiveData = loadArchiveData() else { return nil }
        let cookies = Self.decodeCookies(from: archiveData)
        return cookies.isEmpty ? nil : cookies
    }

    /// Deletes cookies from the Keychain.
    static func deleteCookies() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
        ]

        let status = SecItemDelete(query as CFDictionary)
        Self.writeCoordinator.seedPersistedArchive(nil)

        if status == errSecSuccess {
            Self.logger.info("Deleted cookies from Keychain")
        } else if status != errSecItemNotFound {
            Self.logger.error("Failed to delete cookies from Keychain: \(status)")
        }
    }
}
