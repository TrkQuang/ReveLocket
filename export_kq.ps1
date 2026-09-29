param(
    [string]$AppUserId = "kqdepzai",
    [string]$ApiKey = "appl_JngFETzdodyLmCREOlwTUtXdQik",
    [string]$TargetOffering = "locket_199",
    [string]$TargetPackage = '$rc_annual',
    [string]$ExpectedProduct = "locket_1600_1y",
    [string]$ExpectedEntitlement = "Gold",
    [string]$StoreKitConfigFile = "LocketGold.storekit",
    [string]$OutputFile = "c:\Users\shuut\Documents\StoreKit_Demo\ReveLocket\kq.txt"
)

Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "MODE: XCODE LOCAL STOREKIT + REVENUECAT" -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Cyan

if ($ApiKey.StartsWith("test_")) {
    Write-Host "❌ LỖI: CẤM sử dụng RevenueCat Test Store key (test_...) trong chế độ XCODE_LOCAL_STOREKIT!" -ForegroundColor Red
    exit 1
}

Write-Host "RevenueCat Public SDK Key: OK ($ApiKey)`n" -ForegroundColor Green

# 1. Kiểm tra file StoreKit
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$storeKitPath = Join-Path $scriptDir $StoreKitConfigFile
if (-not (Test-Path $storeKitPath)) {
    Write-Host "❌ Không tìm thấy file $StoreKitConfigFile tại $storeKitPath" -ForegroundColor Red
    exit 1
}
Write-Host "StoreKit Configuration File:`nFOUND ($StoreKitConfigFile)`n" -ForegroundColor Green

$headers = @{
    "Authorization" = "Bearer $ApiKey"
    "Accept"        = "application/json"
    "Content-Type"  = "application/json"
    "X-Platform"    = "ios"
}

# 2. Fetch Offerings
$offUrl = "https://api.revenuecat.com/v1/subscribers/$AppUserId/offerings"
try {
    $offRes = Invoke-RestMethod -Uri $offUrl -Headers $headers -Method Get -TimeoutSec 15
    $targetOff = $offRes.offerings | Where-Object { $_.identifier -eq $TargetOffering } | Select-Object -First 1
    if (-not $targetOff -and $offRes.offerings) {
        $targetOff = $offRes.offerings | Where-Object { $_.identifier -eq $offRes.current_offering_id } | Select-Object -First 1
        if (-not $targetOff) { $targetOff = $offRes.offerings[0] }
    }
    if (-not $targetOff) {
        Write-Host "Offering ${TargetOffering}:`nNOT FOUND`n" -ForegroundColor Red
        exit 1
    }
    Write-Host "Offering '$($targetOff.identifier)':`nFOUND`n" -ForegroundColor Green

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

# 3. Fetch Subscriber (Live REST Validation)
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

$hasSub = ($subscriptions -and $subscriptions.PSObject.Properties[$ExpectedProduct])
$subObj = if ($hasSub) { $subscriptions.$ExpectedProduct } else { $null }

$rcStoreTxId = if ($subObj) { $subObj.store_transaction_id } else { $null }
$rcPurchaseDate = if ($subObj) { $subObj.purchase_date } else { $null }
$rcExpiresDate = if ($subObj) { $subObj.expires_date } else { $null }

# Kiểm tra entitlement Gold (Gold hoặc gold)
$goldEntObj = $null
if ($entitlements) {
    if ($entitlements.PSObject.Properties["Gold"]) {
        $goldEntObj = $entitlements.Gold
    } elseif ($entitlements.PSObject.Properties["gold"]) {
        $goldEntObj = $entitlements.gold
    }
}
$goldActive = ($goldEntObj -and $goldEntObj.product_identifier -eq $ExpectedProduct)

if ($goldActive -and $rcStoreTxId) {
    $finalStatus = "LOCAL_STOREKIT_REVENUECAT_ACTIVE"
    $masterFetchToken = $rcStoreTxId
    $masterFetchTokenSource = "REVENUECAT_STORE_TRANSACTION_ID"
    $storekitVerified = $true
} else {
    $finalStatus = "REVENUECAT_LOCAL_STOREKIT_SYNC_FAILED"
    $masterFetchToken = $null
    $masterFetchTokenSource = $null
    $storekitVerified = $false
}

$section11Output = [ordered]@{
    app_user_id = $AppUserId
    product_id = $ExpectedProduct
    transaction_source = "XCODE_LOCAL_STOREKIT"
    master_fetch_token = $masterFetchToken
    master_fetch_token_source = $masterFetchTokenSource
    fetch_token = $null
    fetch_token_type = "XCODE_LOCAL_STOREKIT_JWS"
    storekit = [ordered]@{
        verified = $storekitVerified
        transaction_id = $rcStoreTxId
        original_transaction_id = $rcStoreTxId
        purchase_date = $rcPurchaseDate
        expiration_date = $rcExpiresDate
    }
    revenuecat = [ordered]@{
        subscription_active = [bool]$hasSub
        entitlement_gold_active = [bool]$goldActive
        store_transaction_id = $rcStoreTxId
    }
    final_status = $finalStatus
}

$jsonText = $section11Output | ConvertTo-Json -Depth 5

Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "SECTION 11 OUTPUT JSON:" -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host $jsonText
Write-Host "================================================================================`n" -ForegroundColor Cyan

# Ghi ra file kq.txt
if (-not (Test-Path (Split-Path -Parent $OutputFile))) {
    $OutputFile = Join-Path $scriptDir "kq.txt"
}

$report = @"
================================================================================
XCODE LOCAL STOREKIT + REVENUECAT AUDIT REPORT
================================================================================
Mode:
XCODE_LOCAL_STOREKIT

App User ID:
$AppUserId

Offering:
$TargetOffering

Package:
$TargetPackage

Product:
$ExpectedProduct

Entitlement Gold Active:
$(if ($goldActive) { "ACTIVE" } else { "INACTIVE" })

Store Transaction ID:
$rcStoreTxId

Final Status:
$finalStatus

================================================================================
SECTION 11 OUTPUT JSON:
================================================================================
$jsonText

================================================================================
HƯỚNG DẪN BƯỚC TIẾP THEO (XCODE LOCAL STOREKIT TESTING CERTIFICATE):
================================================================================
1. Mở file LocketGold.storekit trong Xcode.
2. Vào Editor -> Save Public Certificate...
3. Upload file certificate lên RevenueCat Dashboard (App Settings -> StoreKit Testing Certificate).
4. Run project trong Xcode (Scheme Options -> StoreKit Configuration: LocketGold.storekit).
5. Purchase trong App -> RevenueCat sẽ nhận transaction local và cấp quyền Gold ACTIVE.
================================================================================
"@

[System.IO.File]::WriteAllText($OutputFile, $report, [System.Text.Encoding]::UTF8)
Write-Host "✅ Đã ghi thành công báo cáo vào file: $OutputFile" -ForegroundColor Green
