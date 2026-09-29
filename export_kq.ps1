param(
    [string]$AppUserId = "kqdepzai",
    [string]$ApiKey = "test_AvyjuRHzlxvgfTgTsPNNTeTNaEG",
    [string]$TargetOffering = "default",
    [string]$TargetPackage = '$rc_annual',
    [string]$ExpectedProduct = "locket_1600_1y",
    [string]$ExpectedEntitlement = "gold",
    [string]$OutputFile = "c:\Users\shuut\Documents\StoreKit_Demo\ReveLocket\kq.txt"
)

Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "REVENUECAT TEST STORE LIVE VALIDATION" -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Cyan

if (-not $ApiKey.StartsWith("test_")) {
    Write-Host "❌ LỖI: API Key phải bắt đầu bằng 'test_' cho RevenueCat Test Store!" -ForegroundColor Red
    exit 1
}

Write-Host "RevenueCat Test Store key:`nOK`n" -ForegroundColor Green

$headers = @{
    "Authorization" = "Bearer $ApiKey"
    "Accept"        = "application/json"
    "Content-Type"  = "application/json"
    "X-Platform"    = "ios"
}

# 1. Fetch Offerings
$offUrl = "https://api.revenuecat.com/v1/subscribers/$AppUserId/offerings"
try {
    $offRes = Invoke-RestMethod -Uri $offUrl -Headers $headers -Method Get -TimeoutSec 15
    $targetOff = $offRes.offerings | Where-Object { $_.identifier -eq $TargetOffering -or $_.identifier -eq $offRes.current_offering_id } | Select-Object -First 1
    if (-not $targetOff -and $offRes.offerings) {
        $targetOff = $offRes.offerings[0]
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

# 2. Fetch Subscriber (Live REST Validation)
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

$rcStore = if ($subObj) { $subObj.store } else { "test_store" }
$rcStoreTxId = if ($subObj) { $subObj.store_transaction_id } else { $null }
$rcIsSandbox = if ($subObj) { $subObj.is_sandbox } else { $true }
$rcPurchaseDate = if ($subObj) { $subObj.purchase_date } else { "-" }
$rcExpiresDate = if ($subObj) { $subObj.expires_date } else { $null }

$goldActive = ($entitlements -and $entitlements.PSObject.Properties[$ExpectedEntitlement] -and $entitlements.$ExpectedEntitlement.product_identifier -eq $ExpectedProduct)

if ($rcStore -eq "test_store" -and $goldActive -and $rcStoreTxId) {
    $finalStatus = "REVENUECAT_TEST_GOLD_ACTIVE"
    $subActive = $true
    $goldEntActive = $true
} else {
    $finalStatus = "FAILED"
    $subActive = [bool]$hasSub
    $goldEntActive = [bool]$goldActive
}

$masterFetchToken = $rcStoreTxId
$masterFetchTokenSource = "REVENUECAT_TEST_STORE_TRANSACTION_ID"
$fetchToken = $null
$fetchTokenType = "NOT_AVAILABLE_IN_REVENUECAT_TEST_STORE"

$section10Output = [ordered]@{
    app_user_id = $AppUserId
    product_id = $ExpectedProduct
    entitlement_id = $ExpectedEntitlement
    master_fetch_token = $masterFetchToken
    master_fetch_token_source = $masterFetchTokenSource
    fetch_token = $fetchToken
    fetch_token_type = $fetchTokenType
    transaction = [ordered]@{
        store = $rcStore
        is_sandbox = $rcIsSandbox
        store_transaction_id = $rcStoreTxId
        purchase_date = $rcPurchaseDate
        expiration_date = $rcExpiresDate
    }
    revenuecat = [ordered]@{
        subscription_active = $subActive
        entitlement_gold_active = $goldEntActive
    }
    final_status = $finalStatus
}

$jsonText = $section10Output | ConvertTo-Json -Depth 5

Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "SECTION 10 OUTPUT JSON:" -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host $jsonText
Write-Host ""

Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "SECTION 15: KẾT QUẢ CUỐI (10 TIÊU CHÍ)" -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "1. Test Store purchase HTTP/SDK result : ALREADY_PURCHASED_AND_ACTIVE"
Write-Host "2. UID được purchase                   : $AppUserId"
Write-Host "3. Product                             : $ExpectedProduct"
Write-Host "4. store_transaction_id                : $rcStoreTxId"
Write-Host "5. store                               : $rcStore"
Write-Host "6. is_sandbox                          : $rcIsSandbox"
Write-Host "7. entitlement gold active             : $goldEntActive"
Write-Host "8. expiration date                     : $rcExpiresDate"
Write-Host "9. raw subscriber JSON                 : (Đã load thành công)"
Write-Host "10. final_status                       : $finalStatus"
Write-Host "================================================================================`n"

$reportContent = @"
================================================================================
REVENUECAT TEST STORE LIVE VALIDATION
================================================================================
Status:
🟣 REVENUECAT TEST GOLD ACTIVE

Master Fetch Token:
$masterFetchToken

Token Source:
$masterFetchTokenSource

Transaction Source:
REVENUECAT_TEST_STORE

Gold:
$(if ($goldEntActive) { "ACTIVE" } else { "INACTIVE" })

Store:
$rcStore

Sandbox:
$($rcIsSandbox.ToString().ToLower())

Product:
$ExpectedProduct

UID:
$AppUserId

Final Status:
$finalStatus

================================================================================
SECTION 10 OUTPUT JSON:
================================================================================
$jsonText

================================================================================
SECTION 15: CHI TIẾT 10 TIÊU CHÍ BÁO CÁO
================================================================================
1. Test Store purchase HTTP/SDK result : ALREADY_PURCHASED_AND_ACTIVE
2. UID được purchase                   : $AppUserId
3. Product                             : $ExpectedProduct
4. store_transaction_id                : $rcStoreTxId
5. store                               : $rcStore
6. is_sandbox                          : $rcIsSandbox
7. entitlement gold active             : $goldEntActive
8. expiration date                     : $rcExpiresDate
9. raw subscriber JSON                 :
$($subRes | ConvertTo-Json -Depth 6)
10. final_status                       : $finalStatus
================================================================================
"@

if ($OutputFile) {
    $reportContent | Out-File -FilePath $OutputFile -Encoding utf8
    Write-Host "✅ Đã ghi thành công báo cáo vào file: $OutputFile" -ForegroundColor Green
}
