//
//  ZhixuMac.swift
//  ZhixuMac
//
//  Created by Jobs on 2026年11月18日，星期三.
//

import AppKit
import Combine
import CoreText
import SwiftUI

@main struct ZhixuMac: App {

    @StateObject private var store = ShopStore()

    init() {
        for name in ["NotoSerifTibetan.ttf", "NotoSansCJKsc-Regular.otf"] {
            if let url = Bundle.main.resourceURL?.appendingPathComponent("Fonts/" + name) {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }

    var body: some Scene {
        WindowGroup("知序") {
            ShopView(store: store)
                .frame(minWidth: 960, minHeight: 600)
                .preferredColorScheme(store.theme == "system" ? nil : (store.theme == "dark" ? .dark : .light))
        }
        .defaultSize(width: 1100, height: 780)
        .windowResizability(.contentMinSize)
    }
}

struct FormRequest: Identifiable {

    let id = UUID()
    var title: String
    var fields: [(String, String)] = []
    var values: [String: String] = [:]
    var submit: ([String: String]) async throws -> Void
}

struct ShopView: View {

    @ObservedObject var store: ShopStore
    @State private var page = "home"
    @State private var category = "all"
    @State private var status = "all"
    @State private var detail: Product?
    @State private var form: FormRequest?
    @State private var pendingDestination: String?
    @State private var settings = false
    @State private var accountMenu = false
    @State private var bannerIndex = 0
    @State private var draggingBanner = false
    @State private var categoryDirection = 1
    @State private var orderStatusDirection = 1
    @State private var orderFilterHeight: CGFloat = 44
    @State private var contentScrollView: NSScrollView?
    @State private var catalogScrollOrigin: NSPoint = .zero
    @GestureState private var categoryDrag: CGFloat = 0
    @GestureState private var orderDrag: CGFloat = 0
    @Namespace private var categorySelection
    @Namespace private var orderStatusSelection
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let bannerTimer = Timer.publish(every: 4.5, on: .main, in: .common).autoconnect()
    private let categories = ["all", "graduation", "journal", "editing"]
    private let orderStatuses = ["all", "pending_payment", "pending_completion", "pending_review", "completed", "cancelled"]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 18) {
                Text("知序").font(.title.bold())
                HStack(spacing: 6) {
                    ForEach(["home", "myOrders", "mine"], id: \.self) { item in
                        Button(store.t(item)) {
                            navigate(to: item)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .foregroundStyle(page == item ? activeForeground : Color.primary)
                        .background(page == item ? activeBackground : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                Text("\(Text(store.t("hero")).font(.system(size: 20, weight: .semibold, design: .serif))) \(Text(store.t("intro")).font(.caption).foregroundColor(.secondary))")
                    .lineLimit(1)
                    .minimumScaleFactor(0.25)
                    .accessibilityLabel(store.t("hero") + " " + store.t("intro"))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .layoutPriority(-1)
                if let user = store.user {
                    Button {
                        accountMenu.toggle()
                    } label: {
                        HStack(spacing: 7) {
                            Text(user.name).lineLimit(1)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(user.name + ", " + store.t("accountMenu"))
                    .popover(isPresented: $accountMenu, arrowEdge: .bottom) {
                        accountActions
                    }
                } else {
                    Button(store.t("login")) {
                        auth()
                    }
                }
            }
            .padding(20)
            Divider()
            GeometryReader { viewport in
                ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if store.user != nil && store.hasPendingWrite {
                        HStack {
                            Text(store.t("pendingWrite"))
                            Spacer()
                            Button(store.t("retry")) {
                                Task {
                                    do {
                                        try await store.retryPending()
                                    } catch {
                                        store.error = error.localizedDescription
                                    }
                                }
                            }
                            .disabled(store.busy)
                        }
                        .padding(15)
                        .background(.background, in: RoundedRectangle(cornerRadius: 10))
                    }
                    if let detail {
                        productDetail(detail)
                    } else if page == "home" {
                        home
                    } else if store.user == nil {
                        AuthGate(store: store) {
                            auth(target: page)
                        }
                    } else if page == "myOrders" {
                        orderList(minimumHeight: max(0, viewport.size.height - 56 - (store.hasPendingWrite ? 80 : 0)))
                    } else {
                        profile
                    }
                }
                .padding(28)
                .frame(maxWidth: 1120, alignment: .leading)
                .frame(maxWidth: .infinity)
                .background(NativeScrollContext { scrollView in
                    if contentScrollView !== scrollView {
                        contentScrollView = scrollView
                    }
                })
                }
                .id(page)
            }
            Divider()
            HStack {
                Text(store.t(store.online ? "online" : (store.demoAvailable ? "offline" : "updateFailed")))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    settings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel(store.t("settings"))
                .help(store.t("settings"))
            }
            .padding(14)
        }
        .tint(colorScheme == .dark ? Color(red: 0.65, green: 0.86, blue: 0.70) : Color(red: 0.22, green: 0.42, blue: 0.29))
        .task {
            await store.refreshDemoMode()
            await store.refresh()
            await store.refreshBanners()
        }
        .onReceive(bannerTimer) { _ in
            if scenePhase == .active && !reduceMotion && !draggingBanner && page == "home" && detail == nil && form == nil && !settings && !accountMenu && bannerItems.count > 1 {
                selectBanner(bannerIndex + 1)
            }
        }
        .sheet(item: $form, onDismiss: {
            pendingDestination = nil
        }) { request in
            if request.title == "login" {
                AuthDoor(store: store) {
                    if let target = pendingDestination {
                        page = target
                        detail = nil
                    }
                    pendingDestination = nil
                }
            } else {
                NativeForm(request: request, store: store)
            }
        }
        .sheet(isPresented: $settings) {
            SettingsView(store: store)
        }
        .onChange(of: store.user?.id) { id in
            if id == nil {
                page = "home"
                detail = nil
            }
        }
        .alert(store.error, isPresented: Binding(get: { !store.error.isEmpty }, set: { _ in store.error = "" })) {
            Button(store.t("dismiss")) {
                store.error = ""
            }
        }
    }

    var accountActions: some View {
        VStack(spacing: 8) {
            Button {
                let destination = page == "home" ? nil : page
                accountMenu = false
                store.logout()
                page = "home"
                detail = nil
                DispatchQueue.main.async {
                    auth(target: destination)
                }
            } label: {
                Label(store.t("switchAccount"), systemImage: "arrow.triangle.2.circlepath")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .contentShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            Button(role: .destructive) {
                accountMenu = false
                pendingDestination = nil
                store.logout()
                page = "home"
                detail = nil
            } label: {
                Label(store.t("exit"), systemImage: "rectangle.portrait.and.arrow.right")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .foregroundStyle(.white)
                    .background(Color(red: 0.72, green: 0.10, blue: 0.14), in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .frame(width: 220)
    }

    func navigate(to target: String) {
        if target != "home", store.user == nil {
            auth(target: target)
            return
        }
        pendingDestination = nil
        page = target
        detail = nil
        Task {
            await store.refresh()
        }
    }

    var home: some View {
        VStack(alignment: .leading, spacing: 28) {
            banner
            categoryCards
            catalogPage
                .id(category)
                .transition(reduceMotion ? .identity : .asymmetric(insertion: .offset(x: CGFloat(categoryDirection) * 36).combined(with: .opacity),
                                                                  removal: .offset(x: CGFloat(categoryDirection) * -36).combined(with: .opacity)))
                .offset(x: reduceMotion ? 0 : categoryDrag * 0.16)
                .contentShape(Rectangle())
                .simultaneousGesture(DragGesture(minimumDistance: 30)
                    .updating($categoryDrag) { value, drag, _ in
                        if abs(value.translation.width) > abs(value.translation.height) {
                            drag = value.translation.width
                        }
                    }
                    .onEnded { value in
                        guard abs(value.translation.width) > 55,
                              abs(value.translation.width) > abs(value.translation.height) else {
                            return
                        }
                        moveCategory(value.translation.width < 0 ? 1 : -1)
                    })
        }
    }

    var categoryCards: some View {
        HStack(spacing: 12) {
            ForEach(categories, id: \.self) { value in
                Button {
                    selectCategory(value)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: categorySymbol(value))
                            .font(.system(size: 20, weight: .regular))
                            .frame(width: 22)
                        Text(store.t(value))
                            .font(.system(size: 18, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                        Spacer(minLength: 0)
                        Text(String(store.products.filter { $0.active && (value == "all" || $0.category_id == value) }.count))
                            .font(.system(size: 22, weight: .semibold).monospacedDigit())
                            .fixedSize()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                    .foregroundStyle(category == value ? activeForeground : Color.primary)
                    .background {
                        if category == value {
                            RoundedRectangle(cornerRadius: 14)
                                .fill(activeBackground)
                                .matchedGeometryEffect(id: "category", in: categorySelection)
                        } else {
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color(nsColor: .controlBackgroundColor))
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(store.t(value))
                .accessibilityValue(store.t(category == value ? "selected" : "unselected"))
                .accessibilityAddTraits(category == value ? .isSelected : [])
                .onMoveCommand { direction in
                    if direction == .left {
                        moveCategory(-1)
                    } else if direction == .right {
                        moveCategory(1)
                    }
                }
            }
        }
    }

    var catalogPage: some View {
        let products = store.products.filter { $0.active && (category == "all" || $0.category_id == category) }
        return VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(store.t(category)).font(.title2.weight(.semibold))
                Spacer()
                HStack(spacing: 8) {
                    Button {
                        moveCategory(-1)
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(category == categories.first)
                    .accessibilityLabel(store.t("previousCategory"))
                    Button {
                        moveCategory(1)
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .disabled(category == categories.last)
                    .accessibilityLabel(store.t("nextCategory"))
                }
            }
            if products.isEmpty {
                empty("emptyProducts")
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 255), spacing: 20)], spacing: 20) {
                ForEach(products) { product in
                    Button {
                        catalogScrollOrigin = contentScrollView?.contentView.bounds.origin ?? .zero
                        detail = product
                        restoreContentScroll(to: .zero)
                    } label: {
                        VStack(alignment: .leading, spacing: 12) {
                            productImage(product).frame(height: 128).clipped().clipShape(RoundedRectangle(cornerRadius: 8))
                            Text(store.t(product.category_id)).font(.caption).foregroundStyle(.secondary)
                            Text(product.name).font(.title3.bold())
                            Text(product.summary).foregroundStyle(.secondary).lineLimit(2)
                            HStack {
                                Text(product.price).font(.title2.bold())
                                Spacer()
                                Label(store.t("details"), systemImage: "arrow.up.right")
                                    .font(.callout.weight(.medium))
                                    .foregroundStyle(.tint)
                            }
                        }
                        .padding(18)
                        .background(.background, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.secondary.opacity(0.18)))
                        .contentShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(product.name + ", " + store.t("details"))
                }
            }
        }
    }

    func categorySymbol(_ value: String) -> String {
        switch value {
        case "graduation":
            return "graduationcap"
        case "journal":
            return "book.closed"
        case "editing":
            return "character.book.closed"
        default:
            return "square.grid.2x2"
        }
    }

    func moveCategory(_ direction: Int) {
        let index = categories.firstIndex(of: category) ?? 0
        let target = min(max(index + direction, 0), categories.count - 1)
        selectCategory(categories[target])
    }

    func selectCategory(_ value: String) {
        guard value != category else {
            return
        }
        categoryDirection = (categories.firstIndex(of: value) ?? 0) > (categories.firstIndex(of: category) ?? 0) ? 1 : -1
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.24)) {
            category = value
        }
    }

    var activeBackground: Color {
        return colorScheme == .dark ? Color(red: 0.65, green: 0.86, blue: 0.70) : Color(red: 0.22, green: 0.42, blue: 0.29)
    }

    var activeForeground: Color {
        return colorScheme == .dark ? Color(red: 0.10, green: 0.20, blue: 0.13) : .white
    }

    var bannerItems: [ShopBanner] {
        return store.banners ?? ["graduation", "journal", "editing"].map { value in
            ShopBanner(id: value, title: store.t(value), image: "", target_url: "")
        }
    }

    @ViewBuilder var banner: some View {
        let banners = bannerItems
        if !banners.isEmpty {
            let current = banners[bannerIndex % banners.count]
            let fallback = ["graduation", "journal", "editing"].contains(current.id) ? current.id : "graduation"
            VStack(spacing: 14) {
                GeometryReader { geometry in
                    Group {
                        if current.image.isEmpty {
                            HStack(spacing: 28) {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text(current.title)
                                        .font(.system(size: 30, weight: .semibold, design: .serif))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.7)
                                    Text(store.t("intro"))
                                        .font(.body)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 20)
                                localImage("icon")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 88, height: 88)
                            }
                            .padding(.horizontal, 36)
                        } else {
                            imageSource(current.image, fallback: fallback, mode: .fit)
                        }
                    }
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipped()
                        .id(current.id)
                        .transition(reduceMotion ? .identity : .opacity.combined(with: .scale(scale: 1.015)))
                }
                .aspectRatio(1440.0 / 280.0, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .accessibilityLabel(current.title)
                .onTapGesture {
                    if let url = URL(string: current.target_url), ["http", "https"].contains(url.scheme) {
                        NSWorkspace.shared.open(url)
                    }
                }
                .gesture(DragGesture(minimumDistance: 15)
                    .onChanged { _ in
                        draggingBanner = true
                    }
                    .onEnded { value in
                        if abs(value.translation.width) > 25 && abs(value.translation.width) > abs(value.translation.height) {
                            selectBanner(bannerIndex + (value.translation.width < 0 ? 1 : -1))
                        }
                        draggingBanner = false
                    })
                HStack(spacing: 5) {
                    ForEach(banners.indices, id: \.self) { index in
                        Button {
                            selectBanner(index)
                        } label: {
                            Circle()
                                .fill(index == bannerIndex % banners.count ? activeBackground : .clear)
                                .overlay(Circle().stroke(activeBackground, lineWidth: 1.3))
                                .frame(width: 8, height: 8)
                                .frame(width: 24, height: 20)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(store.t("banners") + " " + String(index + 1))
                        .accessibilityAddTraits(index == bannerIndex % banners.count ? .isSelected : [])
                    }
                }
            }
        }
    }

    func selectBanner(_ index: Int) {
        guard !bannerItems.isEmpty else {
            return
        }
        let count = bannerItems.count
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) {
            bannerIndex = ((index % count) + count) % count
        }
    }

    func localImage(_ name: String) -> Image {
        let path = Bundle.main.resourceURL!.appendingPathComponent(name + ".png").path
        return Image(nsImage: NSImage(contentsOfFile: path) ?? NSImage())
    }

    func productImage(_ product: Product) -> some View {
        return GeometryReader { geometry in
            imageSource(product.image, fallback: product.category_id, mode: .fill)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
        }
    }

    @ViewBuilder func imageSource(_ source: String,
                                  fallback: String,
                                  mode: ContentMode) -> some View {
        if source.hasPrefix("data:image/"),
           let encoded = source.components(separatedBy: ",").last,
           let data = Data(base64Encoded: encoded),
           let image = NSImage(data: data) {
            Image(nsImage: image).resizable().aspectRatio(contentMode: mode)
        } else {
            let target = URL(string: source, relativeTo: URL(string: store.api))?.absoluteURL
            let allowed = target.map { ["http", "https"].contains($0.scheme) } == true
            AsyncImage(url: allowed && !source.isEmpty ? target : nil) { phase in
                if case .success(let image) = phase {
                    image.resizable().aspectRatio(contentMode: mode)
                } else {
                    localImage(fallback).resizable().aspectRatio(contentMode: mode)
                }
            }
        }
    }

    func productDetail(_ product: Product) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Button {
                detail = nil
                restoreContentScroll(to: catalogScrollOrigin)
            } label: {
                Label(store.t("back"), systemImage: "chevron.left")
            }
            Text(product.name).font(.largeTitle.bold())
            productImage(product).frame(height: 240).clipped()
            Text(product.price).font(.title.bold())
            Text(product.description)
            ForEach(product.sections.indices, id: \.self) { index in
                Text(product.sections[index].title).font(.title2)
                Text(product.sections[index].body)
            }
            Button(store.t(product.in_stock ? "buy" : "outOfStock")) {
                guard store.user != nil else {
                    auth()
                    return
                }
                requirements(product: product)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!product.in_stock)
        }
    }

    func restoreContentScroll(to origin: NSPoint) {
        // Restore only after SwiftUI has replaced the detail/catalog document.
        DispatchQueue.main.async {
            guard let scrollView = contentScrollView else {
                return
            }
            scrollView.contentView.scroll(to: origin)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }

    func orderList(minimumHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            orderStatusCards
                .background(GeometryReader { geometry in
                    Color.clear.preference(key: OrderFilterHeightKey.self, value: geometry.size.height)
                })
                .onPreferenceChange(OrderFilterHeightKey.self) { height in
                    orderFilterHeight = height
                }
            orderContent(minimumHeight: max(260, minimumHeight - orderFilterHeight - 20))
                .id(status)
                .transition(reduceMotion ? .identity : .asymmetric(insertion: .offset(x: CGFloat(orderStatusDirection) * 36).combined(with: .opacity),
                                                                  removal: .offset(x: CGFloat(orderStatusDirection) * -36).combined(with: .opacity)))
                .offset(x: reduceMotion ? 0 : orderDrag * 0.16)
                .contentShape(Rectangle())
                .simultaneousGesture(DragGesture(minimumDistance: 30)
                    .updating($orderDrag) { value, drag, _ in
                        if abs(value.translation.width) > abs(value.translation.height) {
                            drag = value.translation.width
                        }
                    }
                    .onEnded { value in
                        guard abs(value.translation.width) > 55,
                              abs(value.translation.width) > abs(value.translation.height) else {
                            return
                        }
                        moveOrderStatus(value.translation.width < 0 ? 1 : -1)
                    })
        }
    }

    var orderStatusCards: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(orderStatuses, id: \.self) { value in
                        let count = store.orders.filter { value == "all" || $0.status == value }.count
                        Button {
                            selectOrderStatus(value)
                        } label: {
                            HStack(spacing: 9) {
                                Text(store.t(value))
                                    .font(.system(size: 18, weight: .semibold))
                                Text(String(count))
                                    .font(.system(size: 22, weight: .semibold).monospacedDigit())
                            }
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 14)
                            .frame(minWidth: 136, minHeight: 64)
                            .foregroundStyle(status == value ? activeForeground : Color.primary)
                            .background {
                                if status == value {
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(activeBackground)
                                        .matchedGeometryEffect(id: "order-status", in: orderStatusSelection)
                                } else {
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(Color(nsColor: .controlBackgroundColor))
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(store.t(value) + " (" + String(count) + ")")
                        .accessibilityValue(store.t(status == value ? "selected" : "unselected"))
                        .accessibilityAddTraits(status == value ? .isSelected : [])
                        .onMoveCommand { direction in
                            if direction == .left {
                                moveOrderStatus(-1)
                            } else if direction == .right {
                                moveOrderStatus(1)
                            }
                        }
                        .id(value)
                    }
                }
                .padding(.vertical, 3)
            }
            .frame(height: 70)
            .onAppear {
                proxy.scrollTo(status, anchor: .center)
            }
            .onChange(of: status) { value in
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.24)) {
                    proxy.scrollTo(value, anchor: .center)
                }
            }
        }
    }

    func moveOrderStatus(_ direction: Int) {
        let index = orderStatuses.firstIndex(of: status) ?? 0
        let target = min(max(index + direction, 0), orderStatuses.count - 1)
        selectOrderStatus(orderStatuses[target])
    }

    func selectOrderStatus(_ value: String) {
        guard value != status else {
            return
        }
        orderStatusDirection = (orderStatuses.firstIndex(of: value) ?? 0) > (orderStatuses.firstIndex(of: status) ?? 0) ? 1 : -1
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.24)) {
            status = value
        }
        restoreContentScroll(to: .zero)
    }

    func orderContent(minimumHeight: CGFloat) -> some View {
        let orders = store.orders.filter { status == "all" || $0.status == status }
        return VStack(alignment: .leading, spacing: 20) {
            if orders.isEmpty {
                empty("emptyOrders")
                    .frame(minHeight: minimumHeight)
            }
            ForEach(orders) { order in
                VStack(alignment: .leading, spacing: 12) {
                    Text(order.product_snapshot.name).font(.title2.bold())
                    Text(order.id).font(.caption).textSelection(.enabled)
                    Text(order.product_snapshot.price + " · " + store.t(order.status) + " · " + store.t(order.fulfillment_status))
                    Text(order.requirements ?? "")
                    if let delivery = order.delivery_text, !delivery.isEmpty {
                        Text(delivery).textSelection(.enabled)
                    }
                    HStack {
                        if order.editable == true {
                            Button(store.t("editRequirements")) {
                                requirements(order: order)
                            }
                        }
                        if order.status == "pending_payment" {
                            ForEach(["alipay", "wechat"], id: \.self) { channel in
                                Button(store.t(channel)) {
                                    actionForm(order, action: "pay", fields: [], values: ["channel": channel])
                                }
                            }
                            Button(store.t("cancel")) {
                                actionForm(order, action: "cancel", fields: [])
                            }
                        }
                        if order.status == "pending_completion" && order.fulfillment_status == "delivered" {
                            Button(store.t("accept")) {
                                actionForm(order, action: "accept", fields: [])
                            }
                        }
                        if order.status == "pending_review" {
                            Button(store.t("review")) {
                                actionForm(order, action: "review", fields: [("rating", "number"), ("text", "multiline")], values: ["rating": "5"])
                            }
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.background, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.secondary.opacity(0.3)))
            }
        }
        .frame(maxWidth: .infinity, minHeight: minimumHeight, alignment: .topLeading)
    }

    var profile: some View {
        ProfileView(store: store) {
            navigate(to: "myOrders")
        }
    }

    func empty(_ key: String) -> some View {
        VStack(spacing: 15) {
            localImage("icon").resizable().frame(width: 60, height: 60)
            Text(store.t(key)).font(.title2)
            Text(store.t("emptyHint")).foregroundStyle(.secondary)
            Button(store.t("reload")) {
                Task {
                    await store.refresh()
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }

    func auth(target: String? = nil) {
        pendingDestination = target
        form = FormRequest(title: "login", fields: [("account", "text"), ("password", "password")]) { values in
            try await store.login(values)
        }
    }

    func requirements(product: Product? = nil,
                      order: ShopOrder? = nil) {
        form = FormRequest(title: order == nil ? "buy" : "editRequirements",
                           fields: [("requirements", "multiline"), ("contact", "text"), ("deliveryRequirements", "multiline")],
                           values: ["requirements": order?.requirements ?? "", "contact": order?.contact ?? "", "deliveryRequirements": order?.delivery_requirements ?? ""]) { values in
            var body: [String: Any] = ["requirements": values["requirements"] ?? "", "contact": values["contact"] ?? "", "delivery_requirements": values["deliveryRequirements"] ?? ""]
            if let product {
                body["product_id"] = product.id
                body["product_version"] = product.version
                try await store.write("/shop-orders", body: body)
            } else if let order {
                body["action"] = "edit"
                body["expected_version"] = order.version
                try await store.write("/shop-orders/" + order.id + "/actions", body: body)
            }
        }
    }

    func actionForm(_ order: ShopOrder,
                    action: String,
                    fields: [(String, String)],
                    values: [String: String] = [:]) {
        form = FormRequest(title: action == "pay" ? "mockHint" : action, fields: fields, values: values) { values in
            var body: [String: Any] = values
            body["action"] = action
            body["expected_version"] = order.version
            if action == "review" {
                guard let rating = Int(values["rating"] ?? ""), (1...5).contains(rating), !(values["text"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw APIError(status: 422, message: store.t("requiredReview"))
                }
                body["rating"] = rating
            }
            try await store.write("/shop-orders/" + order.id + "/actions", body: body)
        }
    }
}

private struct OrderFilterHeightKey: PreferenceKey {

    static var defaultValue: CGFloat = 44

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct NativeScrollContext: NSViewRepresentable {

    let resolve: (NSScrollView) -> Void

    func makeNSView(context: Context) -> NSView {
        return NSView()
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            if let scrollView = view.enclosingScrollView {
                resolve(scrollView)
            }
        }
    }
}
