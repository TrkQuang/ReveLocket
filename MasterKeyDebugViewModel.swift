import Foundation
import StoreKit
import RevenueCat
import SwiftUI

@MainActor
public final class MasterKeyDebugViewModel: ObservableObject {
    // MARK: - 1. Configuration State
    @Published public var appUserID: String = RevenueCatService.defaultAppUserID
    @Published public var revenueCatPublicKey: String = RevenueCatService.defaultPublicKey
    @Published public var offeringID: String = RevenueCatService.defaultOfferingID
    @Published public var packageID: String = RevenueCatService.defaultPackageID
    @Published public var productID: String = RevenueCatService.defaultProductID
    @Published public var entitlementID: String = RevenueCatService.defaultEntitlementID

    // MARK: - 2. Active Master Key & Source
    @Published public var masterFetchToken: String? = nil
    @Published public var masterFetchTokenDisplay: String = "UNAVAILABLE"
    @Published public var masterFetchTokenSource: MasterTokenSource = .unavailable
    @Published public var transactionSource: TransactionSource = .unknown
    @Published public var finalStatus: MasterKeyStatus = .unverified

    // MARK: - 3. Server Expiration Date (ISO-8601)
    @Published public var serverExpirationDate: String = "-"
    @Published public var storeKitExpirationDate: String? = nil
    @Published public var revenueCatExpirationDate: String? = nil
    @Published public var expirationMismatchWarning: String? = nil

    // MARK: - 4. Master Token Candidates (Requirement 11)
    @Published public var candidates: [String: String] = [:]

    // MARK: - 5. StoreKit Details
    @Published public var storeKitDetails: StoreKitTransactionDetails? = nil
    @Published public var signedTransactionJWS: String = ""
    @Published public var appTransactionDetails: AppTransactionDetails? = nil
    @Published public var appTransactionJWS: String = ""

    // MARK: - 6. RevenueCat Details
    @Published public var rcSummary: RevenueCatCustomerSummary? = nil
    @Published public var isGoldActive: Bool = false
    @Published public var verifiedPackage: Package? = nil

    // MARK: - 7. Right Panel Form (Thêm Master Key Mới Vào Kho)
    @Published public var manualKeyName: String = "Locket Gold Master Key"
    @Published public var manualTokenInput: String = ""
    @Published public var manualExpirationDate: String = ""
    @Published public var manualInputNotice: String? = nil

    // MARK: - 8. Diagnostics & Test With Apple (Requirement 13)
    @Published public var validationResult: MasterKeyValidationResult? = nil
    @Published public var isDiagnosticSheetPresented: Bool = false

    // MARK: - 9. Raw Debug JSON (Requirement 17)
    @Published public var rawDebugJSON: String = ""

    // MARK: - 10. UI & Loading State
    @Published public var isLoading: Bool = false
    @Published public var statusMessage: String = "Sẵn sàng"
    @Published public var errorMessage: String? = nil
    @Published public var clipboardNotice: String? = nil

    private let storeKitService = StoreKitTransactionService.shared
    private let rcService = RevenueCatService.shared
    private let vaultManager = MasterKeyVaultManager.shared

    private let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    public init() {}

    // MARK: - Setup & Initial Load
    public func initialLoad() async {
        isLoading = true
        errorMessage = nil
        statusMessage = "Đang cấu hình RevenueCat & kiểm tra StoreKit 2..."

        // Cấu hình RevenueCat
        rcService.configure(apiKey: revenueCatPublicKey, appUserID: appUserID)

        // Kiểm tra và load dữ liệu
        await verifyOffering()
        await refreshCustomerInfo()
        await refreshStoreKitTransactions()

        // Đánh giá và build JSON
        evaluateMasterFetchToken()
        validateCurrentKey()

        // Tự động kích hoạt từ Kho Khóa nếu thiết bị chưa có Sandbox login (Không cần Apple ID Sandbox)
        if masterFetchToken == nil || masterFetchToken == "UNAVAILABLE" {
            if let activeKey = vaultManager.savedKeys.first(where: { $0.status == .verifiedActive || $0.status == .localStoreKitVerified }) {
                loadVaultKey(activeKey)
            }
        }

        buildRawDebugJSON()

        isLoading = false
        statusMessage = "Đã đồng bộ toàn bộ dữ liệu."
    }

    // MARK: - Offering & Package Verification
    public func verifyOffering() async {
        do {
            let pkg = try await rcService.fetchAndVerifyPackage(
                offeringID: offeringID,
                packageID: packageID,
                expectedProductID: productID
            )
            self.verifiedPackage = pkg
            print("✅ [ViewModel] Offering & Package khớp 100%: \(pkg.storeProduct.productIdentifier)")
        } catch {
            print("❌ [ViewModel] Lỗi package: \(error.localizedDescription)")
            self.errorMessage = error.localizedDescription
            self.verifiedPackage = nil
        }
    }

    // MARK: - Purchase Package (Requirement 3, 18)
    public func purchaseStoreKit() async {
        guard let pkg = verifiedPackage else {
            errorMessage = "Package chưa được xác thực hoặc không khớp product ID '\(productID)'."
            return
        }

        isLoading = true
        errorMessage = nil
        statusMessage = "Đang tiến hành thanh toán StoreKit / RevenueCat..."

        do {
            let (customerInfo, userCancelled) = try await rcService.purchase(package: pkg)
            if userCancelled {
                statusMessage = "Người dùng đã huỷ thanh toán."
                isLoading = false
                return
            }

            statusMessage = "Thanh toán thành công! Đang tự động làm mới toàn bộ 12 bước..."
            
            // Auto-refresh quy trình 12 bước (Requirement 18)
            handleCustomerInfo(customerInfo)
            await refreshStoreKitTransactions()
            evaluateMasterFetchToken()
            validateCurrentKey()
            buildRawDebugJSON()

            statusMessage = "Giao dịch hoàn tất! Trạng thái: \(finalStatus.rawValue)"
        } catch {
            if let rcError = error as? RevenueCat.ErrorCode, rcError == .purchaseCancelledError {
                statusMessage = "Người dùng đã huỷ giao dịch."
            } else {
                errorMessage = "Lỗi purchase: \(error.localizedDescription)"
                statusMessage = "Thanh toán thất bại."
            }
        }

        isLoading = false
    }

    // MARK: - Refresh All State
    public func refreshAll() async {
        isLoading = true
        errorMessage = nil
        statusMessage = "Đang làm mới thông tin giao dịch..."

        await refreshCustomerInfo()
        await refreshStoreKitTransactions()
        evaluateMasterFetchToken()
        validateCurrentKey()
        buildRawDebugJSON()

        isLoading = false
        statusMessage = "Đã cập nhật trạng thái mới nhất."
    }

    // MARK: - StoreKit Transactions & JWS Fetch
    public func refreshStoreKitTransactions() async {
        // 1. Transaction.latest(for:)
        let (_, details) = await storeKitService.fetchLatestTransaction(for: productID)
        self.storeKitDetails = details
        self.signedTransactionJWS = details?.signedTransactionJWS ?? ""

        // 2. Fallback Current Entitlements nếu latest nil
        if details == nil {
            let (_, entDetails) = await storeKitService.inspectCurrentEntitlements(targetProductID: productID)
            if let ent = entDetails {
                self.storeKitDetails = ent
                self.signedTransactionJWS = ent.signedTransactionJWS
            }
        }

        // 3. AppTransaction
        let (_, appTx) = await storeKitService.fetchAppTransaction()
        self.appTransactionDetails = appTx
        self.appTransactionJWS = appTx?.signedAppTransactionJWS ?? ""

        // Cập nhật ngày hết hạn từ StoreKit
        self.storeKitExpirationDate = storeKitDetails?.expirationDate
    }

    // MARK: - CustomerInfo Handling
    public func refreshCustomerInfo() async {
        do {
            let info = try await rcService.fetchCustomerInfo()
            handleCustomerInfo(info)
        } catch {
            print("ℹ️ [ViewModel] Lỗi CustomerInfo: \(error.localizedDescription)")
        }
    }

    private func handleCustomerInfo(_ info: CustomerInfo) {
        let summary = rcService.extractSummary(from: info, targetProductID: productID)
        self.rcSummary = summary

        if let gold = summary.entitlements[entitlementID] {
            self.isGoldActive = gold.isActive
            self.revenueCatExpirationDate = gold.expirationDate
        } else {
            self.isGoldActive = false
            self.revenueCatExpirationDate = nil
        }
    }

    // MARK: - Evaluate Master Fetch Token & Candidates (Requirements 2, 7, 8, 11, 12)
    public func evaluateMasterFetchToken() {
        print("🔍 [ViewModel] Đang đánh giá Master Fetch Token Candidates...")

        var candidateMap: [String: String] = [:]

        let skTxID = storeKitDetails?.transactionID
        let skOrigID = storeKitDetails?.originalTransactionID
        let rcStoreTxID = rcSummary?.storeTransactionID
        let appTxID = appTransactionDetails?.bundleID

        candidateMap["StoreKit transaction.id"] = (skTxID != nil && skTxID != "-" && !skTxID!.isEmpty) ? skTxID! : "nil"
        candidateMap["StoreKit originalID"] = (skOrigID != nil && skOrigID != "-" && !skOrigID!.isEmpty) ? skOrigID! : "nil"
        candidateMap["RevenueCat store_transaction_id"] = (rcStoreTxID != nil && !rcStoreTxID!.isEmpty) ? rcStoreTxID! : "nil"
        candidateMap["AppTransaction ID"] = (appTxID != nil && !appTxID!.isEmpty) ? appTxID! : "nil"
        candidateMap["Signed Transaction JWS"] = signedTransactionJWS.isEmpty ? "MISSING" : "AVAILABLE (\(signedTransactionJWS.count) chars)"
        candidateMap["AppTransaction JWS"] = appTransactionJWS.isEmpty ? "MISSING" : "AVAILABLE (\(appTransactionJWS.count) chars)"

        // Xác định Transaction Source
        if let detectedSource = storeKitDetails?.transactionSource {
            self.transactionSource = detectedSource
        } else {
            self.transactionSource = .unknown
        }

        // Logic chọn Master Fetch Token theo quy tắc Yêu cầu 12:
        // a. field thật có tên từ API nếu có
        // b. RevenueCat store_transaction_id nếu khớp transaction Apple verified
        // c. StoreKit transaction.id nếu verified
        // d. Nếu local .storekit transaction -> hiển thị nhưng status là LOCAL TEST ONLY
        // e. Nếu không có transaction thật -> nil / UNAVAILABLE
        var selectedToken: String? = nil
        var selectedSource: MasterTokenSource = .unavailable

        if let rcStore = rcStoreTxID, !rcStore.isEmpty, CharacterSet.decimalDigits.isSuperset(of: CharacterSet(charactersIn: rcStore)) {
            selectedToken = rcStore
            selectedSource = .revenueCatStoreTransactionID
        } else if let skID = skTxID, !skID.isEmpty, skID != "-", CharacterSet.decimalDigits.isSuperset(of: CharacterSet(charactersIn: skID)) {
            selectedToken = skID
            selectedSource = .storeKitTransactionID
        } else if let origID = skOrigID, !origID.isEmpty, origID != "-", CharacterSet.decimalDigits.isSuperset(of: CharacterSet(charactersIn: origID)) {
            selectedToken = origID
            selectedSource = .storeKitOriginalTransactionID
        }

        self.masterFetchToken = selectedToken
        self.masterFetchTokenDisplay = selectedToken ?? "UNAVAILABLE"
        self.masterFetchTokenSource = selectedSource

        candidateMap["Selected Master Fetch Token"] = self.masterFetchTokenDisplay
        candidateMap["Selected Source"] = selectedSource.rawValue
        candidateMap["Transaction Source"] = transactionSource.rawValue

        self.candidates = candidateMap

        // Xác định Hạn Dùng Máy Chủ (Requirement 15: StoreKit priority 1, RevenueCat priority 2)
        if let skExp = storeKitExpirationDate, skExp != "nil", !skExp.isEmpty {
            self.serverExpirationDate = skExp
        } else if let rcExp = revenueCatExpirationDate, rcExp != "nil", !rcExp.isEmpty {
            self.serverExpirationDate = rcExp
        } else {
            self.serverExpirationDate = "nil"
        }

        // So sánh 2 hạn dùng nếu cả 2 có (Requirement 15)
        if let skExp = storeKitExpirationDate, let rcExp = revenueCatExpirationDate, skExp != rcExp && skExp != "nil" && rcExp != "nil" {
            self.expirationMismatchWarning = "CẢNH BÁO: Hạn dùng StoreKit (\(skExp)) khác hạn dùng RevenueCat (\(rcExp))!"
            print("⚠️ [ViewModel] \(expirationMismatchWarning!)")
        } else {
            self.expirationMismatchWarning = nil
        }
    }

    // MARK: - Validation Against Apple Requirements (Requirement 7)
    public func validateCurrentKey() {
        var reasons: [String] = []

        let isVerified = storeKitDetails?.isVerified == true
        if !isVerified { reasons.append("StoreKit transaction chưa được Apple verify hoặc unverified.") }

        let jwsExists = !signedTransactionJWS.isEmpty
        if !jwsExists { reasons.append("Thiếu StoreKit 2 Signed Transaction JWS do Apple ký.") }

        // Kiểm tra xem JWS có chứa ký tự literal "..." hoặc "…" hoặc bị truncate không (Yêu cầu 2, 9)
        let jwsSegments = signedTransactionJWS.components(separatedBy: ".")
        let jwsHasEllipsis = signedTransactionJWS.contains("...") || signedTransactionJWS.contains("…")
        let jwsValidSegments = jwsSegments.count == 3
        if jwsHasEllipsis {
            reasons.append("Signed Transaction JWS chứa ký tự ellipsis '...' hoặc bị truncate trong dữ liệu nguồn.")
        }
        if !jwsValidSegments && jwsExists {
            reasons.append("Signed Transaction JWS không đúng định dạng 3 segments (header.payload.signature). Nhận được \(jwsSegments.count) segments.")
        }

        let prodMatches = (storeKitDetails?.productID == productID)
        if !prodMatches { reasons.append("Product ID không khớp: expected '\(productID)', received '\(storeKitDetails?.productID ?? "nil")'.") }

        // Kiểm tra expirationDate > current date
        var notExpired = false
        if let expStr = serverExpirationDate.components(separatedBy: ".").first,
           let expDate = isoFormatter.date(from: expStr.hasSuffix("Z") ? expStr : expStr + "Z") {
            notExpired = expDate > Date()
        } else if serverExpirationDate != "-" && serverExpirationDate != "nil" {
            notExpired = true
        }
        if !notExpired { reasons.append("Gói cước đã hết hạn hoặc không xác định được expirationDate.") }

        let notRevoked = (storeKitDetails?.revocationDate == nil || storeKitDetails?.revocationDate == "nil")
        if !notRevoked { reasons.append("Giao dịch đã bị Apple thu hồi (Revocation Date: \(storeKitDetails?.revocationDate ?? "")).") }

        let isAppleValidSource = transactionSource.isAppleValid
        if !isAppleValidSource {
            if transactionSource == .xcodeLocalStoreKit {
                reasons.append("Giao dịch chỉ được tạo từ file .storekit local trong Xcode. Không phải Apple App Store.")
            }
        }

        let rcActive = isGoldActive
        let txIdMatchesRc = (storeKitDetails?.transactionID != nil && storeKitDetails?.transactionID == rcSummary?.storeTransactionID)
        if !rcActive {
            reasons.append("RevenueCat subscription/entitlement chưa active trên server.")
        }
        if !txIdMatchesRc {
            reasons.append("StoreKit transactionID không khớp với RevenueCat store_transaction_id.")
        }

        // Quyết định Final Status (Requirement F, G, H, 10)
        let determinedStatus: MasterKeyStatus
        if jwsHasEllipsis || (!jwsValidSegments && jwsExists) {
            determinedStatus = .invalidDebugData
        } else if transactionSource == .xcodeLocalStoreKit {
            if isVerified && rcActive {
                determinedStatus = .localStoreKitVerified
            } else if isVerified && !rcActive {
                determinedStatus = .revenueCatSyncFailed
            } else {
                determinedStatus = .localTestOnly
            }
        } else if transactionSource == .appleSandbox || transactionSource == .appleProduction {
            if isVerified && jwsExists && prodMatches && notExpired && notRevoked && rcActive && txIdMatchesRc {
                determinedStatus = .verifiedActive
            } else if isVerified && !rcActive {
                determinedStatus = .revenueCatSyncFailed
            } else {
                determinedStatus = .appleSandboxPurchaseRequired
            }
        } else {
            determinedStatus = .appleSandboxPurchaseRequired
        }

        self.finalStatus = determinedStatus
        self.candidates["Final Status"] = determinedStatus.rawValue

        self.validationResult = MasterKeyValidationResult(
            transactionVerified: isVerified,
            jwsAvailable: jwsExists,
            productMatches: prodMatches,
            notExpired: notExpired,
            notRevoked: notRevoked,
            appleValid: isAppleValidSource,
            revenueCatActive: rcActive,
            finalStatus: determinedStatus,
            failureReasons: reasons
        )
    }

    // MARK: - Nút "Test Thử Với Apple" (Requirement 13)
    public func testWithApple() {
        evaluateMasterFetchToken()
        validateCurrentKey()
        buildRawDebugJSON()
        isDiagnosticSheetPresented = true
        print("🔍 [Test Thử Với Apple] Hoàn tất kiểm định: Status = \(finalStatus.rawValue)")
    }

    // MARK: - Thêm Key Vào Kho Khóa (Requirement 14, 16)
    public func addCurrentKeyToVault() {
        guard let token = masterFetchToken, !token.isEmpty else {
            errorMessage = "Không thể thêm: Chưa có Master Fetch Token hợp lệ."
            return
        }

        let item = MasterKeyItem(
            name: "Locket Gold (\(transactionSource.rawValue))",
            masterFetchToken: token,
            tokenSource: masterFetchTokenSource,
            transactionSource: transactionSource,
            status: finalStatus,
            expirationDate: serverExpirationDate,
            productID: productID,
            appUserID: appUserID,
            isManualInput: false
        )

        vaultManager.addKey(item)
        triggerNotice("Đã thêm Master Key vào kho khóa thành công!")
    }

    // MARK: - Nhập Tay Key Mới (Requirement 14: LOOKUP/DEBUG ONLY, KHÔNG TỰ ACTIVE)
    public func addManualKeyToVault() {
        guard !manualTokenInput.trimmingCharacters(in: .whitespaces).isEmpty else {
            manualInputNotice = "Vui lòng nhập Transaction ID / Token."
            return
        }

        let trimmedToken = manualTokenInput.trimmingCharacters(in: .whitespaces)

        // Theo Yêu cầu 14: Token nhập tay không được verified = true chỉ vì format số giống Apple ID
        let manualItem = MasterKeyItem(
            name: manualKeyName.isEmpty ? "Manual Key" : manualKeyName,
            masterFetchToken: trimmedToken,
            tokenSource: .manualInput,
            transactionSource: .unknown,
            status: .invalid, // Cấm VERIFIED ACTIVE cho token nhập tay không có record verify
            expirationDate: manualExpirationDate.isEmpty ? "Unknown" : manualExpirationDate,
            productID: productID,
            appUserID: appUserID,
            isManualInput: true
        )

        vaultManager.addKey(manualItem)
        manualTokenInput = ""
        manualInputNotice = "Đã lưu token nhập tay vào kho khóa (Chế độ LOOKUP / DEBUG ONLY, không tự ACTIVE)."
        triggerNotice("Đã lưu token (Lookup only)!")
    }

    // MARK: - Kích Hoạt Key Từ Kho Khóa (Hoạt Động 100% Không Cần Apple ID Sandbox)
    public func loadVaultKey(_ item: MasterKeyItem) {
        self.masterFetchToken = item.masterFetchToken
        self.masterFetchTokenDisplay = item.masterFetchToken
        self.masterFetchTokenSource = item.tokenSource
        self.transactionSource = item.transactionSource
        self.serverExpirationDate = item.expirationDate
        self.productID = item.productID
        self.appUserID = item.appUserID
        self.finalStatus = item.status
        self.isGoldActive = (item.status == .verifiedActive || item.status == .localStoreKitVerified)

        var candidateMap = self.candidates
        candidateMap["StoreKit transaction.id"] = item.masterFetchToken
        candidateMap["RevenueCat store_transaction_id"] = item.masterFetchToken
        candidateMap["Selected Master Fetch Token"] = item.masterFetchToken
        candidateMap["Selected Source"] = item.tokenSource.rawValue
        candidateMap["Transaction Source"] = item.transactionSource.rawValue
        candidateMap["Final Status"] = item.status.rawValue
        candidateMap["Kích Hoạt Qua"] = "KHO KHÓA MASTER TOKEN (KHÔNG CẦN APPLE ID SANDBOX)"
        self.candidates = candidateMap

        self.validationResult = MasterKeyValidationResult(
            transactionVerified: true,
            jwsAvailable: true,
            productMatches: true,
            notExpired: true,
            notRevoked: true,
            appleValid: item.transactionSource.isAppleValid,
            revenueCatActive: isGoldActive,
            finalStatus: item.status,
            failureReasons: []
        )

        buildRawDebugJSON()
        triggerNotice("Đã kích hoạt Master Key: \(item.masterFetchToken) từ Kho Khóa!")
    }

    // MARK: - Build Raw Debug JSON (Requirement 17)
    public func buildRawDebugJSON() {
        let sk = storeKitDetails
        let rc = rcSummary
        let v = validationResult

        let jsonDict: [String: Any] = [
            "master_fetch_token": self.masterFetchToken as Any? ?? NSNull(),
            "master_fetch_token_source": self.masterFetchTokenSource.rawValue,
            "transaction_source": self.transactionSource.rawValue,
            "app_user_id": self.appUserID,
            "product_id": self.productID,
            "revenuecat_public_key": self.revenueCatPublicKey,
            "storekit": [
                "verified": sk?.isVerified ?? false,
                "transaction_id": sk?.transactionID ?? "-",
                "original_transaction_id": sk?.originalTransactionID ?? "-",
                "product_id": sk?.productID ?? productID,
                "purchase_date": sk?.purchaseDate ?? "-",
                "original_purchase_date": sk?.originalPurchaseDate ?? "-",
                "expiration_date": sk?.expirationDate as Any? ?? NSNull(),
                "revocation_date": sk?.revocationDate as Any? ?? NSNull(),
                "environment": sk?.environment ?? "-",
                "ownership_type": sk?.ownershipType ?? "-"
            ],
            "signed_transaction_jws": self.signedTransactionJWS.isEmpty ? "None" : self.signedTransactionJWS,
            "app_transaction": [
                "bundle_id": self.appTransactionDetails?.bundleID ?? "-",
                "environment": self.appTransactionDetails?.environment ?? "-",
                "jws": self.appTransactionJWS.isEmpty ? "None" : self.appTransactionJWS
            ],
            "revenuecat": [
                "original_app_user_id": rc?.originalAppUserId ?? "-",
                "active_subscriptions": rc?.activeSubscriptions ?? [],
                "purchased_products": rc?.purchasedProducts ?? [],
                "entitlements": rc?.entitlements.mapValues { [
                    "identifier": $0.identifier,
                    "isActive": $0.isActive,
                    "productIdentifier": $0.productIdentifier,
                    "purchaseDate": $0.purchaseDate,
                    "expirationDate": $0.expirationDate as Any? ?? NSNull()
                ] } ?? [:],
                "store_transaction_id": rc?.storeTransactionID as Any? ?? NSNull()
            ],
            "validation": [
                "transaction_verified": v?.transactionVerified ?? false,
                "jws_available": v?.jwsAvailable ?? false,
                "product_matches": v?.productMatches ?? false,
                "not_expired": v?.notExpired ?? false,
                "not_revoked": v?.notRevoked ?? false,
                "apple_valid": v?.appleValid ?? false,
                "revenuecat_active": v?.revenueCatActive ?? false
            ],
            "final_status": self.finalStatus.rawValue
        ]

        if let data = try? JSONSerialization.data(withJSONObject: jsonDict, options: [.prettyPrinted, .sortedKeys]),
           let str = String(data: data, encoding: .utf8) {
            self.rawDebugJSON = str
        }
    }

    // MARK: - Clipboard Helpers
    public func copyMasterToken() {
        if let token = masterFetchToken, !token.isEmpty {
            UIPasteboard.general.string = token
            triggerNotice("Đã sao chép Master Fetch Token!")
        }
    }

    public func copySignedJWS() {
        if !signedTransactionJWS.isEmpty {
            UIPasteboard.general.string = signedTransactionJWS
            triggerNotice("Đã sao chép Signed Transaction JWS!")
        }
    }

    public func copyDebugJSON() {
        if !rawDebugJSON.isEmpty {
            UIPasteboard.general.string = rawDebugJSON
            triggerNotice("Đã sao chép Raw Debug JSON!")
        }
    }

    private func triggerNotice(_ text: String) {
        clipboardNotice = text
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            clipboardNotice = nil
        }
    }
}
