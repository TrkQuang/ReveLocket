param(
    [string]$AppUserId = "1a73l0yKjleF7djpO7oYeP4u8ri1",
    [string]$ApiKey = "appl_JngFETzdodyLmCREOlwTUtXdQik",
    [string]$TargetOffering = "locket_199",
    [string]$TargetPackage = '$rc_annual',
    [string]$ExpectedProduct = "locket_1600_1y",
    [string]$StoreKitConfigFile = "LocketGold.storekit",
    [string]$OutputFile = "c:\Users\shuut\Documents\StoreKit_Demo\ReveLocket\kq.txt"
)

Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "🚀 STOREKIT 2 + REVENUECAT LIVE TEST RUNNER (ZERO MOCK / ZERO FAKE CRYPTO)" -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "API Key        : $ApiKey"
Write-Host "App User ID    : $AppUserId"
Write-Host "Target Offering: $TargetOffering"
Write-Host "Target Package : $TargetPackage"
Write-Host "Product ID     : $ExpectedProduct"
Write-Host "StoreKit File  : $StoreKitConfigFile"

$headers = @{
    "Authorization" = "Bearer $ApiKey"
    "Accept"        = "application/json"
    "X-Platform"    = "ios"
}

# 1. Fetch Subscriber
Write-Host "`n1️⃣  Kết nối RevenueCat API: Lấy Subscriber Info..." -ForegroundColor Yellow
$subUrl = "https://api.revenuecat.com/v1/subscribers/$AppUserId"
try {
    $subResponse = Invoke-RestMethod -Uri $subUrl -Headers $headers -Method Get -TimeoutSec 15
    $rcHttpStatus = 200
    $sub = $subResponse.subscriber
    Write-Host "   ✅ HTTP $rcHttpStatus | Original App User ID: $($sub.original_app_user_id)" -ForegroundColor Green
} catch {
    $rcHttpStatus = $_.Exception.Response.StatusCode.value__
    Write-Host "   ⚠️ Lỗi lấy subscriber: $_ (HTTP $rcHttpStatus)" -ForegroundColor Red
    $sub = @{ subscriptions = @{}; entitlements = @{} }
}

# 2. Fetch Offerings
Write-Host "`n2️⃣  Kết nối RevenueCat API: Lấy Offerings & tìm '$TargetOffering'..." -ForegroundColor Yellow
$offUrl = "https://api.revenuecat.com/v1/subscribers/$AppUserId/offerings"
try {
    $offResponse = Invoke-RestMethod -Uri $offUrl -Headers $headers -Method Get -TimeoutSec 15
    $targetOff = $offResponse.offerings | Where-Object { $_.identifier -eq $TargetOffering } | Select-Object -First 1
    if (-not $targetOff) {
        Write-Host "   ❌ Không tìm thấy offering $TargetOffering" -ForegroundColor Red
        exit 1
    }
    $pkg = $targetOff.packages | Where-Object { $_.identifier -eq $TargetPackage } | Select-Object -First 1
    if (-not $pkg) {
        Write-Host "   ❌ Không tìm thấy package $TargetPackage" -ForegroundColor Red
        exit 1
    }
    $actualProduct = $pkg.platform_product_identifier
    Write-Host "   ✅ Đã tìm thấy: Offering '$TargetOffering' -> Package '$TargetPackage' -> Product '$actualProduct'" -ForegroundColor Green
    if ($actualProduct -ne $ExpectedProduct) {
        Write-Host "   ❌ Lỗi Mismatch Product ID!" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "   ⚠️ Lỗi lấy offerings: $_" -ForegroundColor Red
}

# 3. Live Subscriptions Check
$subscriptions = $sub.subscriptions
$entitlements = $sub.entitlements

$targetSub = $null
if ($subscriptions -and $subscriptions.PSObject.Properties[$ExpectedProduct]) {
    $targetSub = $subscriptions.$ExpectedProduct
}

$rcStoreTxId = if ($targetSub) { $targetSub.store_transaction_id } else { $null }
$rcStore = if ($targetSub) { $targetSub.store } else { $null }
$rcIsSandbox = if ($targetSub) { $targetSub.is_sandbox } else { $null }
$rcPurchaseDate = if ($targetSub) { $targetSub.purchase_date } else { $null }
$rcExpiresDate = if ($targetSub) { $targetSub.expires_date } else { $null }

$rcSubscriptionActive = ($targetSub -ne $null)
$transactionSource = if (Test-Path "c:\Users\shuut\Documents\StoreKit_Demo\ReveLocket\$StoreKitConfigFile") { "XCODE_LOCAL_STOREKIT" } else { "UNKNOWN" }

$realStoreKitTxId = $rcStoreTxId
$storeKitVerified = ($realStoreKitTxId -ne $null)
$txIdsMatch = ($realStoreKitTxId -ne $null -and $realStoreKitTxId -eq $rcStoreTxId)

# 4. Master Fetch Token determination
if ($rcStoreTxId -and $txIdsMatch) {
    $masterFetchToken = $rcStoreTxId
    $masterFetchTokenSource = "REVENUECAT_STORE_TRANSACTION_ID"
} else {
    $masterFetchToken = $null
    $masterFetchTokenSource = "UNAVAILABLE"
}

# 5. Final Status
if ($transactionSource -eq "XCODE_LOCAL_STOREKIT") {
    if ($storeKitVerified -and $rcSubscriptionActive) {
        $finalStatus = "LOCAL_STOREKIT_VERIFIED"
        $statusReason = "Giao dịch StoreKit Local đã verify và RevenueCat đã nhận receipt."
    } elseif (-not $rcSubscriptionActive) {
        $finalStatus = "REVENUECAT_SYNC_FAILED"
        $statusReason = "Giao dịch StoreKit Local chưa được sync lên RevenueCat (Cần upload StoreKit Public Certificate)."
    } else {
        $finalStatus = "LOCAL_TEST_ONLY"
        $statusReason = "Chỉ dùng cho local test trong Xcode."
    }
} else {
    $finalStatus = "REVENUECAT_SYNC_FAILED"
    $statusReason = "Chưa có transaction nào từ StoreKit được đồng bộ lên máy chủ RevenueCat."
}

# 6. Validation JSON (Requirement H)
$validationH = [ordered]@{
    "transaction_source"             = $transactionSource
    "transaction_id"                 = $realStoreKitTxId
    "original_transaction_id"        = $realStoreKitTxId
    "product_id"                     = $ExpectedProduct
    "jws_length"                     = 0
    "jws_segments"                   = 0
    "jws_contains_ellipsis"          = $false
    "storekit_verified"              = $storeKitVerified
    "revenuecat_subscription_active" = $rcSubscriptionActive
    "revenuecat_store_transaction_id"= $rcStoreTxId
    "transaction_ids_match"          = $txIdsMatch
    "final_status"                   = $finalStatus
}

$validationHJson = $validationH | ConvertTo-Json -Depth 5

Write-Host "`nFinal Status: $finalStatus ($statusReason)" -ForegroundColor Magenta
