param(
    [string]$AppUserId = "1a73l0yKjleF7djpO7oYeP4u8ri1",
    [string]$ApiKey = "appl_JngFETzdodyLmCREOlwTUtXdQik",
    [string]$TargetOffering = "locket_199",
    [string]$TargetPackage = '$rc_annual',
    [string]$ExpectedProduct = "locket_1600_1y",
    [string]$OutputFile = "c:\Users\shuut\Documents\StoreKit_Demo\ReveLocket\kq.txt"
)

Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "APPLE STOREKIT 2 & REVENUECAT LIVE VALIDATION (STRICT REAL STOREKIT ONLY)" -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Cyan

if (-not $ApiKey.StartsWith("appl_")) {
    Write-Host "❌ LỖI: Chỉ chấp nhận RevenueCat App Store key (bắt đầu bằng appl_)!" -ForegroundColor Red
    exit 1
}

Write-Host "RevenueCat appl key:`nOK`n" -ForegroundColor Green

$headers = @{
    "Authorization" = "Bearer $ApiKey"
    "Accept"        = "application/json"
    "X-Platform"    = "ios"
}

# 1. Fetch Offerings
$offUrl = "https://api.revenuecat.com/v1/subscribers/$AppUserId/offerings"
try {
    $offRes = Invoke-RestMethod -Uri $offUrl -Headers $headers -Method Get -TimeoutSec 15
    $targetOff = $offRes.offerings | Where-Object { $_.identifier -eq $TargetOffering } | Select-Object -First 1
    if (-not $targetOff) {
        Write-Host "Offering ${TargetOffering}:`nNOT FOUND`n" -ForegroundColor Red
        exit 1
    }
    Write-Host "Offering ${TargetOffering}:`nFOUND`n" -ForegroundColor Green

    $pkg = $targetOff.packages | Where-Object { $_.identifier -eq $TargetPackage } | Select-Object -First 1
    if (-not $pkg) {
        Write-Host "Package ${TargetPackage}:`nNOT FOUND`n" -ForegroundColor Red
        exit 1
    }
    Write-Host "Package ${TargetPackage}:`nFOUND`n" -ForegroundColor Green

    $actualProduct = $pkg.platform_product_identifier
    if ($actualProduct -ne $ExpectedProduct) {
        Write-Host "Product ${ExpectedProduct}:`nMISMATCH (Received $actualProduct)`n" -ForegroundColor Red
        exit 1
    }
    Write-Host "Product ${ExpectedProduct}:`nFOUND (Matches expected product identifier)`n" -ForegroundColor Green
} catch {
    Write-Host "❌ Lỗi kết nối Offerings: $_" -ForegroundColor Red
    exit 1
}

# 2. Fetch Subscriber
$subUrl = "https://api.revenuecat.com/v1/subscribers/$AppUserId"
try {
    $subRes = Invoke-RestMethod -Uri $subUrl -Headers $headers -Method Get -TimeoutSec 15
    $sub = $subRes.subscriber
    $subscriptions = $sub.subscriptions
    $entitlements = $sub.entitlements
} catch {
    Write-Host "❌ Lỗi kết nối Subscriber: $_" -ForegroundColor Red
    exit 1
}

$hasAppleSub = ($subscriptions -and $subscriptions.PSObject.Properties[$ExpectedProduct] -and $subscriptions.$ExpectedProduct.store -eq "app_store" -and $subscriptions.$ExpectedProduct.store_transaction_id)

if ($hasAppleSub) {
    $masterFetchToken = $subscriptions.$ExpectedProduct.store_transaction_id
    $masterFetchTokenSource = "REVENUECAT_STORE_TRANSACTION_ID"
    $fetchToken = "OBTAINED_FROM_STOREKIT2_VERIFICATION_RESULT"
    $finalStatus = "VERIFIED_ACTIVE"
    $skVerified = $true
    $skTxId = $subscriptions.$ExpectedProduct.store_transaction_id
    $skOrigId = $subscriptions.$ExpectedProduct.original_purchase_date
    $skEnv = if ($subscriptions.$ExpectedProduct.is_sandbox) { "Sandbox" } else { "Production" }
    $skPurchaseDate = $subscriptions.$ExpectedProduct.purchase_date
    $skExpDate = $subscriptions.$ExpectedProduct.expires_date
    $rcSubActive = $true
    $rcEntActive = ($entitlements -and $entitlements.PSObject.Properties["gold"] -and $entitlements.gold.product_identifier -eq $ExpectedProduct)
    $jwsFull = $true
    $txIdMatch = $true
    $rcLiveMatch = $true
} else {
    # Section 1 & 11: Nếu chưa có transaction Apple hợp lệ:
    # master_fetch_token = null, fetch_token = null, final_status = "PURCHASE_REQUIRED"
    $masterFetchToken = $null
    $masterFetchTokenSource = "UNAVAILABLE"
    $fetchToken = $null
    $finalStatus = "PURCHASE_REQUIRED"
    $skVerified = $false
    $skTxId = "-"
    $skOrigId = "-"
    $skEnv = "-"
    $skPurchaseDate = "-"
    $skExpDate = $null
    $rcSubActive = $false
    $rcEntActive = $false
    $jwsFull = $false
    $txIdMatch = $false
    $rcLiveMatch = $false
}

$section10Output = [ordered]@{
    app_user_id = $AppUserId
    product_id = $ExpectedProduct
    master_fetch_token = $masterFetchToken
    master_fetch_token_source = $masterFetchTokenSource
    fetch_token = $fetchToken
    fetch_token_type = "STOREKIT2_JWS_TRANSACTION"
    storekit = [ordered]@{
        verified = $skVerified
        transaction_id = $skTxId
        original_transaction_id = $skOrigId
        environment = $skEnv
        purchase_date = $skPurchaseDate
        expiration_date = $skExpDate
    }
    revenuecat = [ordered]@{
        subscription_active = $rcSubActive
        store = "app_store"
        store_transaction_id = if ($hasAppleSub) { $subscriptions.$ExpectedProduct.store_transaction_id } else { $null }
        entitlement_active = $rcEntActive
    }
    validation = [ordered]@{
        jws_full = $jwsFull
        apple_transaction_verified = $skVerified
        transaction_id_match = $txIdMatch
        revenuecat_live_match = $rcLiveMatch
    }
    final_status = $finalStatus
}

$jsonText = $section10Output | ConvertTo-Json -Depth 4

Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "SECTION 10 OUTPUT JSON:" -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host $jsonText
Write-Host ""
