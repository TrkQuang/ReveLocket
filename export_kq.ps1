param(
    [string]$AppUserId = "1a73l0yKjleF7djpO7oYeP4u8ri1",
    [string]$ApiKey = "appl_JngFETzdodyLmCREOlwTUtXdQik",
    [string]$TargetOffering = "locket_199",
    [string]$TargetPackage = '$rc_annual',
    [string]$ExpectedProduct = "locket_1600_1y",
    [string]$OutputFile = "c:\Users\shuut\Documents\StoreKit_Demo\ReveLocket\kq.txt"
)

Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "APPLE APP STORE CONFIG CHECK (ZERO TEST STORE / ZERO FAKE PURCHASE)" -ForegroundColor Cyan
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
        Write-Host "Offering $TargetOffering:`nNOT FOUND`n" -ForegroundColor Red
        exit 1
    }
    Write-Host "Offering $TargetOffering:`nFOUND`n" -ForegroundColor Green

    $pkg = $targetOff.packages | Where-Object { $_.identifier -eq $TargetPackage } | Select-Object -First 1
    if (-not $pkg) {
        Write-Host "Package $TargetPackage:`nNOT FOUND`n" -ForegroundColor Red
        exit 1
    }
    Write-Host "Package $TargetPackage:`nFOUND`n" -ForegroundColor Green

    $actualProduct = $pkg.platform_product_identifier
    if ($actualProduct -ne $ExpectedProduct) {
        Write-Host "Product $ExpectedProduct:`nMISMATCH`n" -ForegroundColor Red
        exit 1
    }
    Write-Host "Product $ExpectedProduct:`nFOUND`n" -ForegroundColor Green
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
} catch {
    Write-Host "❌ Lỗi kết nối Subscriber: $_" -ForegroundColor Red
    exit 1
}

$hasAppleSub = ($subscriptions -and $subscriptions.PSObject.Properties[$ExpectedProduct] -and $subscriptions.$ExpectedProduct.store -eq "app_store")

if ($hasAppleSub) {
    $applePurchaseStatus = "EXECUTED (Apple Verified on Server)"
    $masterFetchToken = $subscriptions.$ExpectedProduct.store_transaction_id
    $storeTxDisplay = $subscriptions.$ExpectedProduct.store_transaction_id
    $rcActiveDisplay = "YES"
    $finalStatus = "VERIFIED_ACTIVE"
} else {
    $applePurchaseStatus = "NOT EXECUTED IN CI (DEVICE/SANDBOX ENVIRONMENT REQUIRED)"
    $masterFetchToken = "NONE"
    $storeTxDisplay = "NONE"
    $rcActiveDisplay = "NO"
    $finalStatus = "APPLE_SANDBOX_PURCHASE_REQUIRED"
}

Write-Host "Apple StoreKit Sandbox Purchase:`n$applePurchaseStatus`n"
Write-Host "Master Fetch Token:`n$masterFetchToken`n"
Write-Host "Store Transaction:`n$storeTxDisplay`n"
Write-Host "RevenueCat Subscription Active:`n$rcActiveDisplay`n"
Write-Host "Final Status:`n$finalStatus`n" -ForegroundColor Yellow
