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
    @Published public var masterFetchTokenDisplay: String = "null"
    @Published public var masterFetchTokenSource: MasterTokenSource = .unavailable
    @Published public var transactionSource: TransactionSource = .unknown
    @Published public var finalStatus: MasterKeyStatus = .purchaseRequired

    // MARK: - 2.1 Fetch Token (StoreKit 2 Signed JWS)
    @Published public var fetchToken: String? = nil
    @Published public var fetchTokenType: String = "STOREKIT2_JWS_TRANSACTION"

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

    // MARK: - 6.1 Cross-UID & Owner Validation (Requirements 2, 6, 10)
    @Published public var vaultItemOwner: String? = nil
    @Published public var vaultTransactionID: String? = nil
    @Published public var transactionOwnerMatch: Bool = true
    @Published public var transactionIdMatch: Bool = false

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

        // Cập nhật fetchToken (Section 4: STOREKIT2_JWS_TRANSACTION)
        if storeKitDetails?.isVerified == true && !signedTransactionJWS.isEmpty {
            self.fetchToken = signedTransactionJWS
        } else {
            self.fetchToken = nil
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

    // MARK: - Evaluate Master Fetch Token & Candidates (Requirements 1, 4, 5)
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

        // Section 5: Master Fetch Token dạng transaction ID chỉ được tạo sau khi transaction verified.
        // Candidate: master_fetch_token = String(transaction.id)
        // Chỉ khi: String(transaction.id) == RevenueCat store_transaction_id
        // thì: master_fetch_token = RevenueCat store_transaction_id, source = REVENUECAT_STORE_TRANSACTION_ID
        var selectedToken: String? = nil
        var selectedSource: MasterTokenSource = .unavailable

        let isVerified = storeKitDetails?.isVerified == true
        if isVerified, let skID = skTxID, !skID.isEmpty, skID != "-" {
            if let rcStore = rcStoreTxID, rcStore == skID {
                selectedToken = rcStore
                selectedSource = .revenueCatStoreTransactionID
            } else {
                selectedToken = nil
                selectedSource = .unavailable
            }
        } else {
            selectedToken = nil
            selectedSource = .unavailable
        }

        self.masterFetchToken = selectedToken
        self.masterFetchTokenDisplay = selectedToken ?? "null"
        self.masterFetchTokenSource = selectedSource

        candidateMap["Selected Master Fetch Token"] = self.masterFetchTokenDisplay
        candidateMap["Selected Source"] = selectedSource.rawValue
        candidateMap["Transaction Source"] = transactionSource.rawValue

        self.candidates = candidateMap

        // Xác định Hạn Dùng Máy Chủ (StoreKit priority 1, RevenueCat priority 2)
        if let skExp = storeKitExpirationDate, skExp != "nil", !skExp.isEmpty {
            self.serverExpirationDate = skExp
        } else if let rcExp = revenueCatExpirationDate, rcExp != "nil", !rcExp.isEmpty {
            self.serverExpirationDate = rcExp
        } else {
            self.serverExpirationDate = "-"
        }

        // So sánh 2 hạn dùng nếu cả 2 có
        if let skExp = storeKitExpirationDate, let rcExp = revenueCatExpirationDate, skExp != rcExp && skExp != "nil" && rcExp != "nil" {
            self.expirationMismatchWarning = "CẢNH BÁO: Hạn dùng StoreKit (\(skExp)) khác hạn dùng RevenueCat (\(rcExp))!"
            print("⚠️ [ViewModel] \(expirationMismatchWarning!)")
        } else {
            self.expirationMismatchWarning = nil
        }
    }

    // MARK: - Validation Against Apple Requirements (Section 1, 6, 7, 8, 10)
    public func validateCurrentKey() {
        var reasons: [String] = []

        let isVerified = storeKitDetails?.isVerified == true
        if !isVerified { reasons.append("StoreKit transaction chưa được Apple verify hoặc unverified.") }

        let jwsExists = !signedTransactionJWS.isEmpty
        if !jwsExists { reasons.append("Thiếu StoreKit 2 Signed Transaction JWS do Apple ký.") }

        // Kiểm tra xem JWS có chứa ký tự literal "..." hoặc "…" hoặc bị truncate không (Section 4, 7)
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
        if !prodMatches && isVerified { reasons.append("Product ID không khớp: expected '\(productID)', received '\(storeKitDetails?.productID ?? "nil")'.") }

        let notRevoked = (storeKitDetails?.revocationDate == nil || storeKitDetails?.revocationDate == "nil")
        if !notRevoked { reasons.append("Giao dịch đã bị Apple thu hồi (Revocation Date: \(storeKitDetails?.revocationDate ?? "")).") }

        let isAppleValidSource = transactionSource.isAppleValid
        if !isAppleValidSource && isVerified {
            if transactionSource == .xcodeLocalStoreKit {
                reasons.append("Giao dịch chỉ được tạo từ file .storekit local trong Xcode. Không phải Apple App Store.")
            }
        }

        let rcActive = isGoldActive
        let txIdMatchesRc = (storeKitDetails?.transactionID != nil && storeKitDetails?.transactionID == rcSummary?.storeTransactionID)
        if isVerified && !rcActive {
            reasons.append("RevenueCat subscription/entitlement chưa active trên server.")
        }
        if isVerified && !txIdMatchesRc {
            reasons.append("StoreKit transactionID không khớp với RevenueCat store_transaction_id.")
        }

        // Quyết định Final Status (Section 1, 6, 8, 10)
        let determinedStatus: MasterKeyStatus
        if jwsHasEllipsis || (!jwsValidSegments && jwsExists) {
            determinedStatus = .invalidDebugData
        } else if !isVerified {
            determinedStatus = .purchaseRequired
        } else if isVerified && (!rcActive || !txIdMatchesRc) {
            determinedStatus = .revenueCatSyncFailed
        } else if isVerified && rcActive && txIdMatchesRc && jwsExists && jwsValidSegments && !jwsHasEllipsis && notRevoked {
            determinedStatus = .verifiedActive
        } else {
            determinedStatus = .purchaseRequired
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

    // MARK: - Load Vault Key (Strict Owner Check & Live Validation - ZERO Cross-UID Reuse)
    public func loadVaultKey(_ item: MasterKeyItem) {
        self.vaultItemOwner = item.appUserID
        self.vaultTransactionID = item.masterFetchToken

        // 1. Kiểm tra quyền sở hữu UID (Requirement 2 & 6: Tuyệt đối không reuse transaction của UID khác)
        guard item.appUserID == self.appUserID else {
            print("❌ [Cross-UID Check] Transaction thuộc UID khác: stored '\(item.appUserID)', current '\(self.appUserID)'")
            self.transactionOwnerMatch = false
            self.transactionIdMatch = false
            self.finalStatus = .transactionOwnerMismatch
            self.isGoldActive = false
            self.masterFetchToken = nil
            self.masterFetchTokenDisplay = "MISMATCH (OWNED BY \(item.appUserID))"
            self.masterFetchTokenSource = item.tokenSource
            self.transactionSource = item.transactionSource

            var candidateMap = self.candidates
            candidateMap["Final Status"] = MasterKeyStatus.transactionOwnerMismatch.rawValue
            candidateMap["Current UID"] = self.appUserID
            candidateMap["Stored UID"] = item.appUserID
            candidateMap["Stored Transaction"] = item.masterFetchToken
            candidateMap["Owner Check"] = "TRANSACTION_OWNER_MISMATCH (REUSE REJECTED)"
            self.candidates = candidateMap

            self.errorMessage = "TRANSACTION_OWNER_MISMATCH: Key thuộc về UID '\(item.appUserID)', không thể dùng cho UID '\(self.appUserID)'."
            buildRawDebugJSON()
            return
        }

        self.transactionOwnerMatch = true

        // 2. Kiểm tra Live RevenueCat State của UID hiện tại (Requirement 4: Chỉ active nếu live server có subscription)
        let liveRcStoreTxID = rcSummary?.storeTransactionID
        let liveRcActive = isGoldActive && rcSummary?.activeSubscriptions.contains(productID) == true

        guard liveRcActive else {
            print("❌ [Live RC Check] UID '\(self.appUserID)' chưa có active subscription trên live server.")
            self.transactionIdMatch = false
            self.finalStatus = .inactive
            self.isGoldActive = false
            self.masterFetchToken = nil
            self.masterFetchTokenDisplay = "NONE (INACTIVE ON LIVE SERVER)"

            var candidateMap = self.candidates
            candidateMap["Final Status"] = MasterKeyStatus.inactive.rawValue
            candidateMap["Live RC Active"] = "NO"
            candidateMap["Current UID"] = self.appUserID
            self.candidates = candidateMap

            self.errorMessage = "UID hiện tại chưa có subscription thật trên RevenueCat live. Trạng thái: INACTIVE."
            buildRawDebugJSON()
            return
        }

        // 3. Kiểm tra Store Transaction ID khớp 1-1 với live RevenueCat (Requirement 5)
        guard let rcStoreTx = liveRcStoreTxID, !rcStoreTx.isEmpty, rcStoreTx == item.masterFetchToken else {
            print("❌ [Store Transaction Match] Token trong vault '\(item.masterFetchToken)' không khớp live store_transaction_id '\(liveRcStoreTxID ?? "nil")'")
            self.transactionIdMatch = false
            self.finalStatus = .invalid
            self.isGoldActive = false
            self.errorMessage = "Store Transaction ID không khớp với bản ghi live của RevenueCat."
            buildRawDebugJSON()
            return
        }

        // 4. Khi và chỉ khi cả 3 điều kiện trên thoả mãn mới coi là VERIFIED ACTIVE
        self.transactionIdMatch = true
        self.masterFetchToken = item.masterFetchToken
        self.masterFetchTokenDisplay = item.masterFetchToken
        self.masterFetchTokenSource = item.tokenSource
        self.transactionSource = item.transactionSource
        self.serverExpirationDate = item.expirationDate
        self.finalStatus = .verifiedActive
        self.isGoldActive = true

        var candidateMap = self.candidates
        candidateMap["StoreKit transaction.id"] = item.masterFetchToken
        candidateMap["RevenueCat store_transaction_id"] = rcStoreTx
        candidateMap["Selected Master Fetch Token"] = item.masterFetchToken
        candidateMap["Selected Source"] = item.tokenSource.rawValue
        candidateMap["Transaction Source"] = item.transactionSource.rawValue
        candidateMap["Final Status"] = MasterKeyStatus.verifiedActive.rawValue
        candidateMap["Owner Check"] = "MATCHED (OWNED BY \(self.appUserID))"
        self.candidates = candidateMap

        buildRawDebugJSON()
        triggerNotice("Đã xác thực Master Key khớp 100% cho UID '\(self.appUserID)'!")
    }

    // MARK: - Build Raw Debug JSON (Section 10 Output Format)
    public func buildRawDebugJSON() {
        let sk = storeKitDetails
        let rc = rcSummary
        let jwsSegments = signedTransactionJWS.components(separatedBy: ".")
        let jwsHasEllipsis = signedTransactionJWS.contains("...") || signedTransactionJWS.contains("…")
        let jwsFull = (jwsSegments.count == 3 && !jwsHasEllipsis && !signedTransactionJWS.isEmpty)
        let isTxVerified = sk?.isVerified ?? false
        let txIdMatch = (sk?.transactionID != nil && sk?.transactionID != "-" && sk?.transactionID == rc?.storeTransactionID)
        let rcLiveMatch = self.isGoldActive && (rc?.storeTransactionID != nil)

        let jsonDict: [String: Any] = [
            "app_user_id": self.appUserID,
            "product_id": self.productID,
            "master_fetch_token": self.masterFetchToken as Any? ?? NSNull(),
            "master_fetch_token_source": self.masterFetchTokenSource.rawValue,
            "fetch_token": self.fetchToken as Any? ?? NSNull(),
            "fetch_token_type": self.fetchTokenType,
            "storekit": [
                "verified": isTxVerified,
                "transaction_id": sk?.transactionID ?? "-",
                "original_transaction_id": sk?.originalTransactionID ?? "-",
                "environment": sk?.environment ?? "-",
                "purchase_date": sk?.purchaseDate ?? "-",
                "expiration_date": sk?.expirationDate as Any? ?? NSNull()
            ],
            "revenuecat": [
                "subscription_active": self.isGoldActive,
                "store": rc?.entitlements[entitlementID]?.store ?? "app_store",
                "store_transaction_id": rc?.storeTransactionID as Any? ?? NSNull(),
                "entitlement_active": self.isGoldActive
            ],
            "validation": [
                "jws_full": jwsFull,
                "apple_transaction_verified": isTxVerified,
                "transaction_id_match": txIdMatch,
                "revenuecat_live_match": rcLiveMatch
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
