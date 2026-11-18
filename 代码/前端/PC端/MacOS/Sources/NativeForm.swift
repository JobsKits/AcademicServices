//
//  NativeForm.swift
//  ZhixuMac
//
//  Created by Jobs on 2026年11月18日，星期三.
//

import AppKit
import ImageIO
import UniformTypeIdentifiers
import SwiftUI

struct NativeForm: View {

    @Environment(\.dismiss) private var dismiss
    @State var request: FormRequest
    @ObservedObject var store: ShopStore
    @State private var values: [String: String] = [:]
    @State private var error = ""
    @State private var busy = false
    @State private var visiblePasswords: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(store.t(request.title)).font(.title2.bold())
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(request.fields.indices, id: \.self) { index in
                        let field = request.fields[index]
                        let binding = Binding(get: { values[field.0] ?? "" }, set: { values[field.0] = $0 })
                        Text(store.t(field.0)).foregroundStyle(.secondary)
                        if field.1 == "password" {
                            HStack {
                                Group {
                                    if visiblePasswords.contains(field.0) {
                                        TextField(store.t(field.0), text: binding)
                                    } else {
                                        SecureField(store.t(field.0), text: binding)
                                    }
                                }
                                Button {
                                    if visiblePasswords.contains(field.0) {
                                        visiblePasswords.remove(field.0)
                                    } else {
                                        visiblePasswords.insert(field.0)
                                    }
                                } label: {
                                    Image(systemName: visiblePasswords.contains(field.0) ? "eye.slash" : "eye")
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(store.t(visiblePasswords.contains(field.0) ? "hidePassword" : "showPassword"))
                            }
                        } else if field.1 == "multiline" {
                            TextEditor(text: binding).frame(height: 85).border(.secondary.opacity(0.3))
                        } else if field.1 == "avatar" {
                            Button(store.t("uploadAvatar")) {
                                do {
                                    if let image = try AvatarPicker.select() {
                                        values[field.0] = image
                                    }
                                } catch {
                                    self.error = store.t("invalidDesktopAvatar")
                                }
                            }
                        } else {
                            TextField(store.t(field.0), text: binding)
                        }
                    }
                }
            }
            Text(error).foregroundStyle(.red).textSelection(.enabled)
            HStack {
                Spacer()
                Button(store.t("cancel")) {
                    dismiss()
                }
                .disabled(busy)
                Button(store.t(actionKey)) {
                    run {
                        try await request.submit(values)
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(busy)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(25)
        .frame(width: 510, height: request.fields.count > 3 ? 640 : 500)
        .textFieldStyle(.roundedBorder)
        .interactiveDismissDisabled(busy)
        .onAppear {
            values = request.values
        }
    }

    var actionKey: String {
        switch request.title {
        case "buy", "review", "accept", "cancel":
            return request.title
        case "mockHint":
            return "confirmPay"
        default:
            return "save"
        }
    }

    func run(_ operation: @escaping () async throws -> Void) {
        busy = true
        error = ""
        Task {
            defer {
                busy = false
            }
            do {
                try await operation()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

enum AvatarPicker {

    static func select() throws -> String? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .gif, .webP]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else {
            return nil
        }
        let data = try Data(contentsOf: url)
        guard data.count <= 20 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source),
              let mime = UTType(type as String)?.preferredMIMEType,
              ["image/png", "image/jpeg", "image/gif", "image/webp"].contains(mime) else {
            throw APIError(status: 422, message: "Invalid avatar")
        }
        return "data:" + mime + ";base64," + data.base64EncodedString()
    }
}

struct SettingsView: View {

    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: ShopStore
    @State private var api = ""
    @State private var timeout = ""
    @State private var language = "zh"
    @State private var theme = "system"
    @State private var error = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "gearshape")
                    .font(.system(size: 25, weight: .medium))
                    .foregroundStyle(.tint)
                Text(store.t("settings")).font(.title2.bold())
                Spacer()
            }
            .padding(26)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(store.t("appearance")).font(.headline)
                        field("language") {
                            Picker(store.t("language"), selection: $language) {
                                ForEach(store.languages.indices, id: \.self) { index in
                                    Text(store.languageNames[index]).tag(store.languages[index])
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        field("theme") {
                            Picker(store.t("theme"), selection: $theme) {
                                ForEach(["system", "light", "dark"], id: \.self) { item in
                                    Text(store.t(item)).tag(item)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    if store.demoAvailable {
                        Divider()
                        VStack(alignment: .leading, spacing: 18) {
                            HStack {
                                Text(store.t("connection")).font(.headline)
                                Text(store.t("demoVersion"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            field("api") {
                                TextField(store.t("api"), text: $api)
                            }
                            field("timeout") {
                                TextField(store.t("timeout"), text: $timeout)
                            }
                        }
                    }
                    if !error.isEmpty {
                        Text(error).foregroundStyle(.red).textSelection(.enabled)
                    }
                }
                .padding(26)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack(spacing: 12) {
                Spacer()
                Button(store.t("cancel")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button(store.t("save")) {
                    do {
                        if store.demoAvailable {
                            try store.saveConnection(api, milliseconds: Double(timeout) ?? 0)
                        }
                        store.language = language
                        store.theme = theme
                        Task {
                            await store.refreshDemoMode()
                            await store.refresh()
                        }
                        dismiss()
                    } catch {
                        self.error = error.localizedDescription
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 18)
        }
        .frame(width: 550, height: store.demoAvailable ? 580 : 380)
        .textFieldStyle(.roundedBorder)
        .preferredColorScheme(store.theme == "system" ? nil : (store.theme == "dark" ? .dark : .light))
        .onAppear {
            api = store.api
            timeout = String(Int(store.timeout))
            language = store.language
            theme = store.theme
        }
    }

    func field<Content: View>(_ key: String,
                              @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(store.t(key)).font(.subheadline).foregroundStyle(.secondary)
            content()
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
