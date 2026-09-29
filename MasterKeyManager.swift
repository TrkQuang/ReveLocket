import Foundation
import SwiftUI

// MARK: - 1. Environment & Source Types
public enum TransactionSource: String, Codable, CaseIterable {
    case appleProduction = "APPLE_PRODUCTION"
    case appleSandbox = "APPLE_SANDBOX"
    case xcodeLocalStoreKit = "XCODE_LOCAL_STOREKIT"
    case unknown = "UNKNOWN"

    public var displayName: String {
        switch self {
        case .appleProduction: return "Apple App Store (Production)"
        case .appleSandbox: return "Apple Sandbox / TestFlight"
        case .xcodeLocalStoreKit: return "Xcode Local StoreKit (.storekit)"
        case .unknown: return "Chưa xác định"
        }
    }

    public var isAppleValid: Bool {
        return self == .appleProduction || self == .appleSandbox
    }
}

// MARK: - 1.1 Config Flag (Requirement 12)
public enum PurchaseEnvironment: String, Codable, CaseIterable {
    case appleSandbox = "APPLE_SANDBOX"
    case appleProduction = "APPLE_PRODUCTION"
    case xcodeLocal = "XCODE_LOCAL"
}

// MARK: - 2. Final Verification Status
public enum MasterKeyStatus: String, Codable, CaseIterable {
    case verifiedActive = "VERIFIED_ACTIVE"
    case purchaseRequired = "PURCHASE_REQUIRED"
    case revenueCatSyncFailed = "REVENUECAT_SYNC_FAILED"
    case inactive = "INACTIVE"
    case transactionOwnerMismatch = "TRANSACTION_OWNER_MISMATCH"
    case localStoreKitVerified = "LOCAL_STOREKIT_VERIFIED"
    case localTestOnly = "LOCAL STOREKIT TEST ONLY"
    case appleSandboxPurchaseRequired = "APPLE_SANDBOX_PURCHASE_REQUIRED"
    case invalid = "INVALID"
    case invalidDebugData = "INVALID_DEBUG_DATA"
    case unverified = "UNVERIFIED"

    public var badgeColor: Color {
        switch self {
        case .verifiedActive: return .green
        case .purchaseRequired, .appleSandboxPurchaseRequired: return .orange
        case .revenueCatSyncFailed: return .orange
        case .inactive: return .gray
        case .transactionOwnerMismatch: return .red
        case .localStoreKitVerified, .localTestOnly: return .yellow
        case .invalid, .invalidDebugData: return .red
        case .unverified: return .gray
        }
    }

    public var badgeIcon: String {
        switch self {
        case .verifiedActive: return "checkmark.seal.fill"
        case .purchaseRequired, .appleSandboxPurchaseRequired: return "cart.badge.questionmark"
        case .revenueCatSyncFailed: return "arrow.triangle.2.circlepath.circle.fill"
        case .inactive: return "minus.circle.fill"
        case .transactionOwnerMismatch: return "person.crop.circle.badge.xmark"
        case .localStoreKitVerified: return "checkmark.shield.fill"
        case .localTestOnly: return "exclamationmark.triangle.fill"
        case .invalid, .invalidDebugData: return "xmark.octagon.fill"
        case .unverified: return "questionmark.circle"
        }
    }
}

// MARK: - 3. Master Fetch Token Source
public enum MasterTokenSource: String, Codable {
    case storeKitTransactionID = "STOREKIT_TRANSACTION_ID"
    case storeKitOriginalTransactionID = "STOREKIT_ORIGINAL_TRANSACTION_ID"
    case revenueCatStoreTransactionID = "REVENUECAT_STORE_TRANSACTION_ID"
    case apiExplicitField = "API_EXPLICIT_FIELD"
    case manualInput = "MANUAL_INPUT_LOOKUP_ONLY"
    case unavailable = "UNAVAILABLE"
}

// MARK: - 4. Master Key Item (Kho Khóa)
public struct MasterKeyItem: Identifiable, Codable {
    public let id: UUID
    public var name: String
    public var masterFetchToken: String
    public var originalTransactionID: String?
    public var tokenSource: MasterTokenSource
    public var transactionSource: TransactionSource
    public var status: MasterKeyStatus
    public var expirationDate: String
    public var productID: String
    public var appUserID: String
    public var isManualInput: Bool
    public var addedDate: Date

    // Helper Aliases & Owner Verification
    public var ownerAppUserID: String { return appUserID }
    public var transactionID: String { return masterFetchToken }

    public init(
        id: UUID = UUID(),
        name: String,
        masterFetchToken: String,
        originalTransactionID: String? = nil,
        tokenSource: MasterTokenSource,
        transactionSource: TransactionSource,
        status: MasterKeyStatus,
        expirationDate: String,
        productID: String = "locket_1600_1y",
        appUserID: String,
        isManualInput: Bool = false,
        addedDate: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.masterFetchToken = masterFetchToken
        self.originalTransactionID = originalTransactionID
        self.tokenSource = tokenSource
        self.transactionSource = transactionSource
        self.status = status
        self.expirationDate = expirationDate
        self.productID = productID
        self.appUserID = appUserID
        self.isManualInput = isManualInput
        self.addedDate = addedDate
    }
}

// MARK: - 5. Validation Result Model
public struct MasterKeyValidationResult: Codable {
    public var transactionVerified: Bool
    public var jwsAvailable: Bool
    public var productMatches: Bool
    public var notExpired: Bool
    public var notRevoked: Bool
    public var appleValid: Bool
    public var revenueCatActive: Bool
    public var finalStatus: MasterKeyStatus
    public var failureReasons: [String]

    public var isFullyActive: Bool {
        return finalStatus == .verifiedActive
    }
}

// MARK: - 6. Master Key Vault Manager
@MainActor
public final class MasterKeyVaultManager: ObservableObject {
    public static let shared = MasterKeyVaultManager()

    @Published public private(set) var savedKeys: [MasterKeyItem] = []

    private let storageKey = "Locket_Saved_Master_Keys_Vault"

    public init() {
        loadVault()
    }

    public func addKey(_ item: MasterKeyItem) {
        // Bảo vệ: Nếu là nhập tay hoặc chưa verify qua Live RevenueCat/StoreKit, không cho phép gán trạng thái VERIFIED ACTIVE
        var sanitizedItem = item
        if sanitizedItem.isManualInput && sanitizedItem.status == .verifiedActive {
            sanitizedItem.status = .invalid
            print("⚠️ [MasterKeyVault] Từ chối cấp quyền VERIFIED ACTIVE cho token nhập tay mà không có verified Apple transaction record.")
        }

        savedKeys.removeAll { $0.masterFetchToken == sanitizedItem.masterFetchToken && $0.appUserID == sanitizedItem.appUserID }
        savedKeys.insert(sanitizedItem, at: 0)
        persistVault()
    }

    public func removeKey(id: UUID) {
        savedKeys.removeAll { $0.id == id }
        persistVault()
    }

    public func clearAll() {
        savedKeys.removeAll()
        persistVault()
    }

    // Lọc theo App User ID - Tuyệt đối không cho phép cross-UID reuse
    public func keys(for appUserID: String) -> [MasterKeyItem] {
        return savedKeys.filter { $0.appUserID == appUserID }
    }

    private func persistVault() {
        if let data = try? JSONEncoder().encode(savedKeys) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func loadVault() {
        // Tuyệt đối KHÔNG hardcode bất kỳ token nào
        // Vault chỉ là cache lưu trữ các key người dùng đã xác thực, nếu trống thì để mảng rỗng
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let items = try? JSONDecoder().decode([MasterKeyItem].self, from: data) {
            self.savedKeys = items
        } else {
            self.savedKeys = []
        }
    }
}
