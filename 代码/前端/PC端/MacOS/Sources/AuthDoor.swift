//
//  AuthDoor.swift
//  ZhixuMac
//
//  Created by Jobs on 2026年11月18日，星期三.
//

import SwiftUI

enum AuthDoorMode: String, CaseIterable, Identifiable {

    case login
    case register
    case forgotPassword

    var id: String {
        return rawValue
    }

    var action: String {
        switch self {
        case .login:
            return "login"
        case .register:
            return "createAccount"
        case .forgotPassword:
            return "resetPassword"
        }
    }

    var introduction: String {
        switch self {
        case .login:
            return "authWelcome"
        case .register:
            return "authRegisterIntro"
        case .forgotPassword:
            return "authResetIntro"
        }
    }

    var fields: [String] {
        switch self {
        case .login:
            return ["account", "password"]
        case .register:
            return ["email", "code", "username", "password", "confirmPassword"]
        case .forgotPassword:
            return ["email", "code", "password", "confirmPassword"]
        }
    }
}

struct AuthDoor: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var store: ShopStore
    var onAuthenticated: () -> Void
    @State private var mode: AuthDoorMode = .login
    @State private var drafts: [AuthDoorMode: [String: String]] = [
        .login: [:],
        .register: [:],
        .forgotPassword: [:]
    ]
    @State private var offsets: [AuthDoorMode: CGFloat] = [.login: 0, .register: 490, .forgotPassword: 490]
    @State private var error = ""
    @State private var notice = ""
    @State private var busy = false
    @State private var switching = false
    @State private var appeared = false
    @State private var completedAuthentication = false
    @State private var loginEdited = false
    @State private var demoIdentity = "customer"
    @FocusState private var focusedField: String?

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 15) {
                HStack(spacing: 9) {
                    brandImage.frame(width: 31, height: 31)
                    Text("知序").font(.title2.bold())
                }
                .padding(.bottom, 18)
                ForEach(AuthDoorMode.allCases) { item in
                    Button {
                        changeDoor(item)
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(store.t(item.rawValue))
                                .font(.system(size: 14, weight: .semibold))
                                .fixedSize(horizontal: false, vertical: true)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(item == mode ? activeForeground.opacity(0.8) : .secondary.opacity(0.5))
                                .frame(width: item == mode ? 31 : 17, height: 3)
                        }
                        .frame(maxWidth: .infinity, minHeight: 55, alignment: .leading)
                        .padding(12)
                        .foregroundStyle(item == mode ? activeForeground : .primary)
                        .background(item == mode ? activeBackground : cardBackground, in: RoundedRectangle(cornerRadius: 13))
                        .overlay(RoundedRectangle(cornerRadius: 13).stroke(item == mode ? .clear : .secondary.opacity(0.2)))
                        .contentShape(RoundedRectangle(cornerRadius: 13))
                    }
                    .buttonStyle(.plain)
                    .disabled(busy || switching)
                    .accessibilityValue(item == mode ? store.t(item.rawValue) : "")
                }
                Spacer(minLength: 0)
                Button(store.t("cancel")) {
                    dismiss()
                }
                .buttonStyle(.plain)
                .padding(.vertical, 12)
                .disabled(busy)
                .keyboardShortcut(.cancelAction)
            }
            .frame(width: 142, height: 530)
            ZStack(alignment: .top) {
                ForEach(AuthDoorMode.allCases) { item in
                    AuthDoorCard(mode: item,
                                 values: draftBinding(item),
                                 store: store,
                                 busy: busy,
                                 error: item == mode ? error : "",
                                 notice: item == mode ? notice : "",
                                 demoIdentity: Binding(get: { demoIdentity }, set: selectDemoIdentity),
                                 focusedField: $focusedField,
                                 submit: submit,
                                 sendCode: sendCode,
                                 changeDoor: changeDoor)
                        .offset(x: offsets[item] ?? 490)
                        .allowsHitTesting(item == mode && !switching)
                        .disabled(item != mode || switching)
                        .accessibilityHidden(item != mode || switching)
                }
            }
            .frame(width: 450, height: 560)
            .clipped()
        }
        .padding(25)
        .frame(width: 662, height: 610)
        .background(colorScheme == .dark ? Color(red: 0.09, green: 0.14, blue: 0.11) : Color(red: 0.91, green: 0.95, blue: 0.91))
        .tint(activeBackground)
        .scaleEffect(appeared ? 1 : (reduceMotion ? 1 : 0.01))
        .interactiveDismissDisabled(busy)
        .onAppear {
            if reduceMotion {
                appeared = true
            } else {
                withAnimation(.interpolatingSpring(stiffness: 180, damping: 17)) {
                    appeared = true
                }
            }
            focusedField = AuthDoorMode.login.rawValue + ":account"
            configureDemoCredentials()
        }
        .task {
            await store.refreshDemoMode()
            configureDemoCredentials()
        }
        .onChange(of: store.demoAvailable) { _ in
            configureDemoCredentials()
        }
        .onDisappear {
            if busy && !completedAuthentication {
                store.logout()
            }
            drafts = [:]
        }
    }

    var brandImage: some View {
        Image(nsImage: NSImage(contentsOfFile: Bundle.main.resourceURL!.appendingPathComponent("icon.png").path) ?? NSImage())
            .resizable()
            .scaledToFit()
    }

    var activeBackground: Color {
        return colorScheme == .dark ? Color(red: 0.65, green: 0.86, blue: 0.70) : Color(red: 0.22, green: 0.42, blue: 0.29)
    }

    var activeForeground: Color {
        return colorScheme == .dark ? Color(red: 0.10, green: 0.20, blue: 0.13) : .white
    }

    var cardBackground: Color {
        return colorScheme == .dark ? Color(red: 0.15, green: 0.21, blue: 0.17) : .white
    }

    func draftBinding(_ item: AuthDoorMode) -> Binding<[String: String]> {
        return Binding(get: {
            drafts[item] ?? [:]
        }, set: { values in
            drafts[item] = values
            if item == .login {
                loginEdited = true
            }
        })
    }

    func configureDemoCredentials() {
        guard store.demoAvailable, !loginEdited, !store.demoCredentials.isEmpty else {
            return
        }
        let identity = store.demoCredentials[demoIdentity] != nil ? demoIdentity : store.demoCredentials.keys.sorted().first!
        selectDemoIdentity(identity)
    }

    func selectDemoIdentity(_ identity: String) {
        demoIdentity = identity
        drafts[.login] = ["account": identity, "password": store.demoCredentials[identity] ?? ""]
    }

    func changeDoor(_ target: AuthDoorMode) {
        guard target != mode, !busy, !switching else {
            return
        }
        focusedField = nil
        error = ""
        let previous = mode
        if reduceMotion {
            offsets[previous] = -490
            offsets[target] = 0
            mode = target
            focusedField = target.rawValue + ":" + (target == .login ? "account" : "email")
            return
        }
        switching = true
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            offsets[target] = 490
            mode = target
        }
        withAnimation(.spring(response: 0.7, dampingFraction: 0.74).delay(0.08)) {
            offsets[previous] = -490
            offsets[target] = 0
        }
        Task {
            try? await Task.sleep(nanoseconds: 850_000_000)
            switching = false
            focusedField = target.rawValue + ":" + (target == .login ? "account" : "email")
        }
    }

    func submit() {
        guard !busy, !switching else {
            return
        }
        let current = mode
        let values = drafts[current] ?? [:]
        guard current.fields.allSatisfy({ !(values[$0] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            error = store.t("required")
            return
        }
        focusedField = nil
        error = ""
        notice = ""
        busy = true
        Task {
            defer {
                busy = false
            }
            do {
                if current == .login {
                    try await store.login(values)
                    completedAuthentication = true
                    onAuthenticated()
                    dismiss()
                } else {
                    guard values["password"] == values["confirmPassword"] else {
                        throw APIError(status: 422, message: store.t("required"))
                    }
                    var body = values
                    body["confirm_password"] = body.removeValue(forKey: "confirmPassword")
                    try await store.completeAccount(body, reset: current == .forgotPassword)
                    drafts[current]?["password"] = ""
                    drafts[current]?["confirmPassword"] = ""
                    drafts[.login] = ["account": values["email"] ?? "", "password": ""]
                    loginEdited = true
                    busy = false
                    changeDoor(.login)
                    notice = store.t(current == .register ? "accountCreated" : "passwordReset")
                }
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    func sendCode() {
        guard !busy, mode != .login else {
            return
        }
        let current = mode
        let email = drafts[current]?["email"] ?? ""
        guard !email.trimmingCharacters(in: .whitespaces).isEmpty else {
            error = store.t("required")
            return
        }
        busy = true
        error = ""
        notice = ""
        Task {
            defer {
                busy = false
            }
            do {
                let response = try await store.authEmailCode(email: email, purpose: current == .register ? "register" : "reset_password")
                notice = (response["demo_code"] as? String).map { store.t("demoCode") + ": " + $0 } ?? store.t("codeSent")
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

struct AuthDoorCard: View {

    let mode: AuthDoorMode
    @Binding var values: [String: String]
    @ObservedObject var store: ShopStore
    let busy: Bool
    let error: String
    let notice: String
    @Binding var demoIdentity: String
    var focusedField: FocusState<String?>.Binding
    var submit: () -> Void
    var sendCode: () -> Void
    var changeDoor: (AuthDoorMode) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var visiblePasswords: Set<String> = []
    @State private var visibilityInitialized = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(store.t(mode.action)).font(.system(size: 25, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
            Text(store.t(mode.introduction)).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if mode == .login && store.demoAvailable {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(store.t("demoRole")).font(.caption).foregroundStyle(.secondary)
                            Picker(store.t("buyerRole"), selection: $demoIdentity) {
                                ForEach(store.demoCredentials.keys.sorted(), id: \.self) { identity in
                                    Text(identity == "customer" ? store.t("demoBuyer") : (identity == "customer2" ? store.t("demoBuyer2") : store.t("buyerRole") + " · " + identity)).tag(identity)
                                }
                            }
                            .labelsHidden()
                        }
                        .padding(.bottom, 4)
                    }
                    ForEach(mode.fields, id: \.self) { key in
                        field(key)
                    }
                    if mode == .login && store.demoAvailable {
                        Text(store.t("demoPrefilled")).font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !notice.isEmpty {
                        Text(notice).font(.callout).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !error.isEmpty {
                        Text(error).font(.callout).foregroundStyle(colorScheme == .dark ? Color(red: 1, green: 0.68, blue: 0.66) : Color(red: 0.65, green: 0.12, blue: 0.12))
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }
                .padding(.vertical, 3)
            }
            .frame(maxHeight: .infinity)
            Button(action: submit) {
                HStack {
                    Spacer()
                    if busy {
                        ProgressView().controlSize(.small)
                    }
                    Text(store.t(mode.action)).fontWeight(.semibold)
                    Spacer()
                }
                .padding(.vertical, 11)
            }
            .buttonStyle(.borderedProminent)
            .disabled(busy)
            .keyboardShortcut(.defaultAction)
            HStack(alignment: .top, spacing: 18) {
                if mode == .login {
                    textLink(.register)
                    Spacer(minLength: 0)
                    textLink(.forgotPassword)
                } else {
                    Button(store.t("backToSignIn")) {
                        changeDoor(.login)
                    }
                    .buttonStyle(.plain)
                }
            }
            .font(.callout)
            .padding(.top, 2)
            .disabled(busy)
        }
        .padding(23)
        .frame(width: 444, height: 550)
        .background(colorScheme == .dark ? Color(red: 0.15, green: 0.21, blue: 0.17) : .white, in: RoundedRectangle(cornerRadius: 19))
        .overlay(RoundedRectangle(cornerRadius: 19).stroke(.secondary.opacity(0.2)))
        .disabled(busy)
        .onAppear {
            configurePasswordVisibility()
        }
        .onChange(of: store.demoAvailable) { _ in
            configurePasswordVisibility()
        }
    }

    @ViewBuilder func field(_ key: String) -> some View {
        let binding = Binding(get: {
            values[key] ?? ""
        }, set: { value in
            values[key] = value
        })
        VStack(alignment: .leading, spacing: 5) {
            Text(store.t(key)).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                if key == "password" || key == "confirmPassword" {
                    Group {
                        if visiblePasswords.contains(key) {
                            TextField(store.t(key), text: binding)
                        } else {
                            SecureField(store.t(key), text: binding)
                        }
                    }
                    .focused(focusedField, equals: mode.rawValue + ":" + key)
                    .onSubmit(submit)
                    Button {
                        if visiblePasswords.contains(key) {
                            visiblePasswords.remove(key)
                        } else {
                            visiblePasswords.insert(key)
                        }
                        focusedField.wrappedValue = mode.rawValue + ":" + key
                    } label: {
                        Image(systemName: visiblePasswords.contains(key) ? "eye.slash" : "eye")
                            .frame(width: 27, height: 25)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(store.t(visiblePasswords.contains(key) ? "hidePassword" : "showPassword"))
                    .help(store.t(visiblePasswords.contains(key) ? "hidePassword" : "showPassword"))
                } else {
                    TextField(store.t(key), text: binding)
                        .focused(focusedField, equals: mode.rawValue + ":" + key)
                        .onSubmit(submit)
                    if key == "email" {
                        Button(store.t("sendCode"), action: sendCode)
                            .buttonStyle(.borderless)
                            .font(.caption)
                            .fixedSize()
                    }
                }
            }
            .textFieldStyle(.plain)
            .padding(.horizontal, 11)
            .padding(.vertical, 10)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.35)))
        }
    }

    func textLink(_ destination: AuthDoorMode) -> some View {
        Button(store.t(destination.rawValue)) {
            changeDoor(destination)
        }
        .buttonStyle(.plain)
    }

    func configurePasswordVisibility() {
        guard !visibilityInitialized, store.demoAvailable else {
            return
        }
        visiblePasswords = ["password", "confirmPassword"]
        visibilityInitialized = true
    }
}

struct AuthGate: View {

    @ObservedObject var store: ShopStore
    var login: () -> Void

    var body: some View {
        VStack(spacing: 17) {
            Text(store.t("signInFirst")).font(.title2.bold())
            Text(store.t("authRequiredHint")).foregroundStyle(.secondary)
            Button(store.t("login"), action: login)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .padding(40)
        .frame(maxWidth: .infinity)
        .background(.background, in: RoundedRectangle(cornerRadius: 15))
    }
}
