import SwiftUI
import StoreKit
import RevenueCat

// MARK: - Configuration Constants
enum RevenueCatConfig {
    // Thay bằng Public SDK Key của App Store từ RevenueCat Dashboard (bắt đầu bằng appl_, KHÔNG dùng test_)
    static let apiKey = "appl_JngFETzdodyLmCREOlwTUtXdQik"
    static let bundleID = "com.locket.Locket"
    static let appUserID = "1a73l0yKjleF7djpO7oYeP4u8ri1"
    static let offeringID = "locket_199"
    static let packageID = "$rc_annual"
    static let productID = "locket_1600_1y"
    static let productIDMonthly = "locket_199_1m"
    static let entitlementID = "gold"
}

// MARK: - Main Application Entry Point
@main
struct SandboxPurchaseTestApp: App {
    @StateObject private var viewModel = SandboxPurchaseViewModel()

    init() {
        // Bật log mức Debug của RevenueCat để theo dõi chi tiết StoreKit sync và network calls
        Purchases.logLevel = .debug

        // Khởi tạo RevenueCat Purchases với App Store public SDK key
        Purchases.configure(
            with: Configuration.builder(withAPIKey: RevenueCatConfig.apiKey)
                .with(appUserID: RevenueCatConfig.appUserID)
                .build()
        )
        print("🚀 [App] Configured RevenueCat for Apple StoreKit Sandbox. User ID: \(RevenueCatConfig.appUserID)")
    }

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
        }
    }
}

// MARK: - View Model
@MainActor
final class SandboxPurchaseViewModel: ObservableObject {
    // 1. Config & StoreKit Direct Product Info
    @Published var appUserID: String = RevenueCatConfig.appUserID
    @Published var targetProductID: String = RevenueCatConfig.productID
    @Published var targetOfferingID: String = RevenueCatConfig.offeringID
    @Published var targetPackageID: String = RevenueCatConfig.packageID
    @Published var targetEntitlementID: String = RevenueCatConfig.entitlementID

    @Published var storeKitProduct: Product?
    @Published var storeKitDisplayName: String = "-"
    @Published var storeKitDisplayPrice: String = "-"
    @Published var storeKitProductTypeString: String = "-"

    // 2. RevenueCat State
    @Published var isGoldActive: Bool = false
    @Published var rcOriginalAppUserId: String = "-"
    @Published var rcActiveSubscriptions: [String] = []
    @Published var rcAllPurchasedProducts: [String] = []
    @Published var rcProductIdentifier: String = "-"
    @Published var rcPeriodType: String = "-"
    @Published var rcOwnershipType: String = "-"
    @Published var rcStore: String = "-"
    @Published var rcLatestPurchaseDate: String = "-"
    @Published var rcExpirationDate: String = "-"
    private(set) var rcPackage: Package?

    // 3. StoreKit 2 Transaction Details
    @Published var storeKitIsVerified: Bool = false
    @Published var storeKitVerificationMessage: String = "No transaction checked"
    @Published var storeKitTransactionID: String = "-"
    @Published var storeKitOriginalTransactionID: String = "-"
    @Published var storeKitProductID: String = "-"
    @Published var storeKitProductType: String = "-"
    @Published var storeKitPurchaseDate: String = "-"
    @Published var storeKitOriginalPurchaseDate: String = "-"
    @Published var storeKitExpirationDate: String = "-"
    @Published var storeKitRevocationDate: String = "nil"
    @Published var storeKitRevocationReason: String = "nil"
    @Published var storeKitIsUpgraded: String = "false"
    @Published var storeKitOwnershipType: String = "-"
    @Published var storeKitEnvironment: String = "sandbox"
    @Published var storeKitAppAccountToken: String = "nil"

    // 4. Signed Transaction JWS
    @Published var signedTransactionJWS: String = ""
    @Published var jwsExplanation: String = "StoreKit 2 signed transaction JWS (Apple Compact Serialization). Đây là token mã hóa bảo mật do StoreKit 2 cấp phát cho transaction này."

    // 5. Raw Debug JSON
    @Published var unifiedDebugJSON: String = ""

    // 6. UI & Error State
    @Published var isLoading: Bool = false
    @Published var statusMessage: String = "Ready"
    @Published var errorMessage: String? = nil
    @Published var copiedNotice: String? = nil

    private let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    // MARK: - Initial Startup Load
    func initialLoad() async {
        await fetchStoreKitProduct()
        await fetchRevenueCatOfferings()
        await refreshCustomerInfo()
        await loadLatestStoreKitTransaction()
    }

    // MARK: - 1. Fetch StoreKit 2 Product Directly
    func fetchStoreKitProduct() async {
        isLoading = true
        errorMessage = nil
        statusMessage = "Fetching Product from StoreKit 2..."

        do {
            let products = try await Product.products(for: [RevenueCatConfig.productID, RevenueCatConfig.productIDMonthly])
            if let product = products.first(where: { $0.id == RevenueCatConfig.productIDMonthly }) ?? products.first {
                self.storeKitProduct = product
                self.targetProductID = product.id
                self.storeKitDisplayName = product.displayName
                self.storeKitDisplayPrice = product.displayPrice
                self.storeKitProductTypeString = String(describing: product.type)
                print("🍏 [StoreKit 2] Loaded product: \(product.id) | \(product.displayName) | \(product.displayPrice)")
                statusMessage = "StoreKit 2 Product loaded: \(product.displayName) (\(product.displayPrice))"
            } else {
                let msg = "Products '\(RevenueCatConfig.productID)' / '\(RevenueCatConfig.productIDMonthly)' not found in StoreKit. Check .storekit config."
                print("⚠️ [StoreKit 2] \(msg)")
                self.errorMessage = msg
                statusMessage = "StoreKit Product unavailable."
            }
        } catch {
            print("❌ [StoreKit 2] Error fetching product: \(error.localizedDescription)")
            self.errorMessage = "StoreKit error: \(error.localizedDescription)"
            statusMessage = "Failed to load StoreKit product."
        }

        isLoading = false
    }

    // MARK: - 2. Fetch RevenueCat Offerings
    func fetchRevenueCatOfferings() async {
        isLoading = true
        errorMessage = nil
        statusMessage = "Fetching RevenueCat Offerings..."

        do {
            let offerings = try await Purchases.shared.offerings()
            guard let defaultOffering = offerings.offering(identifier: RevenueCatConfig.offeringID) else {
                let available = offerings.all.keys.joined(separator: ", ")
                let msg = "Offering '\(RevenueCatConfig.offeringID)' unavailable in RevenueCat. Available: [\(available)]"
                print("⚠️ [RevenueCat] \(msg)")
                self.errorMessage = msg
                statusMessage = "Offering unavailable."
                isLoading = false
                return
            }

            if let pkg = defaultOffering.package(identifier: RevenueCatConfig.packageID) {
                self.rcPackage = pkg
                print("📦 [RevenueCat] Found package: \(pkg.identifier) with product: \(pkg.storeProduct.productIdentifier)")
                statusMessage = "RevenueCat package '\(pkg.identifier)' loaded."
            } else {
                let availPkg = defaultOffering.availablePackages.map { $0.identifier }.joined(separator: ", ")
                let msg = "Package '\(RevenueCatConfig.packageID)' not found in offering. Available: [\(availPkg)]"
                print("⚠️ [RevenueCat] \(msg)")
                self.errorMessage = msg
                statusMessage = "Package unavailable."
            }
        } catch {
            print("❌ [RevenueCat] Error fetching offerings: \(error.localizedDescription)")
            self.errorMessage = "RevenueCat error: \(error.localizedDescription)"
            statusMessage = "Failed to fetch offerings."
        }

        isLoading = false
    }

    // MARK: - 3. Purchase with RevenueCat (Apple StoreKit Sandbox)
    func purchaseWithRevenueCat() async {
        guard let pkg = rcPackage else {
            self.errorMessage = "RevenueCat package not loaded. Tap 'Fetch RevenueCat Offering' first."
            return
        }

        isLoading = true
        errorMessage = nil
        statusMessage = "Purchasing via RevenueCat in Apple Sandbox..."

        print("🛒 [RevenueCat] Initiating Sandbox purchase for package: \(pkg.identifier)...")

        do {
            let result = try await Purchases.shared.purchase(package: pkg)

            // Kiểm tra user chủ động cancel
            if result.userCancelled {
                print("ℹ️ [Purchase] User cancelled Sandbox purchase flow.")
                statusMessage = "Purchase cancelled by user."
                isLoading = false
                return
            }

            print("✅ [Purchase] RevenueCat purchase succeeded! Syncing with StoreKit 2...")
            
            // Cập nhật CustomerInfo từ kết quả purchase
            handleCustomerInfo(result.customerInfo)

            // Đồng bộ và tải StoreKit 2 transaction đã verify
            await loadLatestStoreKitTransaction()

            buildUnifiedDebugJSON()
            statusMessage = "Sandbox purchase completed & synced successfully!"
        } catch {
            // Xử lý mã lỗi User Cancelled riêng biệt
            if let rcError = error as? RevenueCat.ErrorCode, rcError == .purchaseCancelledError {
                print("ℹ️ [Purchase] User cancelled purchase.")
                statusMessage = "Purchase cancelled by user."
            } else if (error as NSError).code == RevenueCat.ErrorCode.purchaseCancelledError.rawValue {
                print("ℹ️ [Purchase] User cancelled purchase.")
                statusMessage = "Purchase cancelled by user."
            } else {
                print("❌ [Purchase] RevenueCat purchase error: \(error.localizedDescription)")
                self.errorMessage = "Purchase error: \(error.localizedDescription)"
                statusMessage = "Purchase failed."
            }
        }

        isLoading = false
    }

    // MARK: - 3b. Purchase via Native StoreKit 2 Directly (KHÔNG CẦN ACCOUNT SANDBOX KHI DÙNG .storekit)
    func purchaseDirectWithStoreKit2() async {
        guard let product = storeKitProduct else {
            errorMessage = "StoreKit product chưa tải được. Nhấn 'Fetch StoreKit Product' trước."
            return
        }

        isLoading = true
        errorMessage = nil
        statusMessage = "Purchasing directly via StoreKit 2 (Local / Sandbox)..."

        do {
            let purchaseResult = try await product.purchase()

            switch purchaseResult {
            case .success(let verificationResult):
                self.signedTransactionJWS = verificationResult.jwsRepresentation

                switch verificationResult {
                case .verified(let transaction):
                    self.storeKitIsVerified = true
                    self.storeKitVerificationMessage = "Verified by Apple StoreKit 2"
                    self.storeKitTransactionID = String(transaction.id)
                    self.storeKitOriginalTransactionID = String(transaction.originalID)
                    self.storeKitProductID = transaction.productID
                    self.storeKitPurchaseDate = isoFormatter.string(from: transaction.purchaseDate)
                    if let exp = transaction.expirationDate {
                        self.storeKitExpirationDate = isoFormatter.string(from: exp)
                    }
                    self.isGoldActive = true
                    await transaction.finish()
                    print("✅ [StoreKit 2 Direct] Verified Transaction ID: \(transaction.id)")
                    statusMessage = "StoreKit 2 direct purchase succeeded!"

                case .unverified(let transaction, let err):
                    self.storeKitIsVerified = false
                    self.storeKitVerificationMessage = "Unverified: \(err.localizedDescription)"
                    self.storeKitTransactionID = String(transaction.id)
                    self.errorMessage = "StoreKit 2 unverified: \(err.localizedDescription)"
                }

                // Sync with RevenueCat nếu SDK đang hoạt động
                try? await Purchases.shared.syncPurchases()
                await refreshCustomerInfo()
                buildUnifiedDebugJSON()

            case .userCancelled:
                statusMessage = "Purchase cancelled by user."
                print("ℹ️ [StoreKit 2 Direct] User cancelled purchase.")

            case .pending:
                statusMessage = "Purchase pending authorization."
                print("⏳ [StoreKit 2 Direct] Purchase pending.")

            @unknown default:
                break
            }
        } catch {
            print("❌ [StoreKit 2 Direct] Error: \(error.localizedDescription)")
            self.errorMessage = "StoreKit 2 direct purchase error: \(error.localizedDescription)"
            statusMessage = "StoreKit 2 purchase failed."
        }

        isLoading = false
    }

    // MARK: - 4. Refresh CustomerInfo
    func refreshCustomerInfo() async {
        isLoading = true
        errorMessage = nil
        statusMessage = "Refreshing RevenueCat CustomerInfo..."

        do {
            let info = try await Purchases.shared.customerInfo()
            handleCustomerInfo(info)
            buildUnifiedDebugJSON()
            statusMessage = "CustomerInfo refreshed."
        } catch {
            print("❌ [RevenueCat] Error refreshing CustomerInfo: \(error.localizedDescription)")
            self.errorMessage = "CustomerInfo error: \(error.localizedDescription)"
            statusMessage = "Failed to refresh CustomerInfo."
        }

        isLoading = false
    }

    // MARK: - 5. Load Latest StoreKit 2 Transaction & JWS
    func loadLatestStoreKitTransaction() async {
        isLoading = true
        statusMessage = "Verifying latest StoreKit 2 Transaction..."

        let currentTargetID = self.storeKitProduct?.id ?? RevenueCatConfig.productIDMonthly
        guard let verificationResult = await Transaction.latest(for: currentTargetID) ?? await Transaction.latest(for: RevenueCatConfig.productID) else {
            print("⚠️ [StoreKit 2] No transaction found for products: \(currentTargetID) / \(RevenueCatConfig.productID)")
            self.storeKitStatusClear()
            isLoading = false
            buildUnifiedDebugJSON()
            return
        }

        // Lấy raw StoreKit 2 signed transaction JWS từ VerificationResult
        // Lưu ý: StoreKit 2 cung cấp thuộc tính `jwsRepresentation` trên VerificationResult
        self.signedTransactionJWS = verificationResult.jwsRepresentation
        print("🔐 [StoreKit 2] Retrieved signed transaction JWS (bytes: \(verificationResult.jwsRepresentation.count))")

        // Xác thực Transaction theo chuẩn Apple StoreKit 2
        switch verificationResult {
        case .verified(let transaction):
            self.storeKitIsVerified = true
            self.storeKitVerificationMessage = "Verified by Apple"
            self.storeKitTransactionID = String(transaction.id)
            self.storeKitOriginalTransactionID = String(transaction.originalID)
            self.storeKitProductID = transaction.productID
            self.storeKitProductType = String(describing: transaction.productType)
            self.storeKitPurchaseDate = isoFormatter.string(from: transaction.purchaseDate)
            self.storeKitOriginalPurchaseDate = isoFormatter.string(from: transaction.originalPurchaseDate)

            if let exp = transaction.expirationDate {
                self.storeKitExpirationDate = isoFormatter.string(from: exp)
            } else {
                self.storeKitExpirationDate = "nil"
            }

            if let rev = transaction.revocationDate {
                self.storeKitRevocationDate = isoFormatter.string(from: rev)
            } else {
                self.storeKitRevocationDate = "nil"
            }

            if let reason = transaction.revocationReason {
                self.storeKitRevocationReason = String(describing: reason)
            } else {
                self.storeKitRevocationReason = "nil"
            }

            self.storeKitIsUpgraded = transaction.isUpgraded ? "true" : "false"
            self.storeKitOwnershipType = String(describing: transaction.ownershipType)

            if let token = transaction.appAccountToken {
                self.storeKitAppAccountToken = token.uuidString
            } else {
                self.storeKitAppAccountToken = "nil"
            }

            // Environment: sandbox / production / xcode
            if #available(iOS 16.0, *) {
                switch transaction.environment {
                case .sandbox:
                    self.storeKitEnvironment = "sandbox"
                case .production:
                    self.storeKitEnvironment = "production"
                case .xcode:
                    self.storeKitEnvironment = "xcode"
                default:
                    self.storeKitEnvironment = String(describing: transaction.environment)
                }
            } else {
                self.storeKitEnvironment = "sandbox"
            }

            print("✅ [StoreKit 2] Verified Transaction ID: \(transaction.id), originalID: \(transaction.originalID)")

        case .unverified(let transaction, let error):
            self.storeKitIsVerified = false
            self.storeKitVerificationMessage = "UNVERIFIED: \(error.localizedDescription)"
            self.storeKitTransactionID = String(transaction.id)
            self.storeKitOriginalTransactionID = String(transaction.originalID)
            self.storeKitProductID = transaction.productID
            self.storeKitPurchaseDate = isoFormatter.string(from: transaction.purchaseDate)
            print("⚠️ [StoreKit 2] Transaction FAILED verification: \(error.localizedDescription)")
            self.errorMessage = "StoreKit 2 verification failed: \(error.localizedDescription)"
        }

        buildUnifiedDebugJSON()
        isLoading = false
    }

    // MARK: - 6. Load Current Entitlements via StoreKit 2
    func loadCurrentEntitlements() async {
        isLoading = true
        statusMessage = "Iterating StoreKit 2 currentEntitlements..."
        print("🔍 [StoreKit 2] Inspecting Transaction.currentEntitlements...")

        var found = false
        for await result in Transaction.currentEntitlements {
            switch result {
            case .verified(let transaction):
                print("   🏷️ Active entitlement: \(transaction.productID), ID: \(transaction.id)")
                if transaction.productID == RevenueCatConfig.productID {
                    found = true
                    self.signedTransactionJWS = result.jwsRepresentation
                    self.storeKitTransactionID = String(transaction.id)
                    self.storeKitOriginalTransactionID = String(transaction.originalID)
                    self.storeKitIsVerified = true
                }
            case .unverified(let transaction, let err):
                print("   ⚠️ Unverified active entitlement: \(transaction.productID) - \(err.localizedDescription)")
            }
        }

        if !found {
            print("ℹ️ [StoreKit 2] Target product not found in currentEntitlements.")
        }

        buildUnifiedDebugJSON()
        isLoading = false
    }

    // MARK: - Helper: Handle CustomerInfo
    private func handleCustomerInfo(_ info: CustomerInfo) {
        self.rcOriginalAppUserId = info.originalAppUserId
        self.rcActiveSubscriptions = Array(info.activeSubscriptions)
        self.rcAllPurchasedProducts = Array(info.allPurchasedProductIdentifiers)

        if let entitlement = info.entitlements[RevenueCatConfig.entitlementID] {
            self.isGoldActive = entitlement.isActive
            self.rcProductIdentifier = entitlement.productIdentifier
            self.rcPeriodType = String(describing: entitlement.periodType)
            self.rcOwnershipType = String(describing: entitlement.ownershipType)
            self.rcStore = String(describing: entitlement.store)

            if let latest = entitlement.latestPurchaseDate {
                self.rcLatestPurchaseDate = isoFormatter.string(from: latest)
            }
            if let exp = entitlement.expirationDate {
                self.rcExpirationDate = isoFormatter.string(from: exp)
            }
        } else {
            self.isGoldActive = false
        }

        print("👤 [RevenueCat] User: \(info.originalAppUserId) | Gold active: \(self.isGoldActive)")
    }

    private func storeKitStatusClear() {
        self.storeKitIsVerified = false
        self.storeKitVerificationMessage = "No active transaction found in Sandbox"
        self.storeKitTransactionID = "-"
        self.storeKitOriginalTransactionID = "-"
        self.storeKitProductID = "-"
        self.signedTransactionJWS = ""
    }

    // MARK: - Helper: Build Unified Debug JSON (Requirement 8)
    func buildUnifiedDebugJSON() {
        let debugDict: [String: Any] = [
            "app_user_id": self.appUserID,
            "bundle_id": RevenueCatConfig.bundleID,
            "product_id": RevenueCatConfig.productID,
            "package_id": RevenueCatConfig.packageID,
            "environment": self.storeKitEnvironment,
            "storekit_transaction": [
                "id": self.storeKitTransactionID,
                "original_id": self.storeKitOriginalTransactionID,
                "product_id": self.storeKitProductID,
                "purchase_date": self.storeKitPurchaseDate,
                "expiration_date": self.storeKitExpirationDate,
                "ownership_type": self.storeKitOwnershipType,
                "verified": self.storeKitIsVerified
            ],
            "signed_transaction_jws": self.signedTransactionJWS.isEmpty ? "None" : self.signedTransactionJWS,
            "fetch_token_candidate": self.signedTransactionJWS.isEmpty ? "None" : self.signedTransactionJWS,
            "revenuecat": [
                "entitlement": RevenueCatConfig.entitlementID,
                "is_active": self.isGoldActive,
                "original_app_user_id": self.rcOriginalAppUserId,
                "latest_purchase_date": self.rcLatestPurchaseDate
            ]
        ]

        if let data = try? JSONSerialization.data(withJSONObject: debugDict, options: [.prettyPrinted, .sortedKeys]),
           let str = String(data: data, encoding: .utf8) {
            self.unifiedDebugJSON = str
        }
    }

    // MARK: - Clipboard Helpers
    func copyDebugJSON() {
        UIPasteboard.general.string = self.unifiedDebugJSON
        showNotice("Debug JSON copied!")
    }

    func copySignedJWS() {
        if !signedTransactionJWS.isEmpty {
            UIPasteboard.general.string = self.signedTransactionJWS
            showNotice("Signed JWS copied!")
        }
    }

    private func showNotice(_ text: String) {
        copiedNotice = text
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            copiedNotice = nil
        }
    }
}

// MARK: - UI Content View
struct ContentView: View {
    @ObservedObject var viewModel: SandboxPurchaseViewModel

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    
                    // Header trạng thái Gold
                    entitlementHeader

                    // Các nút thao tác
                    actionButtonsSection

                    // Thông báo phản hồi & lỗi
                    feedbackBanner

                    // Section 1: CONFIG
                    configSection

                    // Section 2: REVENUECAT
                    revenueCatSection

                    // Section 3: STOREKIT TRANSACTION
                    storeKitSection

                    // Section 4: SIGNED TRANSACTION (JWS)
                    signedJWSSection

                    // Section 5: RAW DEBUG JSON
                    rawJSONSection

                    Spacer(minLength: 40)
                }
                .padding()
            }
            .navigationTitle("StoreKit 2 + RevenueCat")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await viewModel.initialLoad()
            }
        }
    }

    // MARK: - Subviews

    private var entitlementHeader: some View {
        HStack {
            Image(systemName: viewModel.isGoldActive ? "crown.fill" : "lock.fill")
                .font(.title2)
            Text(viewModel.isGoldActive ? "Locket Gold: ACTIVE" : "Locket Gold: INACTIVE")
                .font(.headline)
                .fontWeight(.bold)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .foregroundColor(viewModel.isGoldActive ? .green : .red)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(viewModel.isGoldActive ? Color.green.opacity(0.12) : Color.red.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(viewModel.isGoldActive ? Color.green.opacity(0.4) : Color.red.opacity(0.4), lineWidth: 1.5)
        )
    }

    private var actionButtonsSection: some View {
        VStack(spacing: 8) {
            // Main Purchase Button (RevenueCat)
            Button(action: {
                Task {
                    await viewModel.purchaseWithRevenueCat()
                }
            }) {
                HStack {
                    Image(systemName: "cart.fill")
                    Text("Purchase with RevenueCat (\(RevenueCatConfig.packageID))")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(viewModel.rcPackage == nil || viewModel.isLoading ? Color.gray : Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .disabled(viewModel.rcPackage == nil || viewModel.isLoading)

            // Direct StoreKit 2 Purchase Button (No Apple ID / Sandbox account needed when using .storekit)
            Button(action: {
                Task {
                    await viewModel.purchaseDirectWithStoreKit2()
                }
            }) {
                HStack {
                    Image(systemName: "applelogo")
                    Text("Direct StoreKit 2 Purchase (Không cần Account Sandbox)")
                        .font(.footnote)
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(viewModel.storeKitProduct == nil || viewModel.isLoading ? Color.gray.opacity(0.5) : Color.green)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .disabled(viewModel.storeKitProduct == nil || viewModel.isLoading)

            // 2x2 Action Buttons Grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                gridButton(title: "Fetch StoreKit Product", icon: "cart.badge.plus") {
                    await viewModel.fetchStoreKitProduct()
                }
                gridButton(title: "Fetch RC Offering", icon: "arrow.triangle.2.circlepath") {
                    await viewModel.fetchRevenueCatOfferings()
                }
                gridButton(title: "Refresh CustomerInfo", icon: "person.badge.shield.checkmark") {
                    await viewModel.refreshCustomerInfo()
                }
                gridButton(title: "Load Latest StoreKit Tx", icon: "clock.arrow.circlepath") {
                    await viewModel.loadLatestStoreKitTransaction()
                }
                gridButton(title: "Load Current Entitlements", icon: "list.bullet.rectangle") {
                    await viewModel.loadCurrentEntitlements()
                }
                gridButton(title: "Copy Debug JSON", icon: "doc.on.doc") {
                    viewModel.copyDebugJSON()
                }
            }
        }
    }

    private func gridButton(title: String, icon: String, action: @escaping () async -> Void) -> some View {
        Button(action: {
            Task {
                await action()
            }
        }) {
            Label(title, systemImage: icon)
                .font(.caption2)
                .fontWeight(.medium)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
        }
        .disabled(viewModel.isLoading)
    }

    private var feedbackBanner: some View {
        VStack(spacing: 4) {
            if viewModel.isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(viewModel.statusMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else if !viewModel.statusMessage.isEmpty {
                Text(viewModel.statusMessage)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if let copied = viewModel.copiedNotice {
                Text(copied)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.green)
            }

            if let err = viewModel.errorMessage {
                Text(err)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.red.opacity(0.1)))
            }
        }
    }

    // 1. CONFIG SECTION
    private var configSection: some View {
        cardContainer(title: "CONFIG") {
            itemRow(title: "Bundle ID", value: RevenueCatConfig.bundleID)
            itemRow(title: "App User ID", value: viewModel.appUserID)
            itemRow(title: "Product ID", value: viewModel.targetProductID)
            itemRow(title: "StoreKit Title", value: viewModel.storeKitDisplayName)
            itemRow(title: "StoreKit Price", value: viewModel.storeKitDisplayPrice)
            itemRow(title: "RevenueCat Offering", value: viewModel.targetOfferingID)
            itemRow(title: "Package", value: viewModel.targetPackageID)
            itemRow(title: "Entitlement", value: viewModel.targetEntitlementID)
        }
    }

    // 2. REVENUECAT SECTION
    private var revenueCatSection: some View {
        cardContainer(title: "REVENUECAT") {
            itemRow(title: "Entitlement Status", value: viewModel.isGoldActive ? "ACTIVE" : "INACTIVE")
            itemRow(title: "Original App User ID", value: viewModel.rcOriginalAppUserId)
            itemRow(title: "Active Subscriptions", value: viewModel.rcActiveSubscriptions.isEmpty ? "None" : viewModel.rcActiveSubscriptions.joined(separator: ", "))
            itemRow(title: "All Purchased Products", value: viewModel.rcAllPurchasedProducts.isEmpty ? "None" : viewModel.rcAllPurchasedProducts.joined(separator: ", "))
            itemRow(title: "Product Identifier", value: viewModel.rcProductIdentifier)
            itemRow(title: "Period Type", value: viewModel.rcPeriodType)
            itemRow(title: "Ownership Type", value: viewModel.rcOwnershipType)
            itemRow(title: "Store Expose", value: viewModel.rcStore)
            itemRow(title: "Latest Purchase Date", value: viewModel.rcLatestPurchaseDate)
            itemRow(title: "Expiration Date", value: viewModel.rcExpirationDate)
        }
    }

    // 3. STOREKIT TRANSACTION SECTION
    private var storeKitSection: some View {
        cardContainer(title: "STOREKIT TRANSACTION (Apple StoreKit 2)") {
            itemRow(title: "Verified Status", value: viewModel.storeKitVerificationMessage, highlight: viewModel.storeKitIsVerified)
            itemRow(title: "Transaction ID", value: viewModel.storeKitTransactionID)
            itemRow(title: "Original Transaction ID", value: viewModel.storeKitOriginalTransactionID)
            itemRow(title: "Product ID", value: viewModel.storeKitProductID)
            itemRow(title: "Product Type", value: viewModel.storeKitProductType)
            itemRow(title: "Purchase Date", value: viewModel.storeKitPurchaseDate)
            itemRow(title: "Original Purchase Date", value: viewModel.storeKitOriginalPurchaseDate)
            itemRow(title: "Expiration Date", value: viewModel.storeKitExpirationDate)
            itemRow(title: "Revocation Date", value: viewModel.storeKitRevocationDate)
            itemRow(title: "Revocation Reason", value: viewModel.storeKitRevocationReason)
            itemRow(title: "Is Upgraded", value: viewModel.storeKitIsUpgraded)
            itemRow(title: "Ownership Type", value: viewModel.storeKitOwnershipType)
            itemRow(title: "Environment", value: viewModel.storeKitEnvironment)
            itemRow(title: "App Account Token", value: viewModel.storeKitAppAccountToken)
        }
    }

    // 4. SIGNED TRANSACTION SECTION
    private var signedJWSSection: some View {
        cardContainer(title: "SIGNED TRANSACTION JWS") {
            Text(viewModel.jwsExplanation)
                .font(.caption2)
                .foregroundColor(.secondary)

            if !viewModel.signedTransactionJWS.isEmpty {
                Button(action: { viewModel.copySignedJWS() }) {
                    Label("Copy Signed Transaction JWS", systemImage: "doc.on.doc.fill")
                        .font(.caption)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        .background(Color.blue.opacity(0.15))
                        .foregroundColor(.blue)
                        .cornerRadius(6)
                }

                ScrollView(.horizontal, showsIndicators: true) {
                    Text(viewModel.signedTransactionJWS)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.primary)
                        .padding(8)
                        .background(Color(UIColor.tertiarySystemBackground))
                        .cornerRadius(6)
                        .textSelection(.enabled)
                }
            } else {
                Text("Chưa có StoreKit 2 transaction nào được tải.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    // 5. RAW DEBUG JSON SECTION
    private var rawJSONSection: some View {
        cardContainer(title: "RAW DEBUG JSON") {
            HStack {
                Spacer()
                Button(action: { viewModel.copyDebugJSON() }) {
                    Label("Copy Debug JSON", systemImage: "doc.on.doc")
                        .font(.caption)
                }
            }

            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                Text(viewModel.unifiedDebugJSON.isEmpty ? "No debug JSON ready." : viewModel.unifiedDebugJSON)
                    .font(.system(.caption2, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color(UIColor.tertiarySystemBackground))
                    .cornerRadius(6)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 250)
        }
    }

    // MARK: - Reusable UI Helpers
    private func cardContainer<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.secondary)

            Divider()

            content()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(UIColor.secondarySystemBackground))
        )
    }

    private func itemRow(title: String, value: String, highlight: Bool = false) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
                .frame(width: 140, alignment: .leading)
            Spacer()
            Text(value)
                .font(.caption2)
                .fontWeight(highlight ? .bold : .medium)
                .foregroundColor(highlight ? .green : .primary)
                .multilineTextAlignment(.trailing)
        }
    }
}
