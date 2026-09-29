import SwiftUI
import StoreKit
import RevenueCat

// MARK: - Main Application Entry
@main
struct MasterKeyDebugApp: App {
    @StateObject private var viewModel = MasterKeyDebugViewModel()

    var body: some Scene {
        WindowGroup {
            MasterKeyDebugView(viewModel: viewModel)
        }
    }
}

// MARK: - Main Master Key Debug View
struct MasterKeyDebugView: View {
    @ObservedObject var viewModel: MasterKeyDebugViewModel
    @ObservedObject var vaultManager = MasterKeyVaultManager.shared

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    
                    // Notice & Feedback Banner
                    if let notice = viewModel.clipboardNotice {
                        Text(notice)
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(.green)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity)
                            .background(Color.green.opacity(0.15))
                            .cornerRadius(8)
                    }

                    if let err = viewModel.errorMessage {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text(err)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                    }

                    // Main Two-Panel Layout (Left: Active Key & Diagnostic / Right: Key Vault & Actions)
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 20) {
                            leftPanel
                                .frame(maxWidth: .infinity)
                            rightPanel
                                .frame(maxWidth: .infinity)
                        }
                        VStack(spacing: 20) {
                            leftPanel
                            rightPanel
                        }
                    }

                    // Candidates, Certificate Checklist & Full Debug JSON Section
                    candidatesDebugSection
                    certificateChecklistSection
                    rawDebugJSONSection

                    Spacer(minLength: 40)
                }
                .padding()
            }
            .navigationTitle("MASTER STOREKIT 2 KEY MANAGER")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        Task { await viewModel.refreshAll() }
                    }) {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .task {
                await viewModel.initialLoad()
            }
            .sheet(isPresented: $viewModel.isDiagnosticSheetPresented) {
                diagnosticSheet
            }
        }
    }

    // =========================================================================
    // MARK: - LEFT PANEL (MASTER STOREKIT 2 KEY ĐANG KÍCH HOẠT)
    // =========================================================================
    private var leftPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            
            // Header: Title & Status Badge
            HStack {
                Text("MASTER STOREKIT 2 KEY ĐANG KÍCH HOẠT")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                Spacer()
                statusBadge(viewModel.finalStatus)
            }

            Divider()

            // Card: Thời Gian Còn Lại Của Token Master
            VStack(alignment: .leading, spacing: 12) {
                Text("THỜI GIAN CÒN LẠI CỦA TOKEN MASTER")
                    .font(.caption2)
                    .fontWeight(.heavy)
                    .foregroundColor(.secondary)

                // Master Fetch Token
                VStack(alignment: .leading, spacing: 4) {
                    Text("Master Fetch Token:")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)

                    HStack {
                        Text(viewModel.masterFetchTokenDisplay)
                            .font(.system(.title3, design: .monospaced))
                            .fontWeight(.bold)
                            .foregroundColor(.cyan)
                            .textSelection(.enabled)

                        Spacer()

                        Button(action: { viewModel.copyMasterToken() }) {
                            Image(systemName: "doc.on.doc")
                                .font(.caption)
                                .foregroundColor(.cyan)
                        }
                        .disabled(viewModel.masterFetchToken == nil)
                    }

                    Text("Token Source: \(viewModel.masterFetchTokenSource.rawValue)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    Text("Transaction Source: \(viewModel.transactionSource.rawValue)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(viewModel.transactionSource.isAppleValid ? .green : .orange)
                }

                Divider()

                // Public API Key RevenueCat
                VStack(alignment: .leading, spacing: 4) {
                    Text("Public API Key RevenueCat:")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)

                    Text(viewModel.revenueCatPublicKey)
                        .font(.system(.footnote, design: .monospaced))
                        .fontWeight(.semibold)
                        .foregroundColor(.cyan)
                        .textSelection(.enabled)
                }

                Divider()

                // Hạn Dùng Máy Chủ
                VStack(alignment: .leading, spacing: 4) {
                    Text("Hạn Dùng Máy Chủ:")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)

                    Text(viewModel.serverExpirationDate)
                        .font(.system(.footnote, design: .monospaced))
                        .fontWeight(.bold)
                        .foregroundColor(.yellow)
                        .textSelection(.enabled)

                    if let warn = viewModel.expirationMismatchWarning {
                        Text(warn)
                            .font(.system(size: 10))
                            .foregroundColor(.orange)
                    }
                }

                Divider()

                // Product & UID
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Product:")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(viewModel.productID)
                            .font(.caption2)
                            .fontWeight(.bold)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("UID:")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(viewModel.appUserID)
                            .font(.caption2)
                            .fontWeight(.bold)
                    }
                }
            }
            .padding()
            .background(Color(UIColor.tertiarySystemBackground))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(viewModel.finalStatus.badgeColor.opacity(0.4), lineWidth: 1.5)
            )
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(16)
    }

    // =========================================================================
    // MARK: - RIGHT PANEL (THÊM MASTER KEY MỚI VÀO KHO & ACTIONS)
    // =========================================================================
    private var rightPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("THÊM MASTER KEY MỚI VÀO KHO")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.secondary)

            // Form Nhập Key Mới
            VStack(spacing: 8) {
                TextField("Tên Key (ví dụ: Locket Gold Pro)", text: $viewModel.manualKeyName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .font(.caption)

                TextField("Mã Fetch Token / Transaction ID (StoreKit 2)", text: $viewModel.manualTokenInput)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .font(.system(.caption, design: .monospaced))

                TextField("Ngày hết hạn (ISO-8601 hoặc YYYY-MM-DD)", text: $viewModel.manualExpirationDate)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .font(.caption)

                if let notice = viewModel.manualInputNotice {
                    Text(notice)
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Divider()

            // Các Nút Hành Động (Requirements 13, 16)
            VStack(spacing: 8) {
                // Nút Purchase
                Button(action: {
                    Task { await viewModel.purchaseStoreKit() }
                }) {
                    HStack {
                        Image(systemName: "cart.fill")
                        Text("Purchase StoreKit (\(viewModel.packageID))")
                            .fontWeight(.bold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(viewModel.verifiedPackage == nil || viewModel.isLoading ? Color.gray : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .disabled(viewModel.verifiedPackage == nil || viewModel.isLoading)

                HStack(spacing: 8) {
                    actionButton(title: "Refresh Transaction", icon: "arrow.clockwise") {
                        Task { await viewModel.refreshAll() }
                    }
                    actionButton(title: "Test Thử Với Apple", icon: "checkmark.shield.fill", color: .purple) {
                        viewModel.testWithApple()
                    }
                }

                HStack(spacing: 8) {
                    actionButton(title: "Copy Master Token", icon: "doc.on.doc", color: .cyan) {
                        viewModel.copyMasterToken()
                    }
                    actionButton(title: "Copy Signed JWS", icon: "key.fill", color: .indigo) {
                        viewModel.copySignedJWS()
                    }
                }

                HStack(spacing: 8) {
                    actionButton(title: "Copy Debug JSON", icon: "curlybraces", color: .teal) {
                        viewModel.copyDebugJSON()
                    }
                    actionButton(title: "Thêm Vào Kho Khóa", icon: "plus.circle.fill", color: .green) {
                        if !viewModel.manualTokenInput.isEmpty {
                            viewModel.addManualKeyToVault()
                        } else {
                            viewModel.addCurrentKeyToVault()
                        }
                    }
                }
            }

            // Danh sách Keys đã lưu trong kho
            if !vaultManager.savedKeys.isEmpty {
                Divider()
                Text("KHO KHÓA ĐÃ LƯU (\(vaultManager.savedKeys.count))")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)

                ForEach(vaultManager.savedKeys.prefix(3)) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name)
                                .font(.caption2)
                                .fontWeight(.bold)
                            Text(item.masterFetchToken)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.cyan)
                        }
                        Spacer()
                        statusBadge(item.status, isSmall: true)
                    }
                    .padding(6)
                    .background(Color(UIColor.tertiarySystemBackground))
                    .cornerRadius(6)
                }
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(16)
    }

    // =========================================================================
    // MARK: - MASTER TOKEN CANDIDATES DEBUG SECTION (Requirement 11 & 14)
    // =========================================================================
    private var candidatesDebugSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("MASTER TOKEN CANDIDATES")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.secondary)

            Divider()

            VStack(spacing: 6) {
                candidateRow(label: "StoreKit transaction.id:", value: viewModel.candidates["StoreKit transaction.id"] ?? "-")
                candidateRow(label: "StoreKit originalID:", value: viewModel.candidates["StoreKit originalID"] ?? "-")
                candidateRow(label: "RevenueCat store_transaction_id:", value: viewModel.candidates["RevenueCat store_transaction_id"] ?? "-")
                candidateRow(label: "AppTransaction ID:", value: viewModel.candidates["AppTransaction ID"] ?? "-")
                candidateRow(label: "Signed Transaction JWS:", value: viewModel.candidates["Signed Transaction JWS"] ?? "-")
                candidateRow(label: "AppTransaction JWS:", value: viewModel.candidates["AppTransaction JWS"] ?? "-")

                Divider().padding(.vertical, 2)

                candidateRow(label: "Selected Master Fetch Token:", value: viewModel.masterFetchTokenDisplay, isHighlight: true)
                candidateRow(label: "Selected Source:", value: viewModel.masterFetchTokenSource.rawValue)
                candidateRow(label: "Transaction Source:", value: viewModel.transactionSource.rawValue)
                candidateRow(label: "Final Status:", value: viewModel.finalStatus.rawValue, isStatus: true)
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(16)
    }

    // =========================================================================
    // MARK: - REVENUECAT STOREKIT TEST CERTIFICATE CHECKLIST (Requirement C)
    // =========================================================================
    private var certificateChecklistSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundColor(.blue)
                Text("REVENUECAT STOREKIT TEST CERTIFICATE (HƯỚNG DẪN SYNC)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                checkItem(step: "1", text: "Mở file LocketGold.storekit trong Xcode.")
                checkItem(step: "2", text: "Trên thanh menu chọn Editor -> Save Public Certificate...")
                checkItem(step: "3", text: "Export file chứng chỉ (.cer / .pem) về máy.")
                checkItem(step: "4", text: "Vào RevenueCat Dashboard: Project Settings -> Apps -> App Store -> StoreKit testing framework -> Upload public certificate.")
                checkItem(step: "5", text: "Đảm bảo product 'locket_1600_1y' tồn tại trong RevenueCat Product Catalog.")
                checkItem(step: "6", text: "Đảm bảo package 'locket_199' / '$rc_annual' map đúng 'locket_1600_1y'.")
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(16)
    }

    private func checkItem(step: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(step)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.blue))
            Text(text)
                .font(.caption2)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // =========================================================================
    // MARK: - RAW DEBUG JSON VIEWER (Requirement 17)
    // =========================================================================
    private var rawDebugJSONSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("RAW DEBUG JSON (Requirement 17)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: { viewModel.copyDebugJSON() }) {
                    Label("Copy JSON", systemImage: "doc.on.doc")
                        .font(.caption2)
                }
            }

            Divider()

            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                Text(viewModel.rawDebugJSON.isEmpty ? "Chưa có JSON." : viewModel.rawDebugJSON)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color(UIColor.tertiarySystemBackground))
                    .cornerRadius(8)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 260)
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(16)
    }

    // =========================================================================
    // MARK: - DIAGNOSTIC MODAL SHEET (Requirement 13: "Test Thử Với Apple")
    // =========================================================================
    private var diagnosticSheet: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("KẾT QUẢ KIỂM THỬ VỚI APPLE")
                            .font(.headline)
                            .fontWeight(.bold)
                        Spacer()
                        statusBadge(viewModel.finalStatus)
                    }

                    Divider()

                    diagRow(title: "Master Fetch Token", value: viewModel.masterFetchTokenDisplay, isCyan: true)
                    diagRow(title: "Token Source", value: viewModel.masterFetchTokenSource.rawValue)
                    diagRow(title: "Transaction ID", value: viewModel.storeKitDetails?.transactionID ?? "-")
                    diagRow(title: "Original Transaction ID", value: viewModel.storeKitDetails?.originalTransactionID ?? "-")
                    diagRow(title: "Product", value: viewModel.productID)
                    diagRow(title: "Environment", value: viewModel.storeKitDetails?.environment ?? viewModel.transactionSource.rawValue)
                    diagRow(title: "Expiration", value: viewModel.serverExpirationDate)
                    diagRow(title: "Signed JWS", value: viewModel.signedTransactionJWS.isEmpty ? "MISSING" : "AVAILABLE")
                    diagRow(title: "Verified", value: viewModel.storeKitDetails?.isVerified == true ? "YES" : "NO")
                    diagRow(title: "Apple-valid", value: viewModel.transactionSource.isAppleValid ? "YES" : "NO")
                    diagRow(title: "RevenueCat Active", value: viewModel.isGoldActive ? "YES" : "NO")

                    Divider()

                    Text("Final Status: \(viewModel.finalStatus.rawValue)")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(viewModel.finalStatus.badgeColor)

                    if let reasons = viewModel.validationResult?.failureReasons, !reasons.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Chi tiết phân tích / lý do không đạt:")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.red)

                            ForEach(reasons, id: \.self) { reason in
                                Text("• \(reason)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(10)
                        .background(Color.red.opacity(0.08))
                        .cornerRadius(8)
                    }
                }
                .padding()
            }
            .navigationTitle("Test Thử Với Apple")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Đóng") {
                        viewModel.isDiagnosticSheetPresented = false
                    }
                }
            }
        }
    }

    // =========================================================================
    // MARK: - Reusable UI Helpers
    // =========================================================================
    private func statusBadge(_ status: MasterKeyStatus, isSmall: Bool = false) -> some View {
        HStack(spacing: 4) {
            Image(systemName: status.badgeIcon)
            Text(status.rawValue)
                .fontWeight(.bold)
        }
        .font(isSmall ? .system(size: 10) : .caption)
        .padding(.vertical, isSmall ? 3 : 5)
        .padding(.horizontal, isSmall ? 6 : 10)
        .background(status.badgeColor.opacity(0.18))
        .foregroundColor(status.badgeColor)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(status.badgeColor.opacity(0.5), lineWidth: 1)
        )
    }

    private func candidateRow(label: String, value: String, isHighlight: Bool = false, isStatus: Bool = false) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
                .frame(width: 180, alignment: .leading)
            Spacer()
            Text(value)
                .font(.system(.caption2, design: .monospaced))
                .fontWeight(isHighlight || isStatus ? .bold : .regular)
                .foregroundColor(isHighlight ? .cyan : (isStatus ? viewModel.finalStatus.badgeColor : .primary))
                .multilineTextAlignment(.trailing)
        }
    }

    private func diagRow(title: String, value: String, isCyan: Bool = false) -> some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.bold)
                .foregroundColor(isCyan ? .cyan : .primary)
        }
        .padding(.vertical, 2)
    }

    private func actionButton(title: String, icon: String, color: Color = .blue, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.system(size: 11, weight: .semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .cornerRadius(8)
        }
    }
}
