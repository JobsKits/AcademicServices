//
//  LocalDemoAuth.swift
//  ZhixuMac
//
//  Created by Jobs on 2026年11月18日，星期三.
//

import CryptoKit
import Foundation

@MainActor final class LocalDemoAuth {

    private struct Account {

        var user: Buyer
        let salt: String
        var hash: SHA256.Digest
    }

    private struct Challenge {

        let code: String
        let issued: Date
        var attempts = 0
    }

    private var accounts: [String: Account] = [:]
    private var challenges: [String: Challenge] = [:]

    func login(account: String,
               password: String,
               seedCredentials: [String: String]) throws -> Buyer {
        let normalized = account.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let expected = seedCredentials[normalized], password == expected {
            return Buyer(id: "demo-" + normalized, name: normalized, username: normalized)
        }
        if let saved = accounts.values.first(where: { $0.user.email == normalized || $0.user.username?.lowercased() == normalized }),
           SHA256.hash(data: Data((saved.salt + password).utf8)) == saved.hash {
            return saved.user
        }
        throw APIError(status: 401, message: "loginHint")
    }

    func code(email: String,
              purpose: String) throws -> [String: Any] {
        let email = try validateEmail(email)
        guard ["register", "reset_password"].contains(purpose) else {
            throw APIError(status: 422, message: "required")
        }
        let key = email + ":" + purpose
        if let previous = challenges[key], Date().timeIntervalSince(previous.issued) < 60 {
            throw APIError(status: 429, message: "codeSent")
        }
        let code = String(format: "%06d", Int.random(in: 0...999999))
        challenges[key] = Challenge(code: code, issued: Date())
        return ["delivery": "demo", "demo_code": code, "retry_after": 60]
    }

    func register(_ values: [String: String]) throws {
        let email = try validateEmail(values["email"] ?? "")
        let username = (values["username"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let password = try validatePassword(values)
        guard (3...32).contains(username.count), username.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }),
              !["admin", "customer", "customer2"].contains(username.lowercased()), accounts[email] == nil,
              !accounts.values.contains(where: { $0.user.username?.lowercased() == username.lowercased() }) else {
            throw APIError(status: 422, message: "required")
        }
        try verify(email: email, purpose: "register", code: values["code"] ?? "")
        let salt = UUID().uuidString
        accounts[email] = Account(user: Buyer(id: "demo-" + UUID().uuidString, name: username, username: username, email: email),
                                  salt: salt,
                                  hash: SHA256.hash(data: Data((salt + password).utf8)))
        challenges.removeValue(forKey: email + ":register")
    }

    func reset(_ values: [String: String]) throws {
        let email = try validateEmail(values["email"] ?? "")
        let password = try validatePassword(values)
        try verify(email: email, purpose: "reset_password", code: values["code"] ?? "")
        guard var saved = accounts[email] else {
            throw APIError(status: 422, message: "required")
        }
        saved.hash = SHA256.hash(data: Data((saved.salt + password).utf8))
        accounts[email] = saved
        challenges.removeValue(forKey: email + ":reset_password")
    }

    private func validateEmail(_ value: String) throws -> String {
        let email = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard email.range(of: "^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$", options: .regularExpression) != nil else {
            throw APIError(status: 422, message: "required")
        }
        return email
    }

    private func validatePassword(_ values: [String: String]) throws -> String {
        let password = values["password"] ?? ""
        guard password.count >= 8, password.utf8.count <= 512, password == values["confirm_password"] else {
            throw APIError(status: 422, message: "required")
        }
        return password
    }

    private func verify(email: String,
                        purpose: String,
                        code: String) throws {
        let key = email + ":" + purpose
        guard var challenge = challenges[key], challenge.attempts < 5, Date().timeIntervalSince(challenge.issued) < 600 else {
            throw APIError(status: 422, message: "required")
        }
        challenge.attempts += 1
        challenges[key] = challenge
        guard challenge.code == code else {
            throw APIError(status: 422, message: "required")
        }
    }
}
