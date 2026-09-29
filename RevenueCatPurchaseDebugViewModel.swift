import Foundation
import StoreKit
import RevenueCat
import SwiftUI

// MARK: - Configuration
enum AppPurchaseConfig {
    static let apiKey = "test_AvyjuRHzlxvgfTgTsPNNTeTNaEG"
    static let appUserID = "kqdepzai"
    static let targetOfferingID = "default"
    static let targetPackageID = "$rc_annual"
    static let expectedProductID = "locket_1600_1y"
    static let targetEntitlementID = "gold"
}

// MARK: - View Model
@MainActor
final class RevenueCatPurchaseDebugViewModel: ObservableObject {
    // 1. Config Info
    @Published var appUserID: String = AppPurchaseConfig.appUserID
    @Published var revenueCatPublicKey: String = AppPurchaseConfig.apiKey
    @Published var offeringID: String = AppPurchaseConfig.targetOfferingID
    @Published var packageID: String = AppPurchaseConfig.targetPackageID
    @Published var productID: String = AppPurchaseConfig.expectedProductID
    @Published var entitlementID: String = AppPurchaseConfig.targetEntitlementID

    // 2. Package & Offering State
    @Published var loadedPackage: Package? = nil
    @Published var packageVerified: Bool = false
    @Published var packageVerificationMessage: String = "Chưa kiểm tra package."

    // 3. StoreKit 2 Verified Transaction State
    @Published var storeKitVerified: Bool = false
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
    @Published var storeKitEnvironment: String = "-"
    @Published var storeKitAppAccountToken: String = "nil"

    // 4. Signed JWS Tokens
    @Published var signedTransactionJWS: String = ""
    @Published var showFullJWS: Bool = false
    @Published var appTransactionJWS: String = ""
    @Published var appTxBundleID: String = "-"
    @Published var appTxAppVersion: String = "-"
    @Published var appTxOriginalAppVersion: String = "-"
    @Published var appTxOriginalPurchaseDate: String = "-"
    @Published var appTxEnvironment: String = "-"
    @Published var appTxIsVerified: Bool = false

    // 5. Master Fetch Token & Candidates
    @Published var masterFetchToken: String = "UNAVAILABLE"
    @Published var masterFetchTokenSource: String = "No public RevenueCat/StoreKit field matched"
    @Published var rcStoreTransactionID: String = "nil"
    @Published var serverExpirationDate: String = "-"
    @Published var masterTokenCandidates: [String: String] = [:]

    // 6. Fetch Token Status
    @Published var fetchToken: String? = nil
    @Published var fetchTokenStatus: String = "NOT EXPOSED BY REVENUECAT PUBLIC SDK"

    // 7. RevenueCat CustomerInfo State
    @Published var rcOriginalAppUserId: String = "-"
    @Published var rcActiveSubscriptions: [String] = []
    @Published var rcAllPurchasedProducts: [String] = []
    @Published var rcManagementURL: String = "nil"
    @Published var rcRequestDate: String = "-"
    @Published var isGoldActive: Bool = false
    @Published var rcEntitlementsSummary: [String: Any] = [:]

    // 8. Output JSON & UI Status
    @Published var fullDebugJSON: String = ""
    @Published var isLoading: Bool = false
    @Published var statusMessage: String = "Sẵn sàng"
    @Published var errorMessage: String? = nil
    @Published var clipboardNotice: String? = nil

    private let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    // MARK: - Setup & Initial Load
    func setupAndInitialLoad() async {
        // 1. Cấu hình log mức Debug
        Purchases.logLevel = .debug

        // 2. Configure Purchases SDK
        Purchases.configure(
            withAPIKey: AppPurchaseConfig.apiKey,
            appUserID: AppPurchaseConfig.appUserID
        )
        print("🚀 [RevenueCat] Configured with API Key: \(AppPurchaseConfig.apiKey), User: \(AppPurchaseConfig.appUserID)")

        // 3. Tải Offering & Package
        await fetchTargetOffering()

        // 4. Tải CustomerInfo ban đầu
        await refreshCustomerInfo()

        // 5. Kiểm tra StoreKit transactions sẵn có
        await fetchLatestStoreKitTransaction()
        await inspectCurrentEntitlements()
        await fetchAppTransaction()

        buildFinalDebugJSON()
    }

    // MARK: - 1. Fetch Target Offering & Verify Package
    func fetchTargetOffering() async {
        isLoading = true
        errorMessage = nil
        statusMessage = "Đang tải offering '\(AppPurchaseConfig.targetOfferingID)'..."

        do {
            let offerings = try await Purchases.shared.offerings()
            
            // Tìm offering: ưu tiên current, targetOfferingID, hoặc default
            guard let targetOffering = offerings.current ?? offerings.all[AppPurchaseConfig.targetOfferingID] ?? offerings.all["default"] else {
                let avail = offerings.all.keys.joined(separator: ", ")
                let msg = "Không tìm thấy offering '\(AppPurchaseConfig.targetOfferingID)'. Offerings hiện có: [\(avail)]"
                print("❌ [RevenueCat] \(msg)")
                self.errorMessage = msg
                self.packageVerified = false
                self.packageVerificationMessage = msg
                isLoading = false
                return
            }

            self.offeringID = targetOffering.identifier
            print("📦 [RevenueCat] Đã tìm thấy offering: \(targetOffering.identifier)")

            // Tìm package $rc_annual
            guard let package = targetOffering.package(identifier: AppPurchaseConfig.targetPackageID) else {
                let availPkg = targetOffering.availablePackages.map { $0.identifier }.joined(separator: ", ")
                let msg = "Không tìm thấy package '\(AppPurchaseConfig.targetPackageID)'. Packages hiện có: [\(availPkg)]"
                print("❌ [RevenueCat] \(msg)")
                self.errorMessage = msg
                self.packageVerified = false
                self.packageVerificationMessage = msg
                isLoading = false
                return
            }

            // Kiểm tra product identifier
            let actualProductID = package.storeProduct.productIdentifier
            guard actualProductID == AppPurchaseConfig.expectedProductID else {
                let msg = "LỖI PRODUCT MISMATCH: Package '\(package.identifier)' trỏ đến product '\(actualProductID)', không phải '\(AppPurchaseConfig.expectedProductID)'!"
                print("⛔ [RevenueCat] \(msg)")
                self.errorMessage = msg
                self.packageVerified = false
                self.packageVerificationMessage = msg
                self.loadedPackage = nil
                isLoading = false
                return
            }

            self.loadedPackage = package
            self.packageID = package.identifier
            self.productID = actualProductID
            self.packageVerified = true
            self.packageVerificationMessage = "Xác thực hợp lệ: Package '\(package.identifier)' trỏ đúng product '\(actualProductID)' (\(package.storeProduct.localizedPriceString))"
            statusMessage = "Đã tải package: \(package.identifier)"
            print("✅ [RevenueCat] \(packageVerificationMessage)")

        } catch {
            let msg = "Lỗi khi lấy offerings: \(error.localizedDescription)"
            print("❌ [RevenueCat] \(msg)")
            self.errorMessage = msg
            self.packageVerified = false
            self.packageVerificationMessage = msg
        }

        isLoading = false
    }

    // MARK: - 2. Purchase Package via RevenueCat
    func purchaseAnnualPackage() async {
        guard let package = loadedPackage, packageVerified else {
            errorMessage = "Chưa thể mua: Package chưa được xác thực hoặc không khớp product ID."
            return
        }

        isLoading = true
        errorMessage = nil
        statusMessage = "Đang thực hiện thanh toán qua RevenueCat / StoreKit..."
        print("🛒 [Purchase] Bắt đầu thanh toán package: \(package.identifier), product: \(package.storeProduct.productIdentifier)")

        do {
            let result = try await Purchases.shared.purchase(package: package)

            // Kiểm tra user cancel
            if result.userCancelled {
                print("ℹ️ [Purchase] Người dùng đã huỷ thanh toán (User Cancelled).")
                statusMessage = "Thanh toán đã bị huỷ bởi người dùng."
                isLoading = false
                return
            }

            print("✅ [Purchase] Giao dịch thành công! Đang tự động làm mới toàn bộ dữ liệu...")
            statusMessage = "Giao dịch thành công!"

            // 1. Cập nhật CustomerInfo từ purchase result
            handleCustomerInfo(result.customerInfo)

            // 2. Lấy StoreKit 2 Transaction mới nhất
            await fetchLatestStoreKitTransaction()

            // 3. Kiểm tra Current Entitlements
            await inspectCurrentEntitlements()

            // 4. Lấy AppTransaction
            await fetchAppTransaction()

            // 5. Tạo JSON output hoàn chỉnh
            buildFinalDebugJSON()

            statusMessage = "Đã đồng bộ toàn bộ dữ liệu sau thanh toán!"
        } catch {
            if let rcError = error as? RevenueCat.ErrorCode, rcError == .purchaseCancelledError {
                print("ℹ️ [Purchase] Người dùng đã huỷ giao dịch (purchaseCancelledError).")
                statusMessage = "Thanh toán đã bị huỷ bởi người dùng."
            } else if (error as NSError).code == RevenueCat.ErrorCode.purchaseCancelledError.rawValue {
                print("ℹ️ [Purchase] Người dùng đã huỷ giao dịch.")
                statusMessage = "Thanh toán đã bị huỷ bởi người dùng."
            } else {
                print("❌ [Purchase] Lỗi khi mua: \(error.localizedDescription)")
                self.errorMessage = "Lỗi purchase: \(error.localizedDescription)"
                statusMessage = "Thanh toán thất bại."
            }
        }

        isLoading = false
    }

    // MARK: - 3. Fetch Latest StoreKit 2 Transaction & JWS
    func fetchLatestStoreKitTransaction() async {
        statusMessage = "Đang kiểm tra StoreKit 2 Transaction.latest(for: \(AppPurchaseConfig.expectedProductID))..."

        guard let latestResult = await Transaction.latest(for: AppPurchaseConfig.expectedProductID) else {
            print("⚠️ [StoreKit 2] Không tìm thấy transaction nào cho product '\(AppPurchaseConfig.expectedProductID)'")
            self.storeKitVerified = false
            self.signedTransactionJWS = ""
            return
        }

        // Lấy JWS representation từ VerificationResult gốc
        self.signedTransactionJWS = latestResult.jwsRepresentation
        print("🔐 [StoreKit 2 JWS] Đã lấy signed transaction JWS (độ dài: \(latestResult.jwsRepresentation.count) ký tự)")

        // Phân biệt verified và unverified
        switch latestResult {
        case .verified(let transaction):
            self.storeKitVerified = true
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
                    self.storeKitEnvironment = "Sandbox"
                case .production:
                    self.storeKitEnvironment = "Production"
                case .xcode:
                    self.storeKitEnvironment = "Xcode"
                default:
                    self.storeKitEnvironment = String(describing: transaction.environment)
                }
            } else {
                self.storeKitEnvironment = "Sandbox"
            }

            print("✅ [StoreKit 2] Đã verify transaction: ID \(transaction.id), Original ID: \(transaction.originalID)")

        case .unverified(let transaction, let error):
            self.storeKitVerified = false
            self.storeKitTransactionID = String(transaction.id)
            self.storeKitOriginalTransactionID = String(transaction.originalID)
            self.storeKitProductID = transaction.productID
            self.storeKitPurchaseDate = isoFormatter.string(from: transaction.purchaseDate)
            print("⚠️ [StoreKit 2] Transaction UNVERIFIED: \(error.localizedDescription)")
            self.errorMessage = "StoreKit 2 unverified: \(error.localizedDescription)"
        }

        evaluateMasterFetchToken()
    }

    // MARK: - 4. Inspect Transaction.currentEntitlements
    func inspectCurrentEntitlements() async {
        print("🔍 [StoreKit 2] Đang duyệt Transaction.currentEntitlements...")
        var found = false

        for await result in Transaction.currentEntitlements {
            switch result {
            case .verified(let transaction):
                print("   [Entitlement] Product: \(transaction.productID), ID: \(transaction.id)")
                if transaction.productID == AppPurchaseConfig.expectedProductID {
                    found = true
                    if self.signedTransactionJWS.isEmpty {
                        self.signedTransactionJWS = result.jwsRepresentation
                    }
                    self.storeKitTransactionID = String(transaction.id)
                    self.storeKitOriginalTransactionID = String(transaction.originalID)
                    self.storeKitVerified = true
                }
            case .unverified(let transaction, let error):
                print("   [Entitlement Unverified] Product: \(transaction.productID) - \(error.localizedDescription)")
            }
        }

        if !found {
            print("ℹ️ [StoreKit 2] Không tìm thấy \(AppPurchaseConfig.expectedProductID) trong currentEntitlements.")
        }
    }

    // MARK: - 5. AppTransaction Inspection (iOS 16+)
    func fetchAppTransaction() async {
        if #available(iOS 16.0, *) {
            do {
                let verificationResult = try await AppTransaction.shared
                self.appTransactionJWS = verificationResult.jwsRepresentation

                switch verificationResult {
                case .verified(let appTx):
                    self.appTxIsVerified = true
                    self.appTxBundleID = appTx.bundleID
                    self.appTxAppVersion = appTx.appVersion
                    self.appTxOriginalAppVersion = appTx.originalAppVersion
                    self.appTxOriginalPurchaseDate = isoFormatter.string(from: appTx.originalPurchaseDate)
                    switch appTx.environment {
                    case .sandbox:
                        self.appTxEnvironment = "Sandbox"
                    case .production:
                        self.appTxEnvironment = "Production"
                    case .xcode:
                        self.appTxEnvironment = "Xcode"
                    default:
                        self.appTxEnvironment = String(describing: appTx.environment)
                    }
                    print("✅ [AppTransaction] Verified AppTransaction: Bundle \(appTx.bundleID), Version \(appTx.appVersion)")
                case .unverified(let appTx, let error):
                    self.appTxIsVerified = false
                    self.appTxBundleID = appTx.bundleID
                    print("⚠️ [AppTransaction] Unverified: \(error.localizedDescription)")
                }
            } catch {
                print("ℹ️ [AppTransaction] Không thể lấy AppTransaction (yêu cầu App Store sign-in hoặc simulator build): \(error.localizedDescription)")
            }
        }
    }

    // MARK: - 6. Refresh CustomerInfo
    func refreshCustomerInfo() async {
        isLoading = true
        errorMessage = nil
        statusMessage = "Đang làm mới CustomerInfo..."

        do {
            let info = try await Purchases.shared.customerInfo()
            handleCustomerInfo(info)
            statusMessage = "Đã cập nhật CustomerInfo."
        } catch {
            print("❌ [RevenueCat] Lỗi refresh CustomerInfo: \(error.localizedDescription)")
            self.errorMessage = "Lỗi CustomerInfo: \(error.localizedDescription)"
        }

        isLoading = false
    }

    // MARK: - 7. Restore Purchases
    func restorePurchases() async {
        isLoading = true
        errorMessage = nil
        statusMessage = "Đang khôi phục giao dịch (Restore)..."

        do {
            let info = try await Purchases.shared.restorePurchases()
            handleCustomerInfo(info)
            await fetchLatestStoreKitTransaction()
            buildFinalDebugJSON()
            statusMessage = "Khôi phục giao dịch thành công."
        } catch {
            print("❌ [RevenueCat] Lỗi restore: \(error.localizedDescription)")
            self.errorMessage = "Lỗi restore: \(error.localizedDescription)"
        }

        isLoading = false
    }

    // MARK: - Helper: Handle CustomerInfo Data
    private func handleCustomerInfo(_ info: CustomerInfo) {
        self.rcOriginalAppUserId = info.originalAppUserId
        self.rcActiveSubscriptions = Array(info.activeSubscriptions)
        self.rcAllPurchasedProducts = Array(info.allPurchasedProductIdentifiers)
        self.rcManagementURL = info.managementURL?.absoluteString ?? "nil"
        self.rcRequestDate = isoFormatter.string(from: info.requestDate)

        // Kiểm tra entitlement gold
        if let gold = info.entitlements[AppPurchaseConfig.targetEntitlementID] {
            self.isGoldActive = gold.isActive
        } else {
            self.isGoldActive = false
        }

        // Tạo dictionary chi tiết cho từng entitlement
        var entDict: [String: Any] = [:]
        for (key, ent) in info.entitlements.all {
            entDict[key] = [
                "identifier": ent.identifier,
                "isActive": ent.isActive,
                "productIdentifier": ent.productIdentifier,
                "purchaseDate": isoFormatter.string(from: ent.latestPurchaseDate ?? ent.originalPurchaseDate ?? Date()),
                "latestPurchaseDate": ent.latestPurchaseDate != nil ? isoFormatter.string(from: ent.latestPurchaseDate!) : "nil",
                "expirationDate": ent.expirationDate != nil ? isoFormatter.string(from: ent.expirationDate!) : "nil",
                "willRenew": ent.willRenew,
                "periodType": String(describing: ent.periodType),
                "ownershipType": String(describing: ent.ownershipType),
                "store": String(describing: ent.store),
                "isSandbox": ent.isSandbox,
                "unsubscribeDetectedAt": ent.unsubscribeDetectedAt != nil ? isoFormatter.string(from: ent.unsubscribeDetectedAt!) : "nil",
                "billingIssueDetectedAt": ent.billingIssueDetectedAt != nil ? isoFormatter.string(from: ent.billingIssueDetectedAt!) : "nil"
            ]
        }
        self.rcEntitlementsSummary = entDict

        // Trích xuất store_transaction_id từ CustomerInfo rawData nếu có
        if let subDict = (info.rawData["subscriber"] as? [String: Any])?["subscriptions"] as? [String: Any] {
            if let targetSub = subDict[self.productID] as? [String: Any],
               let storeTx = targetSub["store_transaction_id"] as? String {
                self.rcStoreTransactionID = storeTx
            } else {
                for (_, val) in subDict {
                    if let sDict = val as? [String: Any], let storeTx = sDict["store_transaction_id"] as? String {
                        self.rcStoreTransactionID = storeTx
                        break
                    }
                }
            }
        }

        // Cập nhật server expiration date
        if let gold = info.entitlements[AppPurchaseConfig.targetEntitlementID], let exp = gold.expirationDate {
            self.serverExpirationDate = isoFormatter.string(from: exp)
        } else if self.storeKitExpirationDate != "-" && self.storeKitExpirationDate != "nil" {
            self.serverExpirationDate = self.storeKitExpirationDate
        } else {
            self.serverExpirationDate = "nil"
        }

        // Lưu ý theo yêu cầu: fetch_token nội bộ KHÔNG expose qua public SDK
        self.fetchToken = nil
        self.fetchTokenStatus = "NOT EXPOSED BY REVENUECAT PUBLIC SDK"

        print("👤 [CustomerInfo] User: \(info.originalAppUserId) | Active Subs: \(info.activeSubscriptions) | Gold Active: \(self.isGoldActive)")
        
        // Đánh giá Master Fetch Token
        evaluateMasterFetchToken()
    }

    // MARK: - Helper: Evaluate Master Fetch Token & Candidates
    func evaluateMasterFetchToken() {
        print("🔍 [Master Fetch Token Audit] Bắt đầu kiểm tra và đánh giá Master Fetch Token...")

        var candidates: [String: String] = [:]
        let hasStoreKitTx = (storeKitTransactionID != "-" && !storeKitTransactionID.isEmpty && storeKitTransactionID != "nil")
        let hasStoreKitOrigTx = (storeKitOriginalTransactionID != "-" && !storeKitOriginalTransactionID.isEmpty && storeKitOriginalTransactionID != "nil")
        let hasRcStoreTx = (rcStoreTransactionID != "nil" && !rcStoreTransactionID.isEmpty && rcStoreTransactionID != "-")

        candidates["transaction.id"] = hasStoreKitTx ? storeKitTransactionID : "nil"
        candidates["originalTransactionID"] = hasStoreKitOrigTx ? storeKitOriginalTransactionID : "nil"
        candidates["RevenueCat store_transaction_id"] = hasRcStoreTx ? rcStoreTransactionID : "nil"
        candidates["appTransactionID"] = (appTxBundleID != "-" && !appTxBundleID.isEmpty) ? "Bundle: \(appTxBundleID)" : "nil"
        candidates["signed JWS"] = signedTransactionJWS.isEmpty ? "nil" : "\(signedTransactionJWS.prefix(32))... (\(signedTransactionJWS.count) chars)"
        candidates["fetch_token"] = "null (NOT EXPOSED BY REVENUECAT PUBLIC SDK)"

        // Đánh giá thứ tự ưu tiên (Requirement 12):
        // a. field thật có tên master_fetch_token / fetch_token từ API nếu có
        // b. RevenueCat store_transaction_id nếu hệ thống gốc trả về field này
        // c. StoreKit transaction.id nếu là số hợp lệ từ Apple transaction
        // d. StoreKit originalTransactionID nếu transaction.id không có
        // e. UNAVAILABLE nếu không tìm thấy field nào

        if hasRcStoreTx && CharacterSet.decimalDigits.isSuperset(of: CharacterSet(charactersIn: rcStoreTransactionID)) {
            self.masterFetchToken = rcStoreTransactionID
            self.masterFetchTokenSource = "RevenueCat store_transaction_id"
        } else if hasStoreKitTx && CharacterSet.decimalDigits.isSuperset(of: CharacterSet(charactersIn: storeKitTransactionID)) {
            self.masterFetchToken = storeKitTransactionID
            self.masterFetchTokenSource = "StoreKit transaction.id"
        } else if hasStoreKitOrigTx && CharacterSet.decimalDigits.isSuperset(of: CharacterSet(charactersIn: storeKitOriginalTransactionID)) {
            self.masterFetchToken = storeKitOriginalTransactionID
            self.masterFetchTokenSource = "StoreKit originalTransactionID"
        } else {
            self.masterFetchToken = "UNAVAILABLE"
            self.masterFetchTokenSource = "No public RevenueCat/StoreKit field matched"
        }

        candidates["selected master_fetch_token"] = self.masterFetchToken
        candidates["selected master_fetch_token_source"] = self.masterFetchTokenSource
        self.masterTokenCandidates = candidates

        print("📊 [Master Fetch Token] Selected: \(self.masterFetchToken)")
        print("📌 [Master Fetch Token Source]: \(self.masterFetchTokenSource)")
        print("📋 [Master Token Candidates]:")
        for (k, v) in candidates {
            print("   - \(k): \(v)")
        }
    }

    // MARK: - Helper: Build Final Unified Debug JSON
    func buildFinalDebugJSON() {
        evaluateMasterFetchToken()

        // Object chuẩn theo Yêu cầu 9
        let masterPurchaseObject: [String: Any] = [
            "master_fetch_token": self.masterFetchToken,
            "master_fetch_token_source": self.masterFetchTokenSource,
            "transaction_id": self.storeKitTransactionID,
            "original_transaction_id": self.storeKitOriginalTransactionID,
            "store_transaction_id": self.rcStoreTransactionID,
            "signed_transaction_jws": self.signedTransactionJWS.isEmpty ? "None" : self.signedTransactionJWS,
            "app_transaction_jws": self.appTransactionJWS.isEmpty ? "None" : self.appTransactionJWS,
            "revenuecat_public_key": self.revenueCatPublicKey,
            "expiration_date": self.serverExpirationDate
        ]

        let debugDict: [String: Any] = [
            "master_purchase_object": masterPurchaseObject,
            "app_user_id": self.appUserID,
            "revenuecat_public_key": self.revenueCatPublicKey,
            "offering": self.offeringID,
            "package": self.packageID,
            "product_id": self.productID,
            "master_fetch_token": self.masterFetchToken,
            "master_fetch_token_source": self.masterFetchTokenSource,
            "master_token_candidates": self.masterTokenCandidates,
            "server_expiration_date": self.serverExpirationDate,
            "storekit": [
                "verified": self.storeKitVerified,
                "transaction_id": self.storeKitTransactionID,
                "original_transaction_id": self.storeKitOriginalTransactionID,
                "product_id": self.storeKitProductID,
                "product_type": self.storeKitProductType,
                "purchase_date": self.storeKitPurchaseDate,
                "original_purchase_date": self.storeKitOriginalPurchaseDate,
                "expiration_date": self.storeKitExpirationDate,
                "revocation_date": self.storeKitRevocationDate,
                "revocation_reason": self.storeKitRevocationReason,
                "is_upgraded": self.storeKitIsUpgraded,
                "environment": self.storeKitEnvironment,
                "ownership_type": self.storeKitOwnershipType,
                "app_account_token": self.storeKitAppAccountToken
            ],
            "signed_transaction_jws": self.signedTransactionJWS.isEmpty ? "None (No StoreKit 2 transaction loaded yet)" : self.signedTransactionJWS,
            "app_transaction_jws": self.appTransactionJWS.isEmpty ? "None" : self.appTransactionJWS,
            "fetch_token": self.fetchToken as Any? ?? NSNull(),
            "fetch_token_status": self.fetchTokenStatus,
            "revenuecat": [
                "original_app_user_id": self.rcOriginalAppUserId,
                "store_transaction_id": self.rcStoreTransactionID,
                "active_subscriptions": self.rcActiveSubscriptions,
                "purchased_products": self.rcAllPurchasedProducts,
                "management_url": self.rcManagementURL,
                "request_date": self.rcRequestDate,
                "entitlements": self.rcEntitlementsSummary
            ]
        ]

        if let data = try? JSONSerialization.data(withJSONObject: debugDict, options: [.prettyPrinted, .sortedKeys]),
           let str = String(data: data, encoding: .utf8) {
            self.fullDebugJSON = str
        }
    }

    // MARK: - Clipboard Helpers
    func copyDebugJSON() {
        UIPasteboard.general.string = self.fullDebugJSON
        triggerNotice("Đã sao chép Debug JSON!")
    }

    func copySignedJWS() {
        guard !signedTransactionJWS.isEmpty else { return }
        UIPasteboard.general.string = self.signedTransactionJWS
        triggerNotice("Đã sao chép Signed JWS!")
    }

    private func triggerNotice(_ text: String) {
        clipboardNotice = text
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            clipboardNotice = nil
        }
    }
}
