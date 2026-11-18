//
//  StoreSmoke.swift
//  ZhixuNativeTests
//
//  Created by Jobs on 2026年11月18日，星期三.
//

import Foundation

@main struct StoreSmoke {

    @MainActor static func main() async throws {
        let base = CommandLine.arguments[1]
        let preferences = UserDefaults.standard
        let priorAPI = preferences.object(forKey: "api")
        let priorTimeout = preferences.object(forKey: "timeout")
        defer {
            for (key, value) in [("api", priorAPI), ("timeout", priorTimeout)] {
                if let value {
                    preferences.set(value, forKey: key)
                } else {
                    preferences.removeObject(forKey: key)
                }
            }
        }
        let store = ShopStore()
        store.api = base
        store.timeout = 1000
        await store.refresh()
        precondition(store.online && !store.products.isEmpty)
        try await store.login(["account": "customer", "password": "demo-customer"])
        let product = store.products.first!
        try await store.write("/shop-orders", body: ["product_id": product.id, "product_version": product.version, "requirements": "Native integration fixture", "contact": "fixture", "delivery_requirements": "fixture"])
        var order = store.orders.first!
        precondition(!order.id.hasPrefix("demo-"))
        try await store.write("/shop-orders/" + order.id + "/actions", body: ["action": "pay", "expected_version": order.version, "channel": "alipay"])
        order = store.orders.first!
        precondition(order.status == "pending_completion")
        let admin = try await NativeAPI.request(base: base, token: "", timeout: 1000, path: "/auth/login", body: ["account": "admin", "password": "1234"])
        let adminToken = admin["token"] as! String
        _ = try await NativeAPI.request(base: base, token: adminToken, timeout: 1000, path: "/shop-orders/" + order.id + "/actions", body: ["action": "deliver", "expected_version": order.version, "text": "Fixture delivery"], key: UUID().uuidString)
        await store.refresh()
        order = store.orders.first(where: { $0.id == order.id })!
        try await store.write("/shop-orders/" + order.id + "/actions", body: ["action": "accept", "expected_version": order.version])
        order = store.orders.first!
        precondition(order.status == "pending_review")
        try await store.write("/shop-orders/" + order.id + "/actions", body: ["action": "review", "expected_version": order.version, "rating": 5, "text": "Fixture review"])
        precondition(store.orders.first!.status == "completed")
        let customerUID = store.user!.id
        let freeEmail = "  任意邮箱内容 / not-an-address\n"
        let freePhone = "  电话：+86 123-ABC / 未验证\n"
        let freeMood = "今天也在向前走。\n保留这一行。"
        let gifFrame = Data(base64Encoded: "R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7")!
        var animatedGIF = Data(gifFrame.dropLast())
        animatedGIF.append(gifFrame.subdata(in: 19..<(gifFrame.count - 1)))
        animatedGIF.append(0x3b)
        let gif = "data:image/gif;base64," + animatedGIF.base64EncodedString()
        try await store.saveProfile(["email": freeEmail, "phone": freePhone, "mood": freeMood, "avatar": gif])
        precondition(store.user?.id == customerUID)
        precondition(store.user?.email == freeEmail && store.user?.phone == freePhone && store.user?.mood == freeMood)
        precondition(store.user?.avatar_url == gif)
        try await store.saveProfile(["mood": "  只修改心情\n"])
        precondition(store.user?.id == customerUID && store.user?.email == freeEmail && store.user?.phone == freePhone)
        precondition(store.user?.mood == "  只修改心情\n" && store.user?.avatar_url == gif)
        do {
            try await store.saveProfile(["id": "client-supplied-uid"])
            fatalError("A client-supplied UID must be rejected")
        } catch let failure as APIError {
            precondition(failure.status == 422 && store.user?.id == customerUID)
        }
        try await store.saveProfile(["email": "", "phone": ""])
        precondition((store.user?.email ?? "") == "" && (store.user?.phone ?? "") == "" && store.user?.id == customerUID)
        try await store.saveProfile(["email": freeEmail, "phone": freePhone])
        store.logout()
        try await store.login(["account": "customer", "password": "demo-customer"])
        precondition(store.user?.id == customerUID && store.user?.email == freeEmail && store.user?.phone == freePhone)
        precondition(store.user?.mood == "  只修改心情\n" && store.user?.avatar_url == gif)
        await store.refreshDemoMode()
        precondition(store.demoAvailable && store.demoCredentials["customer"] == "demo-customer")
        let identity = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12)
        let email = "native-" + identity + "@example.test"
        let username = "native_" + identity
        let code = try await store.authEmailCode(email: email, purpose: "register")
        try await store.completeAccount(["email": email, "code": code["demo_code"] as! String, "username": username, "password": "FixturePassword1!", "confirm_password": "FixturePassword1!"], reset: false)
        try await store.login(["account": email, "password": "FixturePassword1!"])
        let resetCode = try await store.authEmailCode(email: email, purpose: "reset_password")
        try await store.completeAccount(["email": email, "code": resetCode["demo_code"] as! String, "password": "FixturePassword2!", "confirm_password": "FixturePassword2!"], reset: true)
        precondition(store.user == nil)
        try await store.login(["account": email, "password": "FixturePassword2!"])
        do {
            try await store.login(["account": "customer", "password": "incorrect-password"])
            fatalError("401 must not become a demo login")
        } catch {
            precondition(store.user == nil)
        }
        try store.saveConnection("http://127.0.0.1:1/api/v1", milliseconds: 1000)
        try await store.login(["account": "customer", "password": "demo-customer"])
        try await store.write("/shop-orders", body: ["product_id": store.products.first!.id, "product_version": 1])
        precondition(store.orders.first!.id.hasPrefix("demo-") && !store.online)
        let offlineUID = store.user!.id
        try await store.saveProfile(["email": freeEmail, "phone": freePhone, "mood": freeMood, "avatar": gif])
        precondition(store.user?.id == offlineUID && store.user?.avatar_url == gif && store.user?.mood == freeMood)
        store.logout()
        try await store.login(["account": "customer2", "password": "demo-customer"])
        precondition(store.user?.id != offlineUID && store.user?.avatar_url != gif && store.user?.mood != freeMood)
        try await store.saveProfile(["mood": "第二个用户自己的心情"])
        store.logout()
        try await store.login(["account": "customer", "password": "demo-customer"])
        precondition(store.user?.id == offlineUID && store.user?.avatar_url == gif && store.user?.mood == freeMood)
        precondition(store.user?.email == freeEmail && store.user?.phone == freePhone)
        let offlineCode = try await store.authEmailCode(email: "local-fixture@example.test", purpose: "register")
        try await store.completeAccount(["email": "local-fixture@example.test", "code": offlineCode["demo_code"] as! String, "username": "local_fixture", "password": "LocalPassword1!", "confirm_password": "LocalPassword1!"], reset: false)
        try await store.login(["account": "local_fixture", "password": "LocalPassword1!"])
        let offlineReset = try await store.authEmailCode(email: "local-fixture@example.test", purpose: "reset_password")
        try await store.completeAccount(["email": "local-fixture@example.test", "code": offlineReset["demo_code"] as! String, "password": "LocalPassword2!", "confirm_password": "LocalPassword2!"], reset: true)
        precondition(store.user == nil)
        try await store.login(["account": "local-fixture@example.test", "password": "LocalPassword2!"])
        precondition(store.user?.username == "local_fixture")
        store.api = "http://192.0.2.1:1/api/v1"
        await store.refreshDemoMode()
        precondition(!store.demoAvailable && store.demoCredentials.isEmpty)
        do {
            try await store.login(["account": "customer", "password": "demo-customer"])
            fatalError("Remote endpoint must not use a demo login")
        } catch {
            precondition(store.user == nil)
        }
        print("PASS Swift native store: live buy/pay/deliver/accept/review; raw profile email/phone/mood, immutable UID, GIF bytes, partial update and relogin; isolated offline profiles; live/offline register/reset/login; 401 rejection and remote demo gate")
    }
}
