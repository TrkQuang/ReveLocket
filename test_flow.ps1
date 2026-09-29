param(
    [string]$AppUserId = "kqdepzai",
    [string]$ApiKey = "test_AvyjuRHzlxvgfTgTsPNNTeTNaEG"
)

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "🚀 REVENUECAT TEST STORE - AUTOMATED TEST RUNNER" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "API Key        : $ApiKey"
Write-Host "App User ID    : $AppUserId"
Write-Host "Target Store   : RevenueCat Test Store"
Write-Host ""

$headers = @{
    "Authorization" = "Bearer $ApiKey"
    "Content-Type"  = "application/json"
    "X-Platform"    = "ios"
    "X-Is-Sandbox"  = "true"
}

# 1. Fetch CustomerInfo ban đầu
Write-Host "1️⃣  [FETCH] Đang lấy CustomerInfo cho '$AppUserId'..." -ForegroundColor Yellow
try {
    $sub = Invoke-RestMethod -Uri "https://api.revenuecat.com/v1/subscribers/$AppUserId" -Headers $headers -Method Get
    $isGold = $null -ne $sub.subscriber.entitlements.gold
    Write-Host "   ✅ User ID: $($sub.subscriber.original_app_user_id)" -ForegroundColor Green
    if ($isGold) {
        Write-Host "   👑 Trạng thái Gold ban đầu: ACTIVE" -ForegroundColor Green
    } else {
        Write-Host "   👑 Trạng thái Gold ban đầu: INACTIVE" -ForegroundColor DarkGray
    }
} catch {
    Write-Host "   ❌ Lỗi khi lấy CustomerInfo: $_" -ForegroundColor Red
    exit 1
}

Write-Host ""

# 2. Fetch Offerings
Write-Host "2️⃣  [FETCH] Đang lấy Offerings từ RevenueCat..." -ForegroundColor Yellow
try {
    $offeringsRes = Invoke-RestMethod -Uri "https://api.revenuecat.com/v1/subscribers/$AppUserId/offerings" -Headers $headers -Method Get
    Write-Host "   Current Offering ID: $($offeringsRes.current_offering_id)" -ForegroundColor Green

    $defaultOffering = $offeringsRes.offerings | Where-Object { $_.identifier -eq "default" }
    if (-not $defaultOffering) {
        Write-Host "   ❌ Không tìm thấy offering 'default'!" -ForegroundColor Red
        exit 1
    }

    Write-Host "   ✅ Tìm thấy Offering: $($defaultOffering.identifier)" -ForegroundColor Green

    $annualPkg = $defaultOffering.packages | Where-Object { $_.identifier -eq "`$rc_annual" }
    if (-not $annualPkg) {
        Write-Host "   ❌ Không tìm thấy package '$rc_annual' trong offering default!" -ForegroundColor Red
        exit 1
    }

    Write-Host "   🎁 Package Identifier: $($annualPkg.identifier)" -ForegroundColor Green
    Write-Host "   🏷️  Product Identifier: $($annualPkg.platform_product_identifier)" -ForegroundColor Green
} catch {
    Write-Host "   ❌ Lỗi khi lấy Offerings: $_" -ForegroundColor Red
    exit 1
}

Write-Host ""

# 3. Simulate Purchase trên RevenueCat Test Store
Write-Host "3️⃣  [PURCHASE] Đang thực hiện Purchase Package '$($annualPkg.identifier)'..." -ForegroundColor Yellow
$txId = "test_store_token_" + [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$purchaseBody = @{
    "app_user_id" = $AppUserId
    "fetch_token" = $txId
    "product_id"  = $annualPkg.platform_product_identifier
    "price"       = 16.00
    "currency"    = "USD"
} | ConvertTo-Json

try {
    $purchaseRes = Invoke-RestMethod -Uri "https://api.revenuecat.com/v1/receipts" -Headers $headers -Method Post -Body $purchaseBody
    Write-Host "   ✅ Giao dịch Test Store thành công!" -ForegroundColor Green
    Write-Host "   🧾 Transaction ID: $txId" -ForegroundColor Cyan
    Write-Host "   🏪 Store         : test_store" -ForegroundColor Cyan
} catch {
    Write-Host "   ❌ Lỗi Purchase: $_" -ForegroundColor Red
    exit 1
}

Write-Host ""

# 4. Kiểm tra Entitlement sau khi purchase
Write-Host "4️⃣  [VERIFY] Kiểm tra Entitlement 'gold'..." -ForegroundColor Yellow
$goldEntitlement = $purchaseRes.subscriber.entitlements.gold

if ($null -ne $goldEntitlement) {
    Write-Host "==========================================================" -ForegroundColor Green
    Write-Host "🎉 KẾT QUẢ: Locket Gold: ACTIVE" -ForegroundColor Green
    Write-Host "==========================================================" -ForegroundColor Green
    Write-Host "   - Product ID   : $($goldEntitlement.product_identifier)"
    Write-Host "   - Purchase Date: $($goldEntitlement.purchase_date)"
    Write-Host "   - Expires Date : $($goldEntitlement.expires_date)"
    Write-Host "   - Subscription : $($purchaseRes.subscriber.subscriptions.($goldEntitlement.product_identifier).display_name)"
} else {
    Write-Host "==========================================================" -ForegroundColor Red
    Write-Host "⚠️ KẾT QUẢ: Locket Gold: INACTIVE" -ForegroundColor Red
    Write-Host "==========================================================" -ForegroundColor Red
}

Write-Host ""
Write-Host "5️⃣  [DEBUG] UNIFIED OUTPUT JSON (Theo yêu cầu):" -ForegroundColor Magenta

$unifiedOutput = [ordered]@{
    "app_user_id"        = $AppUserId
    "product_id"         = $annualPkg.platform_product_identifier
    "package_id"         = $annualPkg.identifier
    "store"              = "test_store"
    "transaction"        = [ordered]@{
        "id"                   = $txId
        "store_transaction_id" = $txId
        "purchase_date"        = $goldEntitlement.purchase_date
        "expiration_date"      = $goldEntitlement.expires_date
    }
    "entitlement"        = [ordered]@{
        "identifier" = "gold"
        "is_active"  = ($null -ne $goldEntitlement)
    }
    "fetch_token"        = $null
    "fetch_token_status" = "NOT EXPOSED BY REVENUECAT TEST STORE"
}

$unifiedOutput | ConvertTo-Json -Depth 5

Write-Host ""
Write-Host "👉 Bạn có thể vào RevenueCat Dashboard > Customers > tìm '$AppUserId' để xem transaction vừa tạo!" -ForegroundColor Cyan
