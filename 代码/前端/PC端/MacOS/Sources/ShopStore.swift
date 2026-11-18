//
//  ShopStore.swift
//  ZhixuMac
//
//  Created by Jobs on 2026年11月18日，星期三.
//

import Foundation
import SwiftUI

@MainActor final class ShopStore: ObservableObject {

    @Published var products: [Product] = []
    @Published var orders: [ShopOrder] = []
    @Published var banners: [ShopBanner]?
    @Published var user: Buyer?
    @Published var online = false
    @Published var busy = false
    @Published var profileBusy = false
    @Published var demoAvailable = false
    @Published var demoCredentials: [String: String] = [:]
    @Published var error = ""
    @Published var language: String {
        didSet {
            UserDefaults.standard.set(language, forKey: "language")
        }
    }
    @Published var theme: String {
        didSet {
            UserDefaults.standard.set(theme, forKey: "theme")
        }
    }
    var api: String
    var timeout: Double
    private var token = ""
    private var epoch = 0
    private var readRevision = 0
    private var bannerRevision = 0
    private var profileRevision = 0
    private var activeWrite: UUID?
    private var liveSession = false
    private var explicitDemoMode: Bool?
    private var localDemoAuth = LocalDemoAuth()
    private var demoOrders: [ShopOrder] = []
    private var demoProfiles: [String: Buyer] = [:]
    private var pending: (path: String, body: [String: Any], key: String)?
    private let strings: [String: [String: String]]
    private let seed: [Product]
    let languages = ["zh", "zh-Hant", "bo", "en", "ja", "fr", "es", "de", "ru", "ko"]
    let languageNames = ["简体中文", "繁體中文", "བོད་ཡིག", "English", "日本語", "Français", "Español", "Deutsch", "Русский", "한국어"]

    var hasPendingWrite: Bool {
        return pending != nil
    }

    var localEndpoint: Bool {
        guard let host = URL(string: api)?.host?.lowercased() else {
            return false
        }
        if ["localhost", "::1", "[::1]"].contains(host) {
            return true
        }
        let parts = host.split(separator: ".")
        return parts.count == 4 && parts.first == "127" && parts.allSatisfy { part in
            guard let number = Int(part), String(number) == part else {
                return false
            }
            return (0...255).contains(number)
        }
    }

    init() {
        let resource = Bundle.main.resourceURL!
        let tableData = try! Data(contentsOf: resource.appendingPathComponent("shop_strings.json"))
        strings = try! JSONDecoder().decode([String: [String: String]].self, from: tableData)
        seed = try! JSONDecoder().decode([Product].self, from: Data(contentsOf: resource.appendingPathComponent("products.json")))
        products = seed
        language = UserDefaults.standard.string(forKey: "language") ?? "zh"
        theme = UserDefaults.standard.string(forKey: "theme") ?? "system"
        api = UserDefaults.standard.string(forKey: "api") ?? "http://127.0.0.1:8080/api/v1"
        timeout = UserDefaults.standard.object(forKey: "timeout") as? Double ?? 2500
        if !localEndpoint {
            products = []
        }
    }

    func t(_ key: String) -> String {
        return strings[language]?[key] ?? strings["zh"]?[key] ?? key
    }

    func request(_ path: String,
                 body: [String: Any]? = nil,
                 key: String? = nil,
                 method: String? = nil) async throws -> [String: Any] {
        let requestEpoch = epoch
        do {
            let response = try await NativeAPI.request(base: api,
                                               token: token,
                                               timeout: timeout,
                                               path: path,
                                               body: body,
                                               key: key,
                                               method: method)
            guard requestEpoch == epoch else {
                throw APIError(status: 499, message: t("reselect"))
            }
            return response
        } catch let failure as APIError {
            if requestEpoch != epoch {
                throw APIError(status: 499, message: t("reselect"))
            }
            if failure.status == 401 {
                logout()
            }
            throw failure
        } catch {
            if requestEpoch != epoch {
                throw APIError(status: 499, message: t("reselect"))
            }
            throw error
        }
    }

    func refresh() async {
        let requestEpoch = epoch
        readRevision += 1
        let requestRevision = readRevision
        do {
            let response = try await request("/products")
            let receivedProducts = try NativeAPI.decode([Product].self, from: response["products"])
            guard requestEpoch == epoch, requestRevision == readRevision else {
                return
            }
            var receivedOrders = orders
            if liveSession {
                let response = try await request("/shop-orders")
                receivedOrders = try NativeAPI.decode([ShopOrder].self, from: response["orders"])
                guard receivedOrders.allSatisfy({ $0.owner_id == user?.id }) else {
                    throw APIError(status: 0, message: t("unexpected_response"))
                }
            }
            guard requestEpoch == epoch, requestRevision == readRevision else {
                return
            }
            products = receivedProducts
            orders = receivedOrders
            online = true
        } catch {
            guard requestEpoch == epoch, requestRevision == readRevision else {
                return
            }
            if online {
                self.error = t("updateFailed")
            } else {
                orders = demoOrders
            }
        }
    }

    func login(_ values: [String: String]) async throws {
        logout()
        let loginEpoch = epoch
        token = ""
        do {
            let response = try await request("/auth/login", body: values)
            guard let received = response["token"] as? String,
                  (response["user"] as? [String: Any])?["role"] as? String == "customer" else {
                throw APIError(status: 403, message: t("customer"))
            }
            user = try NativeAPI.decode(Buyer.self, from: response["user"])
            token = received
            liveSession = true
        } catch {
            if let failure = error as? APIError, !failure.mayBeOffline {
                throw failure
            }
            await refreshDemoMode()
            guard loginEpoch == epoch else {
                throw APIError(status: 499, message: t("reselect"))
            }
            guard demoAvailable, localEndpoint else {
                throw error
            }
            do {
                user = try localDemoAuth.login(account: values["account"] ?? "", password: values["password"] ?? "", seedCredentials: demoCredentials)
                if let identity = user?.id, let saved = demoProfiles[identity] {
                    user = saved
                }
            } catch let failure as APIError {
                throw APIError(status: failure.status, message: t(failure.message))
            }
            guard user != nil else {
                throw APIError(status: 401, message: t("loginHint"))
            }
            liveSession = false
            online = false
            products = seed
            orders = demoOrders
        }
        await refresh()
    }

    func refreshDemoMode() async {
        let requestEpoch = epoch
        guard localEndpoint else {
            demoAvailable = false
            demoCredentials = [:]
            return
        }
        do {
            let response = try await request("/shop-config")
            guard let enabled = response["demo_mode"] as? Bool else {
                demoAvailable = false
                return
            }
            explicitDemoMode = enabled
            demoAvailable = enabled
            let credentials = response["demo_credentials"] as? [[String: String]] ?? []
            demoCredentials = enabled ? Dictionary(credentials.filter { $0["role"] == "customer" }.compactMap { item in
                guard let account = item["account"], let password = item["password"] else {
                    return nil
                }
                return (account, password)
            }, uniquingKeysWith: { first, _ in first }) : [:]
            if !enabled && !online {
                products = []
            }
            if !enabled && user != nil && !liveSession {
                logout()
            }
        } catch {
            guard requestEpoch == epoch else {
                return
            }
            if let failure = error as? APIError, !failure.mayBeOffline {
                demoAvailable = false
                return
            }
            demoAvailable = localEndpoint && explicitDemoMode != false
            if demoAvailable && demoCredentials.isEmpty {
                demoCredentials = ["customer": "demo-customer", "customer2": "demo-customer"]
            }
        }
    }

    func authEmailCode(email: String,
                       purpose: String) async throws -> [String: Any] {
        do {
            return try await request("/auth/email-code", body: ["email": email, "purpose": purpose])
        } catch {
            if let failure = error as? APIError, !failure.mayBeOffline {
                throw failure
            }
            guard localEndpoint, demoAvailable else {
                throw error
            }
            do {
                return try localDemoAuth.code(email: email, purpose: purpose)
            } catch let failure as APIError {
                throw APIError(status: failure.status, message: t(failure.message))
            }
        }
    }

    func completeAccount(_ values: [String: String],
                         reset: Bool) async throws {
        do {
            _ = try await request(reset ? "/auth/reset-password" : "/auth/register", body: values)
        } catch {
            if let failure = error as? APIError, !failure.mayBeOffline {
                throw failure
            }
            guard localEndpoint, demoAvailable else {
                throw error
            }
            do {
                if reset {
                    try localDemoAuth.reset(values)
                } else {
                    try localDemoAuth.register(values)
                }
            } catch let failure as APIError {
                throw APIError(status: failure.status, message: t(failure.message))
            }
        }
        if reset {
            logout()
        }
    }

    func refreshBanners() async {
        bannerRevision += 1
        let requestRevision = bannerRevision
        do {
            let response = try await request("/banners")
            guard requestRevision == bannerRevision else {
                return
            }
            banners = try NativeAPI.decode([ShopBanner].self, from: response["banners"])
        } catch {
            // Keep the last known public configuration; nil retains local artwork.
        }
    }

    func saveProfile(_ values: [String: String]) async throws {
        let allowed = Set(["username", "email", "phone", "mood", "avatar"])
        guard !values.isEmpty, Set(values.keys).isSubset(of: allowed) else {
            throw APIError(status: 422, message: t("required"))
        }
        guard let identity = user?.id, !profileBusy else {
            throw APIError(status: 409, message: t("pendingWrite"))
        }
        let operationEpoch = epoch
        profileRevision += 1
        let revision = profileRevision
        profileBusy = true
        let body = values
        defer {
            if revision == profileRevision {
                profileBusy = false
            }
        }
        do {
            let response = try await request("/auth/profile", body: body, method: "PUT")
            let received = try NativeAPI.decode(Buyer.self, from: response["user"])
            guard operationEpoch == epoch, revision == profileRevision, user?.id == identity else {
                throw APIError(status: 499, message: t("reselect"))
            }
            guard received.id == identity else {
                throw APIError(status: 0, message: t("unexpected_response"))
            }
            user = received
        } catch {
            guard operationEpoch == epoch, revision == profileRevision, user?.id == identity else {
                throw APIError(status: 499, message: t("reselect"))
            }
            if let failure = error as? APIError, !failure.mayBeOffline {
                throw failure
            }
            // A real session keeps its server error; only an isolated local Demo may edit offline.
            guard !liveSession, localEndpoint, demoAvailable else {
                throw error
            }
            var edited = user!
            if let value = body["username"] {
                edited.name = value
                edited.username = value
            }
            if let value = body["email"] {
                edited.email = value
            }
            if let value = body["phone"] {
                edited.phone = value
            }
            if let value = body["mood"] {
                edited.mood = value
            }
            if let value = body["avatar"] {
                edited.avatar_url = value
            }
            user = edited
            demoProfiles[identity] = edited
        }
    }

    func logout() {
        epoch += 1
        readRevision += 1
        profileRevision += 1
        profileBusy = false
        activeWrite = nil
        busy = false
        token = ""
        user = nil
        orders = []
        demoOrders = []
        liveSession = false
        pending = nil
    }

    func saveConnection(_ address: String,
                        milliseconds: Double) throws {
        guard let url = URL(string: address), ["http", "https"].contains(url.scheme), url.host != nil,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              (500...10000).contains(milliseconds) else {
            throw APIError(status: 422, message: t("invalidLink"))
        }
        if api != address {
            logout()
            online = false
            products = seed
            banners = nil
            explicitDemoMode = nil
            demoAvailable = false
            demoCredentials = [:]
            localDemoAuth = LocalDemoAuth()
            demoProfiles = [:]
        }
        api = address
        if !localEndpoint {
            products = []
        }
        timeout = milliseconds
        UserDefaults.standard.set(api, forKey: "api")
        UserDefaults.standard.set(timeout, forKey: "timeout")
    }

    func write(_ path: String,
               body: [String: Any]) async throws {
        guard user != nil else {
            throw APIError(status: 401, message: t("signInFirst"))
        }
        if let pending, pending.path != path || !NSDictionary(dictionary: pending.body).isEqual(to: body) {
            throw APIError(status: 409, message: t("pendingWrite"))
        }
        guard activeWrite == nil else {
            throw APIError(status: 409, message: t("pendingWrite"))
        }
        let operationEpoch = epoch
        let ticket = UUID()
        let key = pending?.key ?? "mac-shop-" + UUID().uuidString
        let frozenBody = pending?.body ?? body
        // Freeze one intent before suspension so every retry uses the same key.
        pending = (path, frozenBody, key)
        activeWrite = ticket
        busy = true
        readRevision += 1
        defer {
            if activeWrite == ticket {
                activeWrite = nil
                busy = false
            }
        }
        do {
            let response = try await request(path, body: frozenBody, key: key)
            let order = try NativeAPI.decode(ShopOrder.self, from: response["order"])
            let matchesIntent: Bool
            if path == "/shop-orders" {
                matchesIntent = order.product_snapshot.id == frozenBody["product_id"] as? String && order.product_snapshot.version == frozenBody["product_version"] as? Int
            } else {
                matchesIntent = path == "/shop-orders/" + order.id + "/actions" && order.version > (frozenBody["expected_version"] as? Int ?? 0)
            }
            guard !order.id.isEmpty, order.owner_id == user?.id, order.version > 0, matchesIntent else {
                throw APIError(status: 0, message: t("unexpected_response"))
            }
            guard operationEpoch == epoch, activeWrite == ticket else {
                throw APIError(status: 499, message: t("reselect"))
            }
            // A list started during the write must not replace its confirmed result.
            readRevision += 1
            orders.removeAll { $0.id == order.id }
            orders.insert(order, at: 0)
            pending = nil
            online = true
        } catch {
            guard operationEpoch == epoch, activeWrite == ticket else {
                throw APIError(status: 499, message: t("reselect"))
            }
            if let failure = error as? APIError, !failure.mayBeOffline {
                pending = nil
                throw failure
            }
            if liveSession {
                throw APIError(status: 0, message: t("pendingWrite"))
            }
            do {
                try applyDemo(path, body: frozenBody)
                pending = nil
            } catch {
                pending = nil
                throw error
            }
        }
    }

    func retryPending() async throws {
        if let pending {
            try await write(pending.path, body: pending.body)
        }
    }

    func applyDemo(_ path: String,
                   body: [String: Any]) throws {
        if path == "/shop-orders" {
            guard let product = products.first(where: { $0.id == body["product_id"] as? String }), product.in_stock else {
                throw APIError(status: 422, message: t("outOfStock"))
            }
            demoOrders.insert(ShopOrder(id: "demo-" + UUID().uuidString,
                                        owner_id: user?.id,
                                        product_snapshot: product,
                                        amount_minor: product.price_minor,
                                        status: "pending_payment",
                                        fulfillment_status: "pending",
                                        version: 1,
                                        editable: true,
                                        requirements: body["requirements"] as? String,
                                        contact: body["contact"] as? String,
                                        delivery_requirements: body["delivery_requirements"] as? String), at: 0)
        } else {
            guard let index = demoOrders.firstIndex(where: { path.contains($0.id) }),
                  demoOrders[index].version == body["expected_version"] as? Int else {
                throw APIError(status: 409, message: t("version"))
            }
            let action = body["action"] as? String
            switch action {
            case "pay" where demoOrders[index].status == "pending_payment":
                demoOrders[index].status = "pending_completion"
            case "cancel" where demoOrders[index].status == "pending_payment":
                demoOrders[index].status = "cancelled"
                demoOrders[index].editable = false
            case "edit" where demoOrders[index].editable == true:
                demoOrders[index].requirements = body["requirements"] as? String
                demoOrders[index].contact = body["contact"] as? String
                demoOrders[index].delivery_requirements = body["delivery_requirements"] as? String
            case "accept" where demoOrders[index].fulfillment_status == "delivered":
                demoOrders[index].status = "pending_review"
            case "review" where demoOrders[index].status == "pending_review":
                demoOrders[index].status = "completed"
            default:
                throw APIError(status: 422, message: t("state"))
            }
            demoOrders[index].version += 1
        }
        orders = demoOrders
        online = false
    }
}
