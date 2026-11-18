//
//  ProfileView.swift
//  ZhixuMac
//
//  Created by Jobs on 2026年11月18日，星期三.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ProfileView: View {

    @ObservedObject var store: ShopStore
    var onOrders: () -> Void
    @State private var username = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var moodDraft = ""
    @State private var avatarPicker = false
    @State private var editingMood = false
    @State private var feedback = ""
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack(alignment: .top, spacing: 32) {
                identity
                    .frame(width: 225, alignment: .leading)
                VStack(alignment: .leading, spacing: 22) {
                    Text(store.t("personalDetails"))
                        .font(.title2.bold())
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 7) {
                            Text("UID").font(.callout.weight(.medium)).foregroundStyle(.secondary)
                            HStack(spacing: 8) {
                                Text(store.user?.id ?? "")
                                    .font(.body.monospaced())
                                    .textSelection(.enabled)
                                Image(systemName: "lock")
                                    .foregroundStyle(.secondary)
                            }
                            Text(store.t("uidReadOnly"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        field("username", value: $username)
                        field("email", value: $email)
                        field("phone", value: $phone)
                    }
                    .textFieldStyle(.roundedBorder)
                    Text(store.t("contactNoVerification"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    HStack {
                        Button(store.t("saveProfile")) {
                            save(["username": username, "email": email, "phone": phone])
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(store.profileBusy)
                        if store.profileBusy {
                            ProgressView().controlSize(.small)
                        }
                    }
                    if !feedback.isEmpty {
                        Text(feedback)
                            .font(.callout)
                            .foregroundStyle(failed ? Color.red : Color.secondary)
                            .textSelection(.enabled)
                    }
                }
                .padding(.leading, 32)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .leading) {
                    Rectangle().fill(.separator).frame(width: 1)
                }
            }
            Divider()
            Button(action: onOrders) {
                HStack(spacing: 14) {
                    Image(systemName: "shippingbox")
                        .font(.title2)
                        .foregroundStyle(.tint)
                    Text(store.t("myOrders"))
                        .font(.headline)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(28)
        .frame(maxWidth: 950, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .sheet(isPresented: $avatarPicker) {
            ProfileAvatarPicker(store: store)
        }
        .onAppear(perform: loadDraft)
        .onChange(of: store.user?.id) { _ in
            loadDraft()
        }
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button {
                avatarPicker = true
            } label: {
                ZStack(alignment: .bottomTrailing) {
                    ProfileAvatar(source: store.user?.avatar_url ?? "", api: store.api)
                        .frame(width: 104, height: 104)
                        .clipShape(Circle())
                    Image(systemName: "camera.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(Color.accentColor, in: Circle())
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(store.t("chooseAvatar"))
            .help(store.t("chooseAvatar"))
            Button {
                moodDraft = store.user?.mood ?? ""
                editingMood = true
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Image(systemName: "square.and.pencil")
                        .foregroundStyle(.tint)
                    Text(displayedMood)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(store.t("editMood") + ", " + displayedMood)
            .popover(isPresented: $editingMood, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 16) {
                    Text(store.t("editMood")).font(.headline)
                    TextEditor(text: $moodDraft)
                        .frame(width: 300, height: 95)
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(.separator))
                    if failed && !feedback.isEmpty {
                        Text(feedback)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack {
                        Spacer()
                        Button(store.t("cancel")) {
                            editingMood = false
                        }
                        Button(store.t("save")) {
                            save(["mood": moodDraft]) {
                                editingMood = false
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(store.profileBusy)
                    }
                }
                .padding(20)
            }
            Text(store.user?.name ?? "")
                .font(.title.bold())
                .textSelection(.enabled)
            if store.demoAvailable {
                Text(store.t("demoVersion"))
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .foregroundStyle(.tint)
                    .background(.tint.opacity(0.12), in: Capsule())
            }
        }
    }

    private var displayedMood: String {
        if let mood = store.user?.mood, !mood.isEmpty {
            return mood
        }
        return store.t("defaultMood")
    }

    private func field(_ key: String,
                       value: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(store.t(key)).font(.callout.weight(.medium)).foregroundStyle(.secondary)
            TextField(store.t(key), text: value)
                .labelsHidden()
                .accessibilityLabel(store.t(key))
        }
    }

    private func loadDraft() {
        username = store.user?.username ?? store.user?.name ?? ""
        email = store.user?.email ?? ""
        phone = store.user?.phone ?? ""
    }

    private func save(_ values: [String: String],
                      completion: @escaping () -> Void = {}) {
        feedback = ""
        Task {
            do {
                try await store.saveProfile(values)
                failed = false
                feedback = store.t("profileSaved")
                completion()
            } catch {
                failed = true
                feedback = error.localizedDescription
            }
        }
    }
}

private struct ProfileAvatarPicker: View {

    @ObservedObject var store: ShopStore
    @Environment(\.dismiss) private var dismiss
    @State private var selection = ""
    @State private var error = ""

    private var presets: [URL] {
        let directory = Bundle.main.resourceURL!.appendingPathComponent("Avatars")
        return ((try? FileManager.default.contentsOfDirectory(at: directory,
                                                            includingPropertiesForKeys: nil)) ?? [])
            .filter { ["png", "jpg", "jpeg", "gif", "webp"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(store.t("chooseAvatar")).font(.title2.bold())
            HStack(spacing: 20) {
                ProfileAvatar(source: selection, api: store.api)
                    .frame(width: 86, height: 86)
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 8) {
                    Button(store.t("chooseLocalImage")) {
                        do {
                            if let result = try AvatarPicker.select() {
                                selection = result
                                error = ""
                            }
                        } catch {
                            self.error = store.t("invalidDesktopAvatar")
                        }
                    }
                    .disabled(store.profileBusy)
                    Text(store.t("avatarFormats"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Divider()
            Text(store.t("presetAvatars")).font(.headline)
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 4), spacing: 16) {
                    ForEach(Array(presets.enumerated()), id: \.element) { index, url in
                        let source = dataURI(url)
                        Button {
                            selection = source
                            error = ""
                        } label: {
                            ProfileAvatar(source: source, api: store.api)
                                .frame(width: 76, height: 76)
                                .clipShape(Circle())
                                .padding(5)
                                .background(selection == source ? Color.accentColor.opacity(0.15) : Color.clear, in: Circle())
                                .overlay(Circle().stroke(selection == source ? Color.accentColor : Color.clear, lineWidth: 3))
                                .overlay(alignment: .bottomTrailing) {
                                    if selection == source {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.white, Color.accentColor)
                                            .font(.title3)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(store.t("presetAvatars") + " " + String(index + 1))
                        .accessibilityAddTraits(selection == source ? .isSelected : [])
                    }
                }
                .padding(5)
            }
            .disabled(store.profileBusy)
            Text(error)
                .font(.callout)
                .foregroundStyle(.red)
                .textSelection(.enabled)
            HStack {
                Spacer()
                Button(store.t("cancel")) {
                    dismiss()
                }
                .disabled(store.profileBusy)
                Button(store.t("save")) {
                    Task {
                        do {
                            try await store.saveProfile(["avatar": selection])
                            dismiss()
                        } catch {
                            self.error = error.localizedDescription
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(selection.isEmpty || store.profileBusy)
            }
        }
        .padding(28)
        .frame(width: 450, height: 560)
        .interactiveDismissDisabled(store.profileBusy)
        .onAppear {
            selection = store.user?.avatar_url ?? ""
        }
    }

    private func dataURI(_ url: URL) -> String {
        guard let data = try? Data(contentsOf: url) else {
            return ""
        }
        let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "image/png"
        return "data:" + mime + ";base64," + data.base64EncodedString()
    }
}

private struct ProfileAvatar: View {

    let source: String
    let api: String
    @State private var image: NSImage?

    var body: some View {
        AnimatedProfileImage(image: image ?? fallback)
            .task(id: source) {
                image = nil
                if source.hasPrefix("data:image/"), let comma = source.firstIndex(of: ","),
                   let data = Data(base64Encoded: String(source[source.index(after: comma)...])) {
                    image = NSImage(data: data)
                } else if !source.isEmpty,
                          let url = URL(string: source, relativeTo: URL(string: api))?.absoluteURL,
                          ["http", "https"].contains(url.scheme) {
                    if let (data, response) = try? await URLSession.shared.data(from: url),
                       (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) == true,
                       !Task.isCancelled {
                        image = NSImage(data: data)
                    }
                }
            }
    }

    private var fallback: NSImage {
        let path = Bundle.main.resourceURL!.appendingPathComponent("icon.png").path
        return NSImage(contentsOfFile: path) ?? NSImage()
    }
}

private struct AnimatedProfileImage: NSViewRepresentable {

    let image: NSImage
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.imageScaling = .scaleProportionallyUpOrDown
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        return view
    }

    func sizeThatFits(_ proposal: ProposedViewSize,
                      nsView: NSImageView,
                      context: Context) -> CGSize? {
        return CGSize(width: proposal.width ?? 80, height: proposal.height ?? 80)
    }

    func updateNSView(_ view: NSImageView,
                      context: Context) {
        if view.image !== image {
            view.image = image
        }
        view.animates = !reduceMotion && scenePhase == .active
    }
}
