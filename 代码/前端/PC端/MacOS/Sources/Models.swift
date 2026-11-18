//
//  Models.swift
//  ZhixuMac
//
//  Created by Jobs on 2026年11月18日，星期三.
//

import Foundation

struct Product: Codable, Identifiable {

    let id: String
    var category_id: String
    var name: String
    var price_minor: Int
    var kind: String
    var version: Int
    var active: Bool
    var in_stock: Bool
    var summary: String
    var description: String
    var image: String
    var sections: [Section]

    struct Section: Codable {

        let title: String
        let body: String
    }

    var price: String {
        return String(format: "¥%.2f", Double(price_minor) / 100)
    }
}

struct Buyer: Codable {

    let id: String
    var name: String
    var username: String?
    var email: String?
    var avatar_url: String?
    var phone: String?
    var mood: String?
}

struct ShopBanner: Codable, Identifiable {

    let id: String
    let title: String
    let image: String
    let target_url: String
}

struct ShopOrder: Codable, Identifiable {

    let id: String
    var owner_id: String?
    var product_snapshot: Product
    var amount_minor: Int
    var status: String
    var fulfillment_status: String
    var version: Int
    var editable: Bool?
    var requirements: String?
    var contact: String?
    var delivery_requirements: String?
    var delivery_text: String?
}

struct APIError: LocalizedError {

    let status: Int
    let message: String

    var errorDescription: String? {
        return message
    }

    var mayBeOffline: Bool {
        return status == 0 || status >= 500
    }
}

enum NativeAPI {

    // Transport and JSON validation stay outside view code.
    static func request(base: String,
                        token: String,
                        timeout: Double,
                        path: String,
                        body: [String: Any]? = nil,
                        key: String? = nil,
                        method: String? = nil) async throws -> [String: Any] {
        guard let url = URL(string: base.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + path) else {
            throw APIError(status: 422, message: "Invalid API URL")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout / 1000
        request.httpMethod = method ?? (body == nil ? "GET" : "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !token.isEmpty {
            request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        }
        if let key {
            request.setValue(key, forHTTPHeaderField: "Idempotency-Key")
        }
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw APIError(status: 0, message: "Invalid response")
        }
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard (200..<300).contains(response.statusCode), let object else {
            throw APIError(status: response.statusCode,
                           message: object?["message"] as? String ?? String(describing: object?["error"] ?? response.statusCode))
        }
        return object
    }

    static func decode<T: Decodable>(_ type: T.Type,
                                     from value: Any?) throws -> T {
        guard let value else {
            throw APIError(status: 0, message: "Invalid response")
        }
        return try JSONDecoder().decode(type, from: JSONSerialization.data(withJSONObject: value))
    }
}
