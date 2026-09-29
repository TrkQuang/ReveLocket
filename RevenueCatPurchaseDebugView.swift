import SwiftUI
import StoreKit
import RevenueCat

// MARK: - Main Application Entry Point
@main
struct RevenueCatPurchaseDebugApp: App {
    @StateObject private var viewModel = RevenueCatPurchaseDebugViewModel()

    var body: some Scene {
        WindowGroup {
            RevenueCatPurchaseDebugView(viewModel: viewModel)
        }
    }
}

// MARK: - Main Debug View
struct RevenueCatPurchaseDebugView: View {
    @ObservedObject var viewModel: RevenueCatPurchaseDebugViewModel

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    
                    // 1. Entitlement Status Header Banner
                    goldStatusBanner

                    // 2. Master Token Header (Requirement 10: Cyan values & Yellow Expiration)
                    masterTokenHeaderSection

                    // 3. Feedback & Notifications
                    feedbackBanner

                    // 4. PURCHASE Action Buttons
                    purchaseActionSection

                    // 5. CONFIG Section
                    configSection

                    // 6. MASTER TOKEN CANDIDATES Section (Requirement 11 & 14)
                    masterTokenCandidatesSection

                    // 7. REVENUECAT Section
                    revenueCatSection

                    // 8. STOREKIT Section
                    storeKitSection

                    // 9. SIGNED TRANSACTION Section
                    signedJWSSection

                    // 10. APP TRANSACTION Section (iOS 16+)
                    appTransactionSection

                    // 11. FETCH TOKEN Section
                    fetchTokenSection

                    // 12. DEBUG Section (Full Pretty JSON)
                    debugJSONSection

                    Spacer(minLength: 40)
                }
                .padding()
            }
            .navigationTitle("Locket Purchase Debug")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await viewModel.setupAndInitialLoad()
            }
        }
    }

    // MARK: - 1. Gold Status Banner
    private var goldStatusBanner: some View {
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

    // MARK: - 2. Master Token Header (Requirement 10: Cyan & Yellow)
    private var masterTokenHeaderSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Master Fetch Token
            VStack(alignment: .leading, spacing: 4) {
                Text("Master Fetch Token:")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                
                HStack {
                    Text(viewModel.masterFetchToken)
                        .font(.system(.title3, design: .monospaced))
                        .fontWeight(.bold)
                        .foregroundColor(.cyan)
                    
                    Spacer()
                    
                    if viewModel.masterFetchToken != "UNAVAILABLE" {
                        Button(action: {
                            UIPasteboard.general.string = viewModel.masterFetchToken
                        }) {
                            Image(systemName: "doc.on.doc")
                                .font(.caption)
                                .foregroundColor(.cyan)
                        }
                    }
                }
                
                Text("Source: \(viewModel.masterFetchTokenSource)")
                    .font(.caption2)
                    .foregroundColor(viewModel.masterFetchToken == "UNAVAILABLE" ? .secondary : .green)
            }
            
            Divider()
            
            // Public API Key RevenueCat
            VStack(alignment: .leading, spacing: 4) {
                Text("Public API Key RevenueCat:")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                
                Text(viewModel.revenueCatPublicKey)
                    .font(.system(.subheadline, design: .monospaced))
                    .fontWeight(.semibold)
                    .foregroundColor(.cyan)
                    .textSelection(.enabled)
            }
            
            Divider()
            
            // Hạn Dùng Máy Chủ
            VStack(alignment: .leading, spacing: 4) {
                Text("Hạn Dùng Máy Chủ:")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(Color(UIColor.secondaryLabel))
                
                Text(viewModel.serverExpirationDate)
                    .font(.system(.subheadline, design: .monospaced))
                    .fontWeight(.semibold)
                    .foregroundColor(.yellow)
                    .textSelection(.enabled)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(UIColor.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.cyan.opacity(0.35), lineWidth: 1.5)
        )
    }

    // MARK: - 2. Feedback Banner
    private var feedbackBanner: some View {
        VStack(spacing: 6) {
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

            if let notice = viewModel.clipboardNotice {
                Text(notice)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.green)
            }

            if let err = viewModel.errorMessage {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(err)
                        .font(.caption)
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.red.opacity(0.1)))
            }
        }
    }

    // MARK: - 3. PURCHASE Action Section
    private var purchaseActionSection: some View {
        cardContainer(title: "PURCHASE ACTIONS") {
            // Nút chính: Mua gói Annual
            Button(action: {
                Task {
                    await viewModel.purchaseAnnualPackage()
                }
            }) {
                HStack {
                    Image(systemName: "cart.fill")
                    Text("Purchase \(viewModel.productID) (\(viewModel.packageID))")
                        .fontWeight(.bold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(viewModel.loadedPackage == nil || !viewModel.packageVerified || viewModel.isLoading ? Color.gray : Color.blue)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(viewModel.loadedPackage == nil || !viewModel.packageVerified || viewModel.isLoading)

            // Các nút phụ: Fetch Offering, Restore, Refresh
            HStack(spacing: 8) {
                actionBtn(title: "Fetch Offering", icon: "arrow.triangle.2.circlepath") {
                    await viewModel.fetchTargetOffering()
                }

                actionBtn(title: "Restore", icon: "arrow.counterclockwise") {
                    await viewModel.restorePurchases()
                }

                actionBtn(title: "Refresh Info", icon: "person.crop.circle.badge.checkmark") {
                    await viewModel.refreshCustomerInfo()
                    await viewModel.fetchLatestStoreKitTransaction()
                    await viewModel.inspectCurrentEntitlements()
                    viewModel.buildFinalDebugJSON()
                }
            }
        }
    }

    // MARK: - 4. CONFIG Section
    private var configSection: some View {
        cardContainer(title: "CONFIG") {
            itemRow(title: "App User ID", value: viewModel.appUserID)
            itemRow(title: "Offering Target", value: viewModel.offeringID)
            itemRow(title: "Package Target", value: viewModel.packageID)
            itemRow(title: "Product ID Expected", value: viewModel.productID)
            itemRow(title: "RevenueCat Public Key", value: viewModel.revenueCatPublicKey)
            
            Divider()

            itemRow(title: "Package Match Status", value: viewModel.packageVerificationMessage, highlight: viewModel.packageVerified)
        }
    }

    // MARK: - 5. MASTER TOKEN CANDIDATES Section (Requirement 11 & 14)
    private var masterTokenCandidatesSection: some View {
        cardContainer(title: "MASTER TOKEN CANDIDATES") {
            VStack(alignment: .leading, spacing: 8) {
                candidateItem(
                    name: "transaction.id",
                    val: viewModel.masterTokenCandidates["transaction.id"] ?? viewModel.storeKitTransactionID,
                    isNumeric: true
                )
                candidateItem(
                    name: "originalTransactionID",
                    val: viewModel.masterTokenCandidates["originalTransactionID"] ?? viewModel.storeKitOriginalTransactionID,
                    isNumeric: true
                )
                candidateItem(
                    name: "RevenueCat store_transaction_id",
                    val: viewModel.masterTokenCandidates["RevenueCat store_transaction_id"] ?? viewModel.rcStoreTransactionID,
                    isNumeric: true
                )
                candidateItem(
                    name: "appTransactionID",
                    val: viewModel.masterTokenCandidates["appTransactionID"] ?? (viewModel.appTxBundleID != "-" ? viewModel.appTxBundleID : "nil")
                )
                candidateItem(
                    name: "signed JWS",
                    val: viewModel.masterTokenCandidates["signed JWS"] ?? (viewModel.signedTransactionJWS.isEmpty ? "nil" : "\(viewModel.signedTransactionJWS.prefix(32))...")
                )
                candidateItem(
                    name: "fetch_token",
                    val: viewModel.masterTokenCandidates["fetch_token"] ?? "null (NOT EXPOSED BY REVENUECAT PUBLIC SDK)"
                )

                Divider()
                    .padding(.vertical, 2)

                candidateItem(
                    name: "selected master_fetch_token",
                    val: viewModel.masterFetchToken,
                    isHighlight: true,
                    isNumeric: viewModel.masterFetchToken != "UNAVAILABLE"
                )

                HStack(alignment: .top) {
                    Text("Selected Master Fetch Token Source:")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(viewModel.masterFetchTokenSource)
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(viewModel.masterFetchToken == "UNAVAILABLE" ? .orange : .green)
                        .multilineTextAlignment(.trailing)
                }
                .padding(.top, 2)
            }
        }
    }

    private func candidateItem(name: String, val: String, isHighlight: Bool = false, isNumeric: Bool = false) -> some View {
        HStack(alignment: .top) {
            Text("- \(name):")
                .font(.caption2)
                .foregroundColor(.secondary)
                .frame(width: 170, alignment: .leading)
            Spacer()
            Text(val)
                .font(.system(.caption2, design: isNumeric ? .monospaced : .default))
                .fontWeight(isHighlight ? .bold : .regular)
                .foregroundColor(isHighlight ? .cyan : (val == "nil" || val.contains("null") ? .gray : .primary))
                .multilineTextAlignment(.trailing)
        }
    }

    // MARK: - 5. REVENUECAT Section
    private var revenueCatSection: some View {
        cardContainer(title: "REVENUECAT") {
            itemRow(title: "Customer ID", value: viewModel.rcOriginalAppUserId)
            itemRow(title: "Active Subscription", value: viewModel.rcActiveSubscriptions.isEmpty ? "None" : viewModel.rcActiveSubscriptions.joined(separator: ", "))
            itemRow(title: "Purchased Products", value: viewModel.rcAllPurchasedProducts.isEmpty ? "None" : viewModel.rcAllPurchasedProducts.joined(separator: ", "))
            itemRow(title: "Entitlement Gold", value: viewModel.isGoldActive ? "ACTIVE" : "INACTIVE", highlight: viewModel.isGoldActive)
            itemRow(title: "Request Date", value: viewModel.rcRequestDate)
            itemRow(title: "Management URL", value: viewModel.rcManagementURL)
        }
    }

    // MARK: - 6. STOREKIT Section
    private var storeKitSection: some View {
        cardContainer(title: "STOREKIT 2 TRANSACTION") {
            itemRow(title: "Verified", value: viewModel.storeKitVerified ? "VERIFIED (Apple StoreKit 2)" : "UNVERIFIED", highlight: viewModel.storeKitVerified)
            itemRow(title: "Transaction ID", value: viewModel.storeKitTransactionID)
            itemRow(title: "Original Transaction ID", value: viewModel.storeKitOriginalTransactionID)
            itemRow(title: "Product ID", value: viewModel.storeKitProductID)
            itemRow(title: "Product Type", value: viewModel.storeKitProductType)
            itemRow(title: "Environment", value: viewModel.storeKitEnvironment)
            itemRow(title: "Purchase Date", value: viewModel.storeKitPurchaseDate)
            itemRow(title: "Original Purchase Date", value: viewModel.storeKitOriginalPurchaseDate)
            itemRow(title: "Expiration Date", value: viewModel.storeKitExpirationDate)
            itemRow(title: "Revocation Date", value: viewModel.storeKitRevocationDate)
            itemRow(title: "Revocation Reason", value: viewModel.storeKitRevocationReason)
            itemRow(title: "Is Upgraded", value: viewModel.storeKitIsUpgraded)
            itemRow(title: "Ownership Type", value: viewModel.storeKitOwnershipType)
            itemRow(title: "App Account Token", value: viewModel.storeKitAppAccountToken)
        }
    }

    // MARK: - 7. SIGNED TRANSACTION Section
    private var signedJWSSection: some View {
        cardContainer(title: "SIGNED TRANSACTION JWS (StoreKit 2)") {
            Text("Raw StoreKit 2 JWS Compact Serialization được lấy trực tiếp từ `VerificationResult<Transaction>.jwsRepresentation` do Apple ký.")
                .font(.caption2)
                .foregroundColor(.secondary)

            HStack {
                Button(action: { viewModel.showFullJWS.toggle() }) {
                    Label(viewModel.showFullJWS ? "Hide JWS" : "Show Full JWS", systemImage: viewModel.showFullJWS ? "eye.slash" : "eye")
                        .font(.caption)
                }

                Spacer()

                Button(action: { viewModel.copySignedJWS() }) {
                    Label("Copy JWS", systemImage: "doc.on.doc.fill")
                        .font(.caption)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 10)
                        .background(Color.blue.opacity(0.15))
                        .foregroundColor(.blue)
                        .cornerRadius(6)
                }
                .disabled(viewModel.signedTransactionJWS.isEmpty)
            }

            if viewModel.showFullJWS && !viewModel.signedTransactionJWS.isEmpty {
                ScrollView(.horizontal, showsIndicators: true) {
                    Text(viewModel.signedTransactionJWS)
                        .font(.system(.caption2, design: .monospaced))
                        .padding(8)
                        .background(Color(UIColor.tertiarySystemBackground))
                        .cornerRadius(6)
                        .textSelection(.enabled)
                }
            } else if viewModel.signedTransactionJWS.isEmpty {
                Text("Chưa có StoreKit 2 transaction nào được load.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else {
                Text(String(viewModel.signedTransactionJWS.prefix(60)) + "...")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - 8. APP TRANSACTION Section (iOS 16+)
    private var appTransactionSection: some View {
        cardContainer(title: "APP TRANSACTION (StoreKit 2)") {
            itemRow(title: "Verified", value: viewModel.appTxIsVerified ? "VERIFIED" : "UNVERIFIED", highlight: viewModel.appTxIsVerified)
            itemRow(title: "Bundle ID", value: viewModel.appTxBundleID)
            itemRow(title: "App Version", value: viewModel.appTxAppVersion)
            itemRow(title: "Original Version", value: viewModel.appTxOriginalAppVersion)
            itemRow(title: "Original Purchase Date", value: viewModel.appTxOriginalPurchaseDate)
            itemRow(title: "Environment", value: viewModel.appTxEnvironment)
            
            if !viewModel.appTransactionJWS.isEmpty {
                Divider()
                Text("AppTransaction JWS: " + String(viewModel.appTransactionJWS.prefix(50)) + "...")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - 9. FETCH TOKEN Section
    private var fetchTokenSection: some View {
        cardContainer(title: "FETCH TOKEN AUDIT") {
            itemRow(title: "fetch_token", value: "null", isWarning: true)
            itemRow(title: "fetch_token_status", value: viewModel.fetchTokenStatus, isWarning: true)
            
            Text("Lưu ý: RevenueCat Public iOS SDK KHÔNG expose trường raw internal fetch_token gửi qua mạng. Token mã hoá thật duy nhất có thể trích xuất chính thức từ StoreKit 2 là `signed_transaction_jws` ở trên.")
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.top, 2)
        }
    }

    // MARK: - 10. DEBUG Section
    private var debugJSONSection: some View {
        cardContainer(title: "DEBUG (Full Pretty JSON)") {
            HStack {
                Text("Dữ liệu JSON hoàn chỉnh sẵn sàng trích xuất:")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: { viewModel.copyDebugJSON() }) {
                    Label("Copy Debug JSON", systemImage: "doc.on.doc")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
            }

            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                Text(viewModel.fullDebugJSON.isEmpty ? "Chưa có JSON." : viewModel.fullDebugJSON)
                    .font(.system(.caption2, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color(UIColor.tertiarySystemBackground))
                    .cornerRadius(8)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 280)
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

    private func itemRow(title: String, value: String, highlight: Bool = false, isWarning: Bool = false) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
                .frame(width: 140, alignment: .leading)
            Spacer()
            Text(value)
                .font(.caption2)
                .fontWeight(highlight || isWarning ? .semibold : .regular)
                .foregroundColor(highlight ? .green : (isWarning ? .orange : .primary))
                .multilineTextAlignment(.trailing)
        }
    }

    private func actionBtn(title: String, icon: String, action: @escaping () async -> Void) -> some View {
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
                .background(Color(UIColor.tertiarySystemBackground))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
        }
        .disabled(viewModel.isLoading)
    }
}
