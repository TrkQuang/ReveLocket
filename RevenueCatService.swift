import Foundation
import RevenueCat

// MARK: - Entitlement Detail Model
public struct EntitlementDetailInfo: Codable {
    public var identifier: String
    public var isActive: Bool
    public var productIdentifier: String
    public var purchaseDate: String
    public var latestPurchaseDate: String?
    public var expirationDate: String?
    public var willRenew: Bool
    public var periodType: String
    public var ownershipType: String
    public var store: String
    public var isSandbox: Bool
    public var unsubscribeDetectedAt: String?
    public var billingIssueDetectedAt: String?
}

// MARK: - RevenueCat Customer Summary
public struct RevenueCatCustomerSummary: Codable {
    public var originalAppUserId: String
    public var activeSubscriptions: [String]
    public var purchasedProducts: [String]
    public var storeTransactionID: String?
    public var managementURL: String?
    public var requestDate: String
    public var entitlements: [String: EntitlementDetailInfo]
}

// MARK: - RevenueCat Service
public final class RevenueCatService {
    public static let shared = RevenueCatService()

    public static let defaultEnvironment: RevenueCatEnvironment = .xcodeLocalStoreKit
    public static let defaultPublicKey = "appl_JngFETzdodyLmCREOlwTUtXdQik"
    public static let defaultAppUserID = "kqdepzai"
    public static let defaultOfferingID = "locket_199"
    public static let defaultPackageID = "$rc_annual"
    public static let defaultProductID = "locket_1600_1y"
    public static let defaultEntitlementID = "Gold"

    private let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    public init() {}

    // MARK: - 1. Configure Purchases SDK
    public func configure(apiKey: String = defaultPublicKey, appUserID: String = defaultAppUserID) {
        Purchases.logLevel = .debug
        Purchases.configure(withAPIKey: apiKey, appUserID: appUserID)
        print("🚀 [RevenueCatService] Configured with Key: \(apiKey), User ID: \(appUserID)")
    }

    // MARK: - 2. Fetch & Validate Offering & Package (Section 3)
    public func fetchAndVerifyPackage(
        offeringID: String = defaultOfferingID,
        packageID: String = defaultPackageID,
        expectedProductID: String = defaultProductID
    ) async throws -> Package {
        print("📦 [RevenueCatService] Fetching offerings from RevenueCat...")
        let offerings = try await Purchases.shared.offerings()

        // Ưu tiên: offerings.current hoặc offerings.all[offeringID] hoặc offerings.all["default"]
        guard let targetOffering = offerings.current ?? offerings.all[offeringID] ?? offerings.all["default"] else {
            let available = offerings.all.keys.joined(separator: ", ")
            throw NSError(
                domain: "RevenueCatService",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "Không tìm thấy offering '\(offeringID)'. Offerings hiện có: [\(available)]"]
            )
        }

        guard let targetPackage = targetOffering.package(identifier: packageID) else {
            let availablePkgs = targetOffering.availablePackages.map { $0.identifier }.joined(separator: ", ")
            throw NSError(
                domain: "RevenueCatService",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "Không tìm thấy package '\(packageID)'. Packages hiện có: [\(availablePkgs)]"]
            )
        }

        let actualProductID = targetPackage.storeProduct.productIdentifier
        guard actualProductID == expectedProductID else {
            throw NSError(
                domain: "RevenueCatService",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "MISMATCH: Package '\(packageID)' trỏ đến product '\(actualProductID)', không khớp expected '\(expectedProductID)'!"]
            )
        }

        print("✅ [RevenueCatService] Package '\(packageID)' verified -> Product: '\(actualProductID)' (\(targetPackage.storeProduct.localizedPriceString))")
        return targetPackage
    }

    // MARK: - 3. Purchase Package
    public func purchase(package: Package) async throws -> (CustomerInfo, Bool) {
        print("🛒 [RevenueCatService] Bắt đầu purchase package: \(package.identifier)...")
        let result = try await Purchases.shared.purchase(package: package)
        if result.userCancelled {
            print("ℹ️ [RevenueCatService] Người dùng đã huỷ purchase.")
            return (result.customerInfo, true)
        }
        print("✅ [RevenueCatService] Purchase thành công qua RevenueCat.")
        return (result.customerInfo, false)
    }

    // MARK: - 4. Refresh CustomerInfo
    public func fetchCustomerInfo() async throws -> CustomerInfo {
        let info = try await Purchases.shared.customerInfo()
        return info
    }

    // MARK: - 5. Restore Purchases
    public func restorePurchases() async throws -> CustomerInfo {
        let info = try await Purchases.shared.restorePurchases()
        return info
    }

    // MARK: - 6. Extract Summary Data & store_transaction_id
    public func extractSummary(from info: CustomerInfo, targetProductID: String = defaultProductID) -> RevenueCatCustomerSummary {
        var entMap: [String: EntitlementDetailInfo] = [:]
        for (key, ent) in info.entitlements.all {
            entMap[key] = EntitlementDetailInfo(
                identifier: ent.identifier,
                isActive: ent.isActive,
                productIdentifier: ent.productIdentifier,
                purchaseDate: isoFormatter.string(from: ent.latestPurchaseDate ?? ent.originalPurchaseDate ?? Date()),
                latestPurchaseDate: ent.latestPurchaseDate.map { isoFormatter.string(from: $0) },
                expirationDate: ent.expirationDate.map { isoFormatter.string(from: $0) },
                willRenew: ent.willRenew,
                periodType: String(describing: ent.periodType),
                ownershipType: String(describing: ent.ownershipType),
                store: String(describing: ent.store),
                isSandbox: ent.isSandbox,
                unsubscribeDetectedAt: ent.unsubscribeDetectedAt.map { isoFormatter.string(from: $0) },
                billingIssueDetectedAt: ent.billingIssueDetectedAt.map { isoFormatter.string(from: $0) }
            )
        }

        // Trích xuất store_transaction_id từ rawData của CustomerInfo
        var detectedStoreTxID: String? = nil
        if let subscriberDict = info.rawData["subscriber"] as? [String: Any],
           let subscriptions = subscriberDict["subscriptions"] as? [String: Any] {
            if let targetSub = subscriptions[targetProductID] as? [String: Any],
               let storeTx = targetSub["store_transaction_id"] as? String {
                detectedStoreTxID = storeTx
            } else {
                for (_, val) in subscriptions {
                    if let sDict = val as? [String: Any], let storeTx = sDict["store_transaction_id"] as? String {
                        detectedStoreTxID = storeTx
                        break
                    }
                }
            }
        }

        // Fallback kiểm tra nonSubscriptionTransactions
        if detectedStoreTxID == nil {
            for tx in info.nonSubscriptionTransactions {
                detectedStoreTxID = tx.storeTransactionIdentifier
                break
            }
        }

        return RevenueCatCustomerSummary(
            originalAppUserId: info.originalAppUserId,
            activeSubscriptions: Array(info.activeSubscriptions),
            purchasedProducts: Array(info.allPurchasedProductIdentifiers),
            storeTransactionID: detectedStoreTxID,
            managementURL: info.managementURL?.absoluteString,
            requestDate: isoFormatter.string(from: info.requestDate),
            entitlements: entMap
        )
    }

    // MARK: - 7. Read-Only REST Subscriber Query (Debug Purpose Only - No Fake Receipts)
    public func fetchSubscriberREST(apiKey: String = defaultPublicKey, appUserID: String = defaultAppUserID) async -> [String: Any]? {
        guard let url = URL(string: "https://api.revenuecat.com/v1/subscribers/\(appUserID)") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("ios", forHTTPHeaderField: "X-Platform")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200 {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    return json
                }
            }
        } catch {
            print("ℹ️ [RevenueCatService] REST debug call failed: \(error.localizedDescription)")
        }
        return nil
    }
}
