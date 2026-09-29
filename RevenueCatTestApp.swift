import SwiftUI
import StoreKit
import RevenueCat

// MARK: - Configuration Constants
enum RevenueCatConfig {
    static let apiKey = "appl_JngFETzdodyLmCREOlwTUtXdQik"
    static let appUserID = "kqdepzai"
    static let offeringID = "locket_199"
    static let packageID = "$rc_annual"
    static let expectedProductID = "locket_1600_1y"
    static let entitlementID = "Gold"
}

// MARK: - Main Application Entry Point
@main
struct RevenueCatTestApp: App {
    @StateObject private var viewModel = RevenueCatViewModel()

    init() {
        // Bật log mức Debug để in chi tiết mọi request, response, token và metadata từ SDK
        Purchases.logLevel = .debug

        // Cấu hình Purchases SDK cho Xcode Local StoreKit + RevenueCat
        Purchases.configure(
            withAPIKey: RevenueCatConfig.apiKey,
            appUserID: RevenueCatConfig.appUserID
        )
        print("🚀 [Xcode Local StoreKit] Initialized with App User ID: \(RevenueCatConfig.appUserID)")
    }

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
        }
    }
}

// MARK: - View Model
@MainActor
final class RevenueCatViewModel: ObservableObject {
    // 1. Thông tin định danh & Offering
    @Published var appUserID: String = RevenueCatConfig.appUserID
    @Published var originalAppUserId: String = "-"
    @Published var productIdentifier: String = RevenueCatConfig.expectedProductID
    @Published var packageIdentifier: String = RevenueCatConfig.packageID
    @Published var offeringIdentifier: String = RevenueCatConfig.offeringID

    @Published var store: String = "app_store"
    @Published var storeTransactionIdentifier: String = "-"
    @Published var transactionIdentifier: String = "-"
    @Published var originalTransactionIdentifier: String = "nil"
    @Published var purchaseDate: String = "-"
    @Published var expirationDate: String = "-"
    @Published var isSandbox: String = "true"

    // 3. Thông tin Entitlement
    @Published var entitlementIdentifier: String = RevenueCatConfig.entitlementID
    @Published var entitlementIsActive: Bool = false
    @Published var latestPurchaseDate: String = "-"
    @Published var ownershipType: String = "-"
    @Published var periodType: String = "-"
    @Published var unsubscribeDetectedAt: String = "nil"
    @Published var billingIssueDetectedAt: String = "nil"
    @Published var verificationResult: String = "-"

    // 4. Token & Security Investigation (Kiểm tra fetch_token, receipt, JWS)
    @Published var fetchToken: String? = nil
    @Published var fetchTokenType: String = "XCODE_LOCAL_STOREKIT_JWS"
    @Published var fetchTokenStatus: String = "XCODE_LOCAL_STOREKIT_JWS (NO TRANSACTION YET)"
    @Published var receiptStatus: String = "XCODE_LOCAL_STOREKIT (LocketGold.storekit)"
    @Published var jwsStatus: String = "STOREKIT 2 LOCAL JWS (SIGNED BY LOCAL CERTIFICATE)"

    // 5. Raw Data & JSON Dumps
    @Published var unifiedDebugJSON: String = ""
    @Published var rawPurchaseResultJSON: String = "Chưa có purchase result."
    @Published var rawCustomerInfoJSON: String = "Chưa có CustomerInfo."
    @Published var rawSubscriberAPIJSON: String = "Chưa fetch REST API."

    // 6. UI State
    @Published var isLoading: Bool = false
    @Published var statusMessage: String = "Ready"
    @Published var errorMessage: String? = nil
    @Published var copiedNotice: Bool = false

    private(set) var annualPackage: Package?
    private let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    // Khởi chạy khi view xuất hiện
    func initialLoad() async {
        await refreshCustomerInfo()
        await fetchOfferings()
        await fetchSubscriberRestAPI()
    }

    // MARK: - 1. Fetch Offerings
    func fetchOfferings() async {
        isLoading = true
        errorMessage = nil
        statusMessage = "Fetching Offerings..."

        do {
            let offerings = try await Purchases.shared.offerings()
            if let defaultOffering = offerings.current ?? offerings.offering(identifier: RevenueCatConfig.offeringID) ?? offerings.all["default"] {
                self.offeringIdentifier = defaultOffering.identifier
                if let pkg = defaultOffering.package(identifier: RevenueCatConfig.packageID) {
                    self.annualPackage = pkg
                    self.packageIdentifier = pkg.identifier
                    self.productIdentifier = pkg.storeProduct.productIdentifier
                    print("📦 [RevenueCat] Loaded package: \(pkg.identifier), product: \(pkg.storeProduct.productIdentifier)")
                } else {
                    errorMessage = "Không tìm thấy package '\(RevenueCatConfig.packageID)'."
                }
            } else {
                errorMessage = "Không tìm thấy offering '\(RevenueCatConfig.offeringID)'."
            }
            statusMessage = "Offerings loaded."
        } catch {
            print("❌ [RevenueCat] Error fetching offerings: \(error.localizedDescription)")
            errorMessage = "Fetch Offerings error: \(error.localizedDescription)"
        }

        isLoading = false
    }

    // MARK: - 2. Purchase Annual
    func purchaseAnnual() async {
        guard let targetPackage = annualPackage else {
            errorMessage = "Package '\(RevenueCatConfig.packageID)' is not loaded yet."
            return
        }

        isLoading = true
        errorMessage = nil
        statusMessage = "Purchasing \(targetPackage.identifier)..."

        print("🛒 [RevenueCat DEBUG] Triggering purchase for package: \(targetPackage.identifier)")

        do {
            let result = try await Purchases.shared.purchase(package: targetPackage)

            if result.userCancelled {
                print("ℹ️ [RevenueCat DEBUG] User cancelled purchase.")
                statusMessage = "Purchase cancelled by user."
                isLoading = false
                return
            }

            print("✅ [RevenueCat DEBUG] Purchase completed successfully!")
            
            // Xử lý Transaction trả về
            if let tx = result.transaction {
                self.transactionIdentifier = tx.transactionIdentifier
                self.storeTransactionIdentifier = tx.transactionIdentifier
                self.purchaseDate = isoFormatter.string(from: tx.purchaseDate)
                print("🧾 [RevenueCat DEBUG] Transaction Identifier: \(tx.transactionIdentifier)")
                print("📅 [RevenueCat DEBUG] Transaction Purchase Date: \(tx.purchaseDate)")
            }

            // Xcode Local StoreKit 2: Trích xuất signed transaction JWS thật từ StoreKit local
            if #available(iOS 15.0, *) {
                for await entResult in StoreKit.Transaction.currentEntitlements {
                    if case .verified(let transaction) = entResult, transaction.productID == RevenueCatConfig.expectedProductID {
                        self.fetchToken = entResult.jwsRepresentation
                        self.fetchTokenType = "XCODE_LOCAL_STOREKIT_JWS"
                        self.fetchTokenStatus = "STOREKIT 2 LOCAL JWS (VERIFIED)"
                        self.transactionIdentifier = String(transaction.id)
                        self.originalTransactionIdentifier = String(transaction.originalID)
                        self.purchaseDate = isoFormatter.string(from: transaction.purchaseDate)
                        if let exp = transaction.expirationDate {
                            self.expirationDate = isoFormatter.string(from: exp)
                        }
                        print("🔑 [StoreKit 2 Local] Verified Local Transaction: \(transaction.id)")
                        break
                    }
                }
            }

            // Serialize RAW PURCHASE RESULT
            buildRawPurchaseResultJSON(result: result)

            // Cập nhật CustomerInfo từ kết quả purchase
            handleCustomerInfo(result.customerInfo)

            // Gọi thêm REST API để lấy đúng store_transaction_id từ server RevenueCat
            await fetchSubscriberRestAPI()

            // Tạo Unified Debug JSON
            buildUnifiedDebugJSON()

            statusMessage = "Purchase successful & debug data updated!"
        } catch {
            if let rcError = error as? RevenueCat.ErrorCode, rcError == .purchaseCancelledError {
                print("ℹ️ [RevenueCat DEBUG] User cancelled purchase.")
                statusMessage = "Purchase cancelled by user."
            } else if (error as NSError).code == RevenueCat.ErrorCode.purchaseCancelledError.rawValue {
                print("ℹ️ [RevenueCat DEBUG] User cancelled purchase.")
                statusMessage = "Purchase cancelled by user."
            } else {
                print("❌ [RevenueCat DEBUG] Purchase error: \(error.localizedDescription)")
                errorMessage = "Purchase error: \(error.localizedDescription)"
                statusMessage = "Purchase failed."
            }
        }

        isLoading = false
    }

    // MARK: - 3. Refresh CustomerInfo
    func refreshCustomerInfo() async {
        isLoading = true
        errorMessage = nil
        statusMessage = "Refreshing CustomerInfo..."

        do {
            let customerInfo = try await Purchases.shared.customerInfo()
            handleCustomerInfo(customerInfo)
            buildUnifiedDebugJSON()
            statusMessage = "CustomerInfo updated."
        } catch {
            print("❌ [RevenueCat DEBUG] CustomerInfo error: \(error.localizedDescription)")
            errorMessage = "Fetch CustomerInfo failed: \(error.localizedDescription)"
        }

        isLoading = false
    }

    // MARK: - 4. Fetch Subscriber JSON qua REST API (GET /v1/subscribers/{app_user_id})
    func fetchSubscriberRestAPI() async {
        let endpoint = "https://api.revenuecat.com/v1/subscribers/\(RevenueCatConfig.appUserID)"
        guard let url = URL(string: endpoint) else { return }

        print("🌐 [RevenueCat REST] Calling GET \(endpoint)")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(RevenueCatConfig.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("ios", forHTTPHeaderField: "X-Platform")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpRes = response as? HTTPURLResponse {
                print("🌐 [RevenueCat REST] Response Status Code: \(httpRes.statusCode)")
            }

            if let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                // In pretty JSON
                if let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted, .sortedKeys]),
                   let prettyString = String(data: prettyData, encoding: .utf8) {
                    self.rawSubscriberAPIJSON = prettyString
                } else {
                    self.rawSubscriberAPIJSON = String(data: data, encoding: .utf8) ?? ""
                }

                // Trích xuất store_transaction_id và store từ response REST API
                if let subscriber = jsonObject["subscriber"] as? [String: Any],
                   let subscriptions = subscriber["subscriptions"] as? [String: Any],
                   let subInfo = subscriptions[self.productIdentifier] as? [String: Any] {
                    
                    if let storeTx = subInfo["store_transaction_id"] as? String {
                        self.storeTransactionIdentifier = storeTx
                        print("🔑 [RevenueCat REST] Found store_transaction_id: \(storeTx)")
                    }
                    if let st = subInfo["store"] as? String {
                        self.store = st
                    }
                    if let exp = subInfo["expires_date"] as? String {
                        self.expirationDate = exp
                    }
                    if let pur = subInfo["purchase_date"] as? String {
                        if self.purchaseDate == "-" {
                            self.purchaseDate = pur
                        }
                    }
                }
            }

            buildUnifiedDebugJSON()
        } catch {
            print("❌ [RevenueCat REST] Error fetching subscriber: \(error.localizedDescription)")
            self.rawSubscriberAPIJSON = "REST API Error: \(error.localizedDescription)"
        }
    }

    // MARK: - Helper: CustomerInfo Processing
    private func handleCustomerInfo(_ customerInfo: CustomerInfo) {
        self.appUserID = Purchases.shared.appUserID
        self.originalAppUserId = customerInfo.originalAppUserId

        // Trích xuất Entitlement 'gold'
        if let entitlement = customerInfo.entitlements[RevenueCatConfig.entitlementID] {
            self.entitlementIsActive = entitlement.isActive
            self.entitlementIdentifier = entitlement.identifier
            self.productIdentifier = entitlement.productIdentifier
            self.store = String(describing: entitlement.store)
            self.isSandbox = entitlement.isSandbox ? "true" : "false"
            self.ownershipType = String(describing: entitlement.ownershipType)
            self.periodType = String(describing: entitlement.periodType)
            self.verificationResult = String(describing: entitlement.verification)

            if let exp = entitlement.expirationDate {
                self.expirationDate = isoFormatter.string(from: exp)
            }
            if let latest = entitlement.latestPurchaseDate {
                self.latestPurchaseDate = isoFormatter.string(from: latest)
            }
            if let unsub = entitlement.unsubscribeDetectedAt {
                self.unsubscribeDetectedAt = isoFormatter.string(from: unsub)
            }
            if let issue = entitlement.billingIssueDetectedAt {
                self.billingIssueDetectedAt = isoFormatter.string(from: issue)
            }
        } else {
            self.entitlementIsActive = false
        }

        // Kiểm tra Verification ở cấp CustomerInfo
        self.verificationResult = String(describing: customerInfo.entitlementVerification)

        // Kiểm tra fetch_token trong StoreKit 2
        if self.fetchToken == nil {
            self.fetchTokenStatus = "STOREKIT 2 JWS (NO TRANSACTION YET)"
        }

        // Serialize RAW CUSTOMER INFO
        if JSONSerialization.isValidJSONObject(customerInfo.rawData),
           let rawData = try? JSONSerialization.data(withJSONObject: customerInfo.rawData, options: [.prettyPrinted, .sortedKeys]),
           let rawString = String(data: rawData, encoding: .utf8) {
            self.rawCustomerInfoJSON = rawString
        } else {
            self.rawCustomerInfoJSON = "\(customerInfo.description)"
        }
    }

    // MARK: - Helper: Build Raw Purchase Result JSON
    private func buildRawPurchaseResultJSON(result: PurchaseResultData) {
        var dict: [String: Any] = [
            "userCancelled": result.userCancelled
        ]

        if let tx = result.transaction {
            dict["transaction"] = [
                "transactionIdentifier": tx.transactionIdentifier,
                "productIdentifier": tx.productIdentifier,
                "purchaseDate": isoFormatter.string(from: tx.purchaseDate),
                "quantity": tx.quantity
            ]
        } else {
            dict["transaction"] = NSNull()
        }

        dict["entitlements_active"] = Array(result.customerInfo.entitlements.active.keys)
        dict["verification_result"] = String(describing: result.customerInfo.entitlementVerification)

        if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]),
           let str = String(data: data, encoding: .utf8) {
            self.rawPurchaseResultJSON = str
        }
    }

    // MARK: - Helper: Build Unified Debug JSON (Section 11 Output Format)
    func buildUnifiedDebugJSON() {
        let isGoldActive = self.entitlementIsActive
        let hasStoreTx = self.storeTransactionIdentifier != "-" && !self.storeTransactionIdentifier.isEmpty
        let isLocalStoreKitVerified = self.fetchToken != nil
        
        let finalStatus: String
        if isGoldActive && hasStoreTx {
            finalStatus = "LOCAL_STOREKIT_REVENUECAT_ACTIVE"
        } else if isLocalStoreKitVerified {
            finalStatus = "REVENUECAT_LOCAL_STOREKIT_SYNC_FAILED"
        } else {
            finalStatus = "STOREKIT_LOCAL_PURCHASE_REQUIRED"
        }

        let storeKitDict: [String: Any] = [
            "verified": isLocalStoreKitVerified,
            "transaction_id": self.transactionIdentifier == "-" ? (NSNull() as Any) : (self.transactionIdentifier as Any),
            "original_transaction_id": (self.originalTransactionIdentifier == "nil" || self.originalTransactionIdentifier == "-") ? (NSNull() as Any) : (self.originalTransactionIdentifier as Any),
            "purchase_date": self.purchaseDate == "-" ? (NSNull() as Any) : (self.purchaseDate as Any),
            "expiration_date": self.expirationDate == "-" ? (NSNull() as Any) : (self.expirationDate as Any)
        ]

        let revenueCatDict: [String: Any] = [
            "subscription_active": isGoldActive,
            "entitlement_gold_active": isGoldActive,
            "store_transaction_id": hasStoreTx ? (self.storeTransactionIdentifier as Any) : (NSNull() as Any)
        ]

        let debugDict: [String: Any] = [
            "app_user_id": self.appUserID,
            "product_id": self.productIdentifier.isEmpty ? RevenueCatConfig.expectedProductID : self.productIdentifier,
            "transaction_source": "XCODE_LOCAL_STOREKIT",
            "master_fetch_token": hasStoreTx ? (self.storeTransactionIdentifier as Any) : (NSNull() as Any),
            "master_fetch_token_source": hasStoreTx ? ("REVENUECAT_STORE_TRANSACTION_ID" as Any) : (NSNull() as Any),
            "fetch_token": self.fetchToken != nil ? (self.fetchToken! as Any) : (NSNull() as Any),
            "fetch_token_type": "XCODE_LOCAL_STOREKIT_JWS",
            "storekit": storeKitDict,
            "revenuecat": revenueCatDict,
            "final_status": finalStatus
        ]

        if let data = try? JSONSerialization.data(withJSONObject: debugDict, options: [.prettyPrinted, .sortedKeys]),
           let str = String(data: data, encoding: .utf8) {
            self.unifiedDebugJSON = str
        }
    }

    // MARK: - Copy Debug JSON to Clipboard
    func copyDebugJSON() {
        UIPasteboard.general.string = self.unifiedDebugJSON
        copiedNotice = true
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            copiedNotice = false
        }
    }
}

// MARK: - UI Content View
struct ContentView: View {
    @ObservedObject var viewModel: RevenueCatViewModel
    @State private var selectedTab: Int = 0

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    
                    // 1. Entitlement Status Header
                    entitlementHeader

                    // 2. Action Buttons
                    actionButtonsGrid

                    // 3. Status & Loading Bar
                    feedbackSection

                    // 4. Token & Security Inspection Banner
                    tokenSecurityBanner

                    // 5. Segmented Debug View
                    Picker("Debug View", selection: $selectedTab) {
                        Text("Unified JSON").tag(0)
                        Text("Fields Inspector").tag(1)
                        Text("Raw Purchase").tag(2)
                        Text("Raw CustomerInfo").tag(3)
                        Text("REST API").tag(4)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding(.top, 4)

                    // Debug Content Panels
                    switch selectedTab {
                    case 0:
                        unifiedJSONPanel
                    case 1:
                        fieldsInspectorPanel
                    case 2:
                        codeDumpPanel(title: "RAW PURCHASE RESULT", code: viewModel.rawPurchaseResultJSON)
                    case 3:
                        codeDumpPanel(title: "RAW CUSTOMER INFO (customerInfo.rawData)", code: viewModel.rawCustomerInfoJSON)
                    case 4:
                        codeDumpPanel(title: "REVENUECAT REST API (GET /v1/subscribers)", code: viewModel.rawSubscriberAPIJSON)
                    default:
                        EmptyView()
                    }

                    Spacer(minLength: 40)
                }
                .padding()
            }
            .navigationTitle("RevenueCat Debugger")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await viewModel.initialLoad()
            }
        }
    }

    // MARK: - Header
    private var entitlementHeader: some View {
        HStack {
            Image(systemName: viewModel.entitlementIsActive ? "crown.fill" : "lock.fill")
                .font(.title2)
            Text(viewModel.entitlementIsActive ? "Locket Gold: ACTIVE" : "Locket Gold: INACTIVE")
                .font(.headline)
                .fontWeight(.bold)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .foregroundColor(viewModel.entitlementIsActive ? .green : .red)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(viewModel.entitlementIsActive ? Color.green.opacity(0.12) : Color.red.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(viewModel.entitlementIsActive ? Color.green.opacity(0.4) : Color.red.opacity(0.4), lineWidth: 1.5)
        )
    }

    // MARK: - Action Buttons Grid
    private var actionButtonsGrid: some View {
        VStack(spacing: 10) {
            // Purchase Button
            Button(action: {
                Task {
                    await viewModel.purchaseAnnual()
                }
            }) {
                HStack {
                    Image(systemName: "cart.fill")
                    Text("Purchase Annual (\(viewModel.packageIdentifier))")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(viewModel.annualPackage == nil || viewModel.isLoading ? Color.gray : Color.blue)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(viewModel.annualPackage == nil || viewModel.isLoading)

            // Secondary Buttons (2x2 Grid)
            HStack(spacing: 8) {
                actionButton(title: "Refresh Info", icon: "person.crop.circle.badge.checkmark") {
                    await viewModel.refreshCustomerInfo()
                }

                actionButton(title: "Fetch REST API", icon: "network") {
                    await viewModel.fetchSubscriberRestAPI()
                }

                actionButton(title: viewModel.copiedNotice ? "Copied!" : "Copy Debug JSON", icon: viewModel.copiedNotice ? "checkmark" : "doc.on.doc") {
                    viewModel.copyDebugJSON()
                }
            }
        }
    }

    private func actionButton(title: String, icon: String, action: @escaping () async -> Void) -> some View {
        Button(action: {
            Task {
                await action()
            }
        }) {
            Label(title, systemImage: icon)
                .font(.caption)
                .fontWeight(.medium)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
        }
        .disabled(viewModel.isLoading)
    }

    // MARK: - Feedback & Loading
    private var feedbackSection: some View {
        VStack(spacing: 6) {
            if viewModel.isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(viewModel.statusMessage)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            } else if !viewModel.statusMessage.isEmpty {
                Text(viewModel.statusMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let error = viewModel.errorMessage {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(error)
                        .font(.footnote)
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.red.opacity(0.1))
                )
            }
        }
    }

    // MARK: - Token & Security Banner
    private var tokenSecurityBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TOKEN & VERIFICATION AUDIT")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(.secondary)

            infoRow(title: "fetch_token", value: viewModel.fetchTokenStatus, isWarning: true)
            infoRow(title: "Receipt", value: viewModel.receiptStatus, isWarning: false)
            infoRow(title: "JWS Transaction", value: viewModel.jwsStatus, isWarning: false)
            infoRow(title: "VerificationResult", value: viewModel.verificationResult, isWarning: false)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(UIColor.secondarySystemBackground))
        )
    }

    // MARK: - Panel 1: Unified Debug JSON
    private var unifiedJSONPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("FINAL DEBUG OUTPUT JSON")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: { viewModel.copyDebugJSON() }) {
                    Label(viewModel.copiedNotice ? "Copied" : "Copy", systemImage: viewModel.copiedNotice ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                }
            }

            ScrollView(.horizontal, showsIndicators: true) {
                Text(viewModel.unifiedDebugJSON.isEmpty ? "No debug JSON available yet." : viewModel.unifiedDebugJSON)
                    .font(.system(.caption2, design: .monospaced))
                    .padding()
                    .background(Color(UIColor.tertiarySystemBackground))
                    .cornerRadius(8)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(UIColor.secondarySystemBackground))
        )
    }

    // MARK: - Panel 2: Fields Inspector
    private var fieldsInspectorPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ALL EXTRACTED REVENUECAT FIELDS")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.secondary)

            Divider()

            Group {
                infoRow(title: "appUserID", value: viewModel.appUserID)
                infoRow(title: "originalAppUserId", value: viewModel.originalAppUserId)
                infoRow(title: "productIdentifier", value: viewModel.productIdentifier)
                infoRow(title: "packageIdentifier", value: viewModel.packageIdentifier)
                infoRow(title: "offeringIdentifier", value: viewModel.offeringIdentifier)
                infoRow(title: "store", value: viewModel.store)
                infoRow(title: "storeTransactionIdentifier", value: viewModel.storeTransactionIdentifier)
                infoRow(title: "transactionIdentifier", value: viewModel.transactionIdentifier)
                infoRow(title: "originalTransactionIdentifier", value: viewModel.originalTransactionIdentifier)
                infoRow(title: "purchaseDate", value: viewModel.purchaseDate)
                infoRow(title: "expirationDate", value: viewModel.expirationDate)
                infoRow(title: "isSandbox", value: viewModel.isSandbox)
            }

            Divider()

            Group {
                infoRow(title: "entitlement identifier", value: viewModel.entitlementIdentifier)
                infoRow(title: "entitlement isActive", value: viewModel.entitlementIsActive ? "true" : "false")
                infoRow(title: "latestPurchaseDate", value: viewModel.latestPurchaseDate)
                infoRow(title: "ownershipType", value: viewModel.ownershipType)
                infoRow(title: "periodType", value: viewModel.periodType)
                infoRow(title: "unsubscribeDetectedAt", value: viewModel.unsubscribeDetectedAt)
                infoRow(title: "billingIssueDetectedAt", value: viewModel.billingIssueDetectedAt)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(UIColor.secondarySystemBackground))
        )
    }

    // MARK: - Panel: Generic Code Dump
    private func codeDumpPanel(title: String, code: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.secondary)

            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                Text(code)
                    .font(.system(.caption2, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(UIColor.tertiarySystemBackground))
                    .cornerRadius(8)
            }
            .frame(maxHeight: 350)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(UIColor.secondarySystemBackground))
        )
    }

    private func infoRow(title: String, value: String, isWarning: Bool = false) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 140, alignment: .leading)
            Spacer()
            Text(value)
                .font(.caption)
                .fontWeight(isWarning ? .semibold : .regular)
                .foregroundColor(isWarning ? .orange : .primary)
                .multilineTextAlignment(.trailing)
        }
    }
}
