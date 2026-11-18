//
//  StoreConcurrency.swift
//  ZhixuNativeTests
//
//  Created by Jobs on 2026年11月18日，星期三.
//

import Foundation

@MainActor enum StoreFixtureAPI {
    struct Call {
        let path: String
        let key: String?
        let continuation: CheckedContinuation<[String: Any], Error>
    }
    static var calls: [Call] = []
    static func request(base: String, token: String, timeout: Double, path: String, body: [String: Any]? = nil, key: String? = nil, method: String? = nil) async throws -> [String: Any] {
        return try await withCheckedThrowingContinuation { continuation in
            calls.append(Call(path: path, key: key, continuation: continuation))
        }
    }
    static func decode<T: Decodable>(_ type: T.Type, from value: Any?) throws -> T {
        return try JSONDecoder().decode(type, from: JSONSerialization.data(withJSONObject: value!))
    }
    static func wait(_ count: Int) async {
        for _ in 0..<10000 {
            if calls.count >= count { return }
            await Task.yield()
        }
        fatalError("Timed out waiting for request")
    }
    static func succeed(_ index: Int, _ value: [String: Any]) {
        calls[index].continuation.resume(returning: value)
    }
}

@main struct Harness {
    @MainActor static func main() async throws {
        let store = ShopStore()
        let products = try JSONSerialization.jsonObject(with: Data(contentsOf: Bundle.main.resourceURL!.appendingPathComponent("products.json"))) as! [[String: Any]]
        let product = products[0]
        func order(_ version: Int) -> [String: Any] {
            return ["id": "created-order", "owner_id": "buyer", "product_snapshot": product, "amount_minor": product["price_minor"]!, "status": "pending_payment", "fulfillment_status": "pending", "version": version, "editable": true]
        }
        let login = Task { try await store.login(["account": "customer", "password": "demo-customer"]) }
        await StoreFixtureAPI.wait(1)
        StoreFixtureAPI.succeed(0, ["token": "fixture", "user": ["id": "buyer", "name": "Fixture", "role": "customer"]])
        await StoreFixtureAPI.wait(2)
        StoreFixtureAPI.succeed(1, ["products": products])
        await StoreFixtureAPI.wait(3)
        StoreFixtureAPI.succeed(2, ["orders": []])
        try await login.value

        let staleRefresh = Task { await store.refresh() }
        await StoreFixtureAPI.wait(4)
        let payload: [String: Any] = ["product_id": product["id"]!, "product_version": product["version"]!, "requirements": "Fixture"]
        let write = Task { try await store.write("/shop-orders", body: payload) }
        await StoreFixtureAPI.wait(5)
        do {
            try await store.write("/shop-orders", body: payload)
            fatalError("Concurrent write was accepted")
        } catch let failure as APIError {
            precondition(failure.status == 409)
        }
        precondition(StoreFixtureAPI.calls.count == 5)
        StoreFixtureAPI.succeed(4, ["order": order(1)])
        try await write.value
        StoreFixtureAPI.succeed(3, ["products": products])
        await staleRefresh.value
        precondition(store.orders.first?.version == 1 && StoreFixtureAPI.calls.count == 5)

        let action: [String: Any] = ["action": "pay", "expected_version": 1]
        let pay = Task { try await store.write("/shop-orders/created-order/actions", body: action) }
        await StoreFixtureAPI.wait(6)
        let overlappingRefresh = Task { await store.refresh() }
        await StoreFixtureAPI.wait(7)
        StoreFixtureAPI.succeed(6, ["products": products])
        await StoreFixtureAPI.wait(8)
        StoreFixtureAPI.succeed(5, ["order": order(2)])
        try await pay.value
        StoreFixtureAPI.succeed(7, ["orders": [order(1)]])
        await overlappingRefresh.value
        precondition(store.orders.first?.version == 2)

        let secondAction: [String: Any] = ["action": "cancel", "expected_version": 2]
        let uncertain = Task { try await store.write("/shop-orders/created-order/actions", body: secondAction) }
        await StoreFixtureAPI.wait(9)
        StoreFixtureAPI.calls[8].continuation.resume(throwing: URLError(.timedOut))
        do {
            try await uncertain.value
            fatalError("Unknown write was accepted")
        } catch {}
        let retry = Task { try await store.retryPending() }
        await StoreFixtureAPI.wait(10)
        precondition(StoreFixtureAPI.calls[8].key == StoreFixtureAPI.calls[9].key)
        StoreFixtureAPI.succeed(9, ["order": order(3)])
        try await retry.value
        precondition(store.orders.first?.version == 3)

        var confirmedVersion = 3
        for failure in ["order", "version", "owner"] {
            let requestCount = StoreFixtureAPI.calls.count
            let body: [String: Any] = ["action": "pay", "expected_version": confirmedVersion]
            let invalid = Task { try await store.write("/shop-orders/created-order/actions", body: body) }
            await StoreFixtureAPI.wait(requestCount + 1)
            var response = order(confirmedVersion + 1)
            if failure == "order" {
                response["id"] = "created-order-other"
            } else if failure == "version" {
                response["version"] = confirmedVersion
            } else {
                response["owner_id"] = "another-buyer"
            }
            StoreFixtureAPI.succeed(requestCount, ["order": response])
            do {
                try await invalid.value
                fatalError("Invalid write response was accepted")
            } catch let rejected as APIError {
                precondition(rejected.status == 0)
            }
            precondition(store.orders.first?.version == confirmedVersion)
            let retryInvalid = Task { try await store.retryPending() }
            await StoreFixtureAPI.wait(requestCount + 2)
            precondition(StoreFixtureAPI.calls[requestCount].key == StoreFixtureAPI.calls[requestCount + 1].key)
            confirmedVersion += 1
            StoreFixtureAPI.succeed(requestCount + 1, ["order": order(confirmedVersion)])
            try await retryInvalid.value
        }

        let requestCount = StoreFixtureAPI.calls.count
        let lastVersion = confirmedVersion
        let staleWrite = Task { try await store.write("/shop-orders/created-order/actions", body: ["action": "pay", "expected_version": lastVersion]) }
        await StoreFixtureAPI.wait(requestCount + 1)
        store.logout()
        StoreFixtureAPI.succeed(requestCount, ["order": order(lastVersion + 1)])
        do {
            try await staleWrite.value
            fatalError("Stale write was accepted")
        } catch let failure as APIError {
            precondition(failure.status == 499)
        }
        precondition(store.user == nil && store.orders.isEmpty && !store.busy)

        for oldStatus in [200, 401] {
            let firstIndex = StoreFixtureAPI.calls.count
            let oldLogin = Task {
                try await store.login(["account": "old-fixture", "password": "old-secret"])
            }
            await StoreFixtureAPI.wait(firstIndex + 1)
            let currentLogin = Task {
                try await store.login(["account": "new-fixture", "password": "new-secret"])
            }
            await StoreFixtureAPI.wait(firstIndex + 2)
            StoreFixtureAPI.succeed(firstIndex + 1, ["token": "current-token", "user": ["id": "current-buyer", "name": "Current fixture", "role": "customer"]])
            await StoreFixtureAPI.wait(firstIndex + 3)
            StoreFixtureAPI.succeed(firstIndex + 2, ["products": products])
            await StoreFixtureAPI.wait(firstIndex + 4)
            StoreFixtureAPI.succeed(firstIndex + 3, ["orders": []])
            try await currentLogin.value
            if oldStatus == 200 {
                StoreFixtureAPI.succeed(firstIndex, ["token": "old-token", "user": ["id": "old-buyer", "name": "Old fixture", "role": "customer"]])
            } else {
                StoreFixtureAPI.calls[firstIndex].continuation.resume(throwing: APIError(status: 401, message: "Old fixture rejection"))
            }
            do {
                try await oldLogin.value
                fatalError("An old authentication attempt was accepted")
            } catch let stale as APIError {
                precondition(stale.status == 499)
            }
            precondition(store.user?.id == "current-buyer")
            precondition(StoreFixtureAPI.calls.count == firstIndex + 4)
        }

        let cancelledIndex = StoreFixtureAPI.calls.count
        let cancelledLogin = Task {
            try await store.login(["account": "cancelled-fixture", "password": "fixture-secret"])
        }
        await StoreFixtureAPI.wait(cancelledIndex + 1)
        store.logout()
        StoreFixtureAPI.succeed(cancelledIndex, ["token": "cancelled-token", "user": ["id": "cancelled-buyer", "name": "Cancelled fixture", "role": "customer"]])
        do {
            try await cancelledLogin.value
            fatalError("A cancelled authentication attempt was accepted")
        } catch let stale as APIError {
            precondition(stale.status == 499)
        }
        precondition(store.user == nil && store.orders.isEmpty)
        print("PASS 11 Swift scenarios: 8 write/read guards, old login success/401 exclusion, cancelled authentication late-response isolation")
    }
}
