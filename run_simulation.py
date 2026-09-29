import requests
import json
import os
import sys

# ==============================================================================
# XCODE LOCAL STOREKIT + REVENUECAT LIVE AUDIT
# ==============================================================================
# TUYỆT ĐỐI KHÔNG dùng Apple Sandbox.
# KHÔNG dùng TestFlight.
# KHÔNG yêu cầu Sandbox Apple ID.
# KHÔNG dùng RevenueCat Test Store (không test_...).
#
# CẤU HÌNH:
# - RevenueCat Public SDK Key: appl_JngFETzdodyLmCREOlwTUtXdQik
# - App User ID: kqdepzai
# - Offering: locket_199
# - Package: $rc_annual
# - Product: locket_1600_1y
# - Entitlement: Gold
# - StoreKit Config: LocketGold.storekit
# - Transaction Source: XCODE_LOCAL_STOREKIT
# ==============================================================================

PUBLIC_SDK_KEY = "appl_JngFETzdodyLmCREOlwTUtXdQik"
APP_USER_ID = os.environ.get("CURRENT_UID", "kqdepzai")
TARGET_OFFERING = "locket_199"
TARGET_PACKAGE = "$rc_annual"
EXPECTED_PRODUCT = "locket_1600_1y"
EXPECTED_ENTITLEMENT = "Gold"
STOREKIT_CONFIG_FILE = "LocketGold.storekit"

WORKSPACE_DIR = os.path.dirname(os.path.abspath(__file__))
STOREKIT_PATH = os.path.join(WORKSPACE_DIR, STOREKIT_CONFIG_FILE)
OUTPUT_FILE = os.path.join(WORKSPACE_DIR, "kq.txt")

headers = {
    "Authorization": f"Bearer {PUBLIC_SDK_KEY}",
    "Accept": "application/json",
    "Content-Type": "application/json",
    "X-Platform": "ios"
}

print("================================================================================")
print("MODE: XCODE LOCAL STOREKIT + REVENUECAT")
print("================================================================================")
print(f"RevenueCat Public SDK Key : {PUBLIC_SDK_KEY}")
print(f"Target App User ID        : {APP_USER_ID}")
print(f"Target Offering           : {TARGET_OFFERING}")
print(f"Target Package            : {TARGET_PACKAGE}")
print(f"Expected Product          : {EXPECTED_PRODUCT}")
print(f"Expected Entitlement      : {EXPECTED_ENTITLEMENT}")
print(f"StoreKit Config File      : {STOREKIT_CONFIG_FILE}")
print("================================================================================\n")

# 1. Kiểm tra API Key (Phải bắt đầu bằng appl_, TUYỆT ĐỐI không test_)
if PUBLIC_SDK_KEY.startswith("test_"):
    print("❌ LỖI: CẤM sử dụng RevenueCat Test Store key (test_...) trong chế độ XCODE_LOCAL_STOREKIT!")
    sys.exit(1)

if not PUBLIC_SDK_KEY.startswith("appl_"):
    print("❌ LỖI: Public API Key phải là key Apple (appl_...)!")
    sys.exit(1)

print("✅ RevenueCat Public SDK Key: OK (appl_...)\n")

# 2. Kiểm tra StoreKit Configuration File (LocketGold.storekit)
print("--- [BƯỚC 1] KIỂM TRA LOCAL STOREKIT CONFIGURATION FILE ---")
if not os.path.exists(STOREKIT_PATH):
    print(f"❌ Không tìm thấy file {STOREKIT_CONFIG_FILE} tại {STOREKIT_PATH}")
    sys.exit(1)

try:
    with open(STOREKIT_PATH, "r", encoding="utf-8") as f:
        storekit_data = json.load(f)
except Exception as e:
    print(f"❌ Không thể đọc file {STOREKIT_CONFIG_FILE}: {e}")
    sys.exit(1)

storefront = storekit_data.get("settings", {}).get("_storefront", "")
sub_groups = storekit_data.get("subscriptionGroups", [])
found_sub = None
found_group_id = None

for group in sub_groups:
    group_id = group.get("id")
    for sub in group.get("subscriptions", []):
        if sub.get("productID") == EXPECTED_PRODUCT:
            found_sub = sub
            found_group_id = group_id
            break
    if found_sub:
        break

if not found_sub:
    print(f"❌ Product '{EXPECTED_PRODUCT}' KHÔNG tồn tại trong {STOREKIT_CONFIG_FILE}!")
    sys.exit(1)

period = found_sub.get("recurringSubscriptionPeriod")
print(f"✅ Tìm thấy file StoreKit: {STOREKIT_CONFIG_FILE}")
print(f"   - Product ID: {found_sub.get('productID')}")
print(f"   - Subscription Group ID: {found_group_id}")
print(f"   - Recurring Period: {period}")
print(f"   - Storefront: {storefront}")

if period != "P1Y" or found_group_id != "21419447" or storefront != "VNM":
    print("⚠️ Cảnh báo cấu hình StoreKit không khớp hoàn toàn với đặc tả P1Y/21419447/VNM!")
else:
    print("✅ StoreKit Configuration File khớp 100% với yêu cầu.\n")

# 3. Fetch Offering & Verify Package từ RevenueCat API
print("--- [BƯỚC 2] FETCH OFFERING TỪ REVENUECAT LIVE API ---")
off_url = f"https://api.revenuecat.com/v1/subscribers/{APP_USER_ID}/offerings"
try:
    r_off = requests.get(off_url, headers=headers, timeout=15)
    r_off.raise_for_status()
    offerings_json = r_off.json()
    offerings_data = offerings_json.get("offerings", [])
    current_off_id = offerings_json.get("current_offering_id")
except Exception as e:
    print(f"❌ Lỗi kết nối RevenueCat Offerings: {e}")
    sys.exit(1)

target_off = next((o for o in offerings_data if o.get("identifier") == TARGET_OFFERING), None)
if not target_off and offerings_data:
    target_off = next((o for o in offerings_data if o.get("identifier") == current_off_id), offerings_data[0])

if not target_off:
    print(f"❌ Offering '{TARGET_OFFERING}': KHÔNG TÌM THẤY")
    sys.exit(1)
print(f"✅ Offering '{target_off.get('identifier')}': TÌM THẤY")

target_pkg = next((p for p in target_off.get("packages", []) if p.get("identifier") == TARGET_PACKAGE), None)
if not target_pkg:
    print(f"❌ Package '{TARGET_PACKAGE}': KHÔNG TÌM THẤY")
    sys.exit(1)
print(f"✅ Package '{TARGET_PACKAGE}': TÌM THẤY")

actual_product_id = target_pkg.get("platform_product_identifier")
if actual_product_id != EXPECTED_PRODUCT:
    print(f"❌ Product mismatch: Offering trỏ về '{actual_product_id}', kỳ vọng '{EXPECTED_PRODUCT}'")
    sys.exit(1)
print(f"✅ Product '{EXPECTED_PRODUCT}' khớp 100% giữa Offering và StoreKit Config!\n")

# 4. Query Subscriber Hiện Tại từ RevenueCat (Section 8)
print("--- [BƯỚC 3] REVENUECAT LIVE CHECK (GET /v1/subscribers/{app_user_id}) ---")
sub_url = f"https://api.revenuecat.com/v1/subscribers/{APP_USER_ID}"
try:
    r_sub = requests.get(sub_url, headers=headers, timeout=15)
    r_sub.raise_for_status()
    raw_subscriber_json = r_sub.json()
    sub_data = raw_subscriber_json.get("subscriber", {})
except Exception as e:
    print(f"❌ Lỗi query subscriber từ RevenueCat: {e}")
    sys.exit(1)

subscriptions = sub_data.get("subscriptions", {})
entitlements = sub_data.get("entitlements", {})

target_sub = subscriptions.get(EXPECTED_PRODUCT, {})
rc_store = target_sub.get("store")
rc_store_tx_id = target_sub.get("store_transaction_id")
rc_purchase_date = target_sub.get("purchase_date")
rc_expires_date = target_sub.get("expires_date")

# Kiểm tra entitlement Gold (có thể là "Gold" hoặc "gold")
gold_ent = entitlements.get("Gold") or entitlements.get("gold") or {}
gold_active = (gold_ent.get("product_identifier") == EXPECTED_PRODUCT) if gold_ent else False
sub_active = (EXPECTED_PRODUCT in subscriptions)
has_store_tx = (rc_store_tx_id is not None and len(str(rc_store_tx_id)) > 0)

print(f"   - Subscriptions hiện có: {list(subscriptions.keys())}")
print(f"   - Entitlements hiện có: {list(entitlements.keys())}")
print(f"   - Entitlement Gold active: {gold_active}")
print(f"   - store_transaction_id: {rc_store_tx_id}\n")

# 5. Đánh giá trạng thái và Master Fetch Token
# Theo Section 8, 9, 10:
# Nếu RevenueCat nhận local StoreKit purchase:
# - entitlement Gold active
# - store_transaction_id tồn tại
# -> final_status = "LOCAL_STOREKIT_REVENUECAT_ACTIVE"
# Nếu không:
# -> final_status = "REVENUECAT_LOCAL_STOREKIT_SYNC_FAILED"

if gold_active and has_store_tx:
    final_status = "LOCAL_STOREKIT_REVENUECAT_ACTIVE"
    master_fetch_token = rc_store_tx_id
    master_fetch_token_source = "REVENUECAT_STORE_TRANSACTION_ID"
    storekit_verified = True
else:
    final_status = "REVENUECAT_LOCAL_STOREKIT_SYNC_FAILED"
    master_fetch_token = None
    master_fetch_token_source = None
    storekit_verified = False

# fetch_token type là XCODE_LOCAL_STOREKIT_JWS (theo Section 7)
fetch_token = None
fetch_token_type = "XCODE_LOCAL_STOREKIT_JWS"

# 6. Build Section 11 Output JSON
section_11_output = {
    "app_user_id": APP_USER_ID,
    "product_id": EXPECTED_PRODUCT,
    "transaction_source": "XCODE_LOCAL_STOREKIT",
    "master_fetch_token": master_fetch_token,
    "master_fetch_token_source": master_fetch_token_source,
    "fetch_token": fetch_token,
    "fetch_token_type": fetch_token_type,
    "storekit": {
        "verified": storekit_verified,
        "transaction_id": rc_store_tx_id if has_store_tx else None,
        "original_transaction_id": target_sub.get("original_purchase_date") or rc_store_tx_id if has_store_tx else None,
        "purchase_date": rc_purchase_date,
        "expiration_date": rc_expires_date
    },
    "revenuecat": {
        "subscription_active": sub_active,
        "entitlement_gold_active": gold_active,
        "store_transaction_id": rc_store_tx_id
    },
    "final_status": final_status
}

print("================================================================================")
print("SECTION 11 OUTPUT JSON:")
print("================================================================================")
print(json.dumps(section_11_output, indent=2))
print("================================================================================\n")

if final_status == "LOCAL_STOREKIT_REVENUECAT_ACTIVE":
    print("🎉 KẾT QUẢ: Giao dịch StoreKit Local đã được RevenueCat đồng bộ và Gold ACTIVE!")
else:
    print("ℹ️ THÔNG BÁO: RevenueCat chưa nhận giao dịch StoreKit Local.")
    print("   Lý do: StoreKit Local transaction được ký bởi Xcode Local Certificate.")
    print("   Để RevenueCat backend chấp nhận transaction từ Xcode:")
    print("   1. Mở file 'LocketGold.storekit' trong Xcode.")
    print("   2. Chọn menu Editor > Save Public Certificate... để lưu file certificate (.cer).")
    print("   3. Vào RevenueCat Dashboard > Project Settings > Apps > [App Store].")
    print("   4. Upload file StoreKit Testing Certificate vừa lưu.")
    print("   5. Chạy app trên Xcode Simulator/Device với Scheme chọn StoreKit Configuration là 'LocketGold.storekit' và bấm Purchase.")
    print("   -> RevenueCat sẽ tự động nhận transaction và cấp quyền Gold ACTIVE!")

# 7. Ghi báo cáo ra file kq.txt
report_content = f"""================================================================================
XCODE LOCAL STOREKIT + REVENUECAT AUDIT REPORT
================================================================================
Mode:
XCODE_LOCAL_STOREKIT

App User ID:
{APP_USER_ID}

Offering:
{TARGET_OFFERING}

Package:
{TARGET_PACKAGE}

Product:
{EXPECTED_PRODUCT}

Entitlement Gold Active:
{"ACTIVE" if gold_active else "INACTIVE"}

Store Transaction ID:
{rc_store_tx_id}

Final Status:
{final_status}

================================================================================
SECTION 11 OUTPUT JSON:
================================================================================
{json.dumps(section_11_output, indent=2)}

================================================================================
HƯỚNG DẪN BƯỚC TIẾP THEO (XCODE LOCAL STOREKIT TESTING CERTIFICATE):
================================================================================
1. Mở file LocketGold.storekit trong Xcode.
2. Vào Editor -> Save Public Certificate...
3. Upload file certificate lên RevenueCat Dashboard (App Settings -> StoreKit Testing Certificate).
4. Run project trong Xcode (Scheme Options -> StoreKit Configuration: LocketGold.storekit).
5. Purchase trong App -> RevenueCat sẽ nhận transaction local và cấp quyền Gold ACTIVE.
================================================================================
"""

with open(OUTPUT_FILE, "w", encoding="utf-8") as f:
    f.write(report_content)

print(f"\n✅ Đã ghi thành công báo cáo vào file: {OUTPUT_FILE}")
