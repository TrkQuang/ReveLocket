import Foundation
import StoreKit

// MARK: - StoreKit Transaction Details Model
public struct StoreKitTransactionDetails: Codable {
    public var isVerified: Bool
    public var verificationError: String?
    public var transactionID: String
    public var originalTransactionID: String
    public var productID: String
    public var productType: String
    public var purchaseDate: String
    public var originalPurchaseDate: String
    public var expirationDate: String?
    public var revocationDate: String?
    public var revocationReason: String?
    public var isUpgraded: Bool
    public var ownershipType: String
    public var environment: String
    public var appAccountToken: String?
    public var transactionSource: TransactionSource
    public var signedTransactionJWS: String
}

// MARK: - App Transaction Details Model
public struct AppTransactionDetails: Codable {
    public var isVerified: Bool
    public var verificationError: String?
    public var bundleID: String
    public var appVersion: String
    public var originalAppVersion: String
    public var originalPurchaseDate: String
    public var environment: String
    public var signedAppTransactionJWS: String
}

// MARK: - StoreKit 2 Transaction Service
public final class StoreKitTransactionService {
    public static let shared = StoreKitTransactionService()

    private let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    public init() {}

    // MARK: - 1. Fetch Latest Transaction for Product
    public func fetchLatestTransaction(for productID: String) async -> (VerificationResult<Transaction>?, StoreKitTransactionDetails?) {
        print("🍏 [StoreKitTransactionService] Calling Transaction.latest(for: \(productID))...")
        guard let verificationResult = await Transaction.latest(for: productID) else {
            print("ℹ️ [StoreKitTransactionService] No transaction found for product: \(productID)")
            return (nil, nil)
        }

        let jwsString = verificationResult.jwsRepresentation
        print("🔐 [StoreKitTransactionService] Raw JWS Representation obtained (length: \(jwsString.count) chars)")

        switch verificationResult {
        case .verified(let transaction):
            let source = detectSource(for: transaction)
            let details = buildDetails(from: transaction, isVerified: true, error: nil, jws: jwsString, source: source)
            print("✅ [StoreKitTransactionService] Verified Transaction ID: \(transaction.id), Source: \(source.rawValue)")
            return (verificationResult, details)

        case .unverified(let transaction, let error):
            let source = detectSource(for: transaction)
            let details = buildDetails(from: transaction, isVerified: false, error: error.localizedDescription, jws: jwsString, source: source)
            print("❌ [StoreKitTransactionService] Unverified Transaction ID: \(transaction.id), Error: \(error.localizedDescription)")
            return (verificationResult, details)
        }
    }

    // MARK: - 2. Inspect All Current Entitlements
    public func inspectCurrentEntitlements(targetProductID: String) async -> (VerificationResult<Transaction>?, StoreKitTransactionDetails?) {
        print("🔍 [StoreKitTransactionService] Iterating Transaction.currentEntitlements...")
        for await verificationResult in Transaction.currentEntitlements {
            let jws = verificationResult.jwsRepresentation
            switch verificationResult {
            case .verified(let transaction):
                if transaction.productID == targetProductID {
                    let source = detectSource(for: transaction)
                    let details = buildDetails(from: transaction, isVerified: true, error: nil, jws: jws, source: source)
                    print("✅ [StoreKitTransactionService] Matching Current Entitlement: \(transaction.productID), ID: \(transaction.id)")
                    return (verificationResult, details)
                }
            case .unverified(let transaction, let error):
                if transaction.productID == targetProductID {
                    let source = detectSource(for: transaction)
                    let details = buildDetails(from: transaction, isVerified: false, error: error.localizedDescription, jws: jws, source: source)
                    print("⚠️ [StoreKitTransactionService] Matching Unverified Entitlement: \(transaction.productID)")
                    return (verificationResult, details)
                }
            }
        }
        return (nil, nil)
    }

    // MARK: - 3. Fetch AppTransaction (iOS 16+)
    public func fetchAppTransaction() async -> (VerificationResult<AppTransaction>?, AppTransactionDetails?) {
        if #available(iOS 16.0, *) {
            do {
                let verificationResult = try await AppTransaction.shared
                let jws = verificationResult.jwsRepresentation

                switch verificationResult {
                case .verified(let appTx):
                    let envStr: String
                    switch appTx.environment {
                    case .production: envStr = "Production"
                    case .sandbox: envStr = "Sandbox"
                    case .xcode: envStr = "Xcode"
                    default: envStr = String(describing: appTx.environment)
                    }

                    let details = AppTransactionDetails(
                        isVerified: true,
                        verificationError: nil,
                        bundleID: appTx.bundleID,
                        appVersion: appTx.appVersion,
                        originalAppVersion: appTx.originalAppVersion,
                        originalPurchaseDate: isoFormatter.string(from: appTx.originalPurchaseDate),
                        environment: envStr,
                        signedAppTransactionJWS: jws
                    )
                    print("✅ [StoreKitTransactionService] AppTransaction Verified: \(appTx.bundleID), Environment: \(envStr)")
                    return (verificationResult, details)

                case .unverified(let appTx, let error):
                    let details = AppTransactionDetails(
                        isVerified: false,
                        verificationError: error.localizedDescription,
                        bundleID: appTx.bundleID,
                        appVersion: appTx.appVersion,
                        originalAppVersion: appTx.originalAppVersion,
                        originalPurchaseDate: isoFormatter.string(from: appTx.originalPurchaseDate),
                        environment: String(describing: appTx.environment),
                        signedAppTransactionJWS: jws
                    )
                    print("⚠️ [StoreKitTransactionService] AppTransaction Unverified: \(error.localizedDescription)")
                    return (verificationResult, details)
                }
            } catch {
                print("ℹ️ [StoreKitTransactionService] AppTransaction.shared not available on this configuration: \(error.localizedDescription)")
            }
        }
        return (nil, nil)
    }

    // MARK: - 4. Detect Transaction Source (4 Environments)
    public func detectSource(for transaction: Transaction) -> TransactionSource {
        if #available(iOS 16.0, *) {
            switch transaction.environment {
            case .production:
                return .appleProduction
            case .sandbox:
                return .appleSandbox
            case .xcode:
                return .xcodeLocalStoreKit
            default:
                let desc = String(describing: transaction.environment).lowercased()
                if desc.contains("xcode") || desc.contains("local") {
                    return .xcodeLocalStoreKit
                } else if desc.contains("sandbox") {
                    return .appleSandbox
                } else if desc.contains("prod") {
                    return .appleProduction
                }
            }
        }

        return .appleSandbox
    }

    // MARK: - Private Helpers
    private func buildDetails(
        from transaction: Transaction,
        isVerified: Bool,
        error: String?,
        jws: String,
        source: TransactionSource
    ) -> StoreKitTransactionDetails {
        let expString = transaction.expirationDate.map { isoFormatter.string(from: $0) }
        let revString = transaction.revocationDate.map { isoFormatter.string(from: $0) }
        let envString: String
        if #available(iOS 16.0, *) {
            envString = String(describing: transaction.environment)
        } else {
            envString = source.rawValue
        }

        return StoreKitTransactionDetails(
            isVerified: isVerified,
            verificationError: error,
            transactionID: String(transaction.id),
            originalTransactionID: String(transaction.originalID),
            productID: transaction.productID,
            productType: String(describing: transaction.productType),
            purchaseDate: isoFormatter.string(from: transaction.purchaseDate),
            originalPurchaseDate: isoFormatter.string(from: transaction.originalPurchaseDate),
            expirationDate: expString,
            revocationDate: revString,
            revocationReason: transaction.revocationReason.map { String(describing: $0) },
            isUpgraded: transaction.isUpgraded,
            ownershipType: String(describing: transaction.ownershipType),
            environment: envString,
            appAccountToken: transaction.appAccountToken?.uuidString,
            transactionSource: source,
            signedTransactionJWS: jws
        )
    }
}
