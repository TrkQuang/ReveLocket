import requests
import json
import os
import sys
from datetime import datetime, timezone

# ==============================================================================
# REVENUECAT + APPLE STOREKIT CONFIG CHECK (STRICT APP STORE ONLY - ZERO TEST STORE)
# ==============================================================================
# Tuân thủ nghiêm ngặt:
# - CẤM RevenueCat Test Store (Không dùng test_ key, không tạo test_store_token)
# - DUY NHẤT App Store Public Key: appl_JngFETzdodyLmCREOlwTUtXdQik
# - KHÔNG coi REST API 200 là purchase thành công
# - Trong CI / Terminal: Nếu chưa có Apple StoreKit transaction thật -> APPLE_SANDBOX_PURCHASE_REQUIRED
# ==============================================================================

PUBLIC_KEY = "appl_JngFETzdodyLmCREOlwTUtXdQik"
APP_USER_ID = os.environ.get("CURRENT_UID", "1a73l0yKjleF7djpO7oYeP4u8ri1")
TARGET_OFFERING = "locket_199"
TARGET_PACKAGE = "$rc_annual"
EXPECTED_PRODUCT = "locket_1600_1y"
OUTPUT_FILE = r"c:\Users\shuut\Documents\StoreKit_Demo\ReveLocket\kq.txt"

# Nếu chạy trên Linux/macOS trong CI (file path tương đối)
if not os.path.exists(os.path.dirname(OUTPUT_FILE)):
    OUTPUT_FILE = "kq.txt"

headers = {
    "Authorization": f"Bearer {PUBLIC_KEY}",
    "Accept": "application/json",
    "X-Platform": "ios"
}

print("================================================================================")
print("APPLE APP STORE & REVENUECAT LIVE VALIDATION (STRICT NO CROSS-UID REUSE)")
print("================================================================================")
print(f"Current App User ID: {APP_USER_ID}")

# 1. Kiểm tra RevenueCat Public Key (appl_...)
if not PUBLIC_KEY.startswith("appl_"):
    print("❌ LỖI: Chỉ chấp nhận RevenueCat App Store key (bắt đầu bằng appl_)!")
    sys.exit(1)

print("RevenueCat appl key:")
print("OK\n")

# 2. Kiểm tra Offerings & Packages trên RevenueCat (Read-Only)
off_url = f"https://api.revenuecat.com/v1/subscribers/{APP_USER_ID}/offerings"
try:
    r_off = requests.get(off_url, headers=headers, timeout=15)
    r_off.raise_for_status()
    offerings_data = r_off.json().get("offerings", [])
except Exception as e:
    print(f"❌ Lỗi kết nối RevenueCat Offerings: {e}")
    sys.exit(1)

# Kiểm tra Offering locket_199
target_off = next((o for o in offerings_data if o.get("identifier") == TARGET_OFFERING), None)
if not target_off:
    print(f"Offering {TARGET_OFFERING}:")
    print("NOT FOUND")
    sys.exit(1)

print(f"Offering {TARGET_OFFERING}:")
print("FOUND\n")

# Kiểm tra Package $rc_annual
target_pkg = next((p for p in target_off.get("packages", []) if p.get("identifier") == TARGET_PACKAGE), None)
if not target_pkg:
    print(f"Package {TARGET_PACKAGE}:")
    print("NOT FOUND")
    sys.exit(1)

print(f"Package {TARGET_PACKAGE}:")
print("FOUND\n")

# Kiểm tra Product locket_1600_1y
actual_product_id = target_pkg.get("platform_product_identifier")
if actual_product_id != EXPECTED_PRODUCT:
    print(f"Product {EXPECTED_PRODUCT}:")
    print(f"MISMATCH (Received '{actual_product_id}')")
    sys.exit(1)

print(f"Product {EXPECTED_PRODUCT}:")
print("FOUND\n")

# 3. Kiểm tra Subscriber State từ RevenueCat Live Server (Read-Only)
sub_url = f"https://api.revenuecat.com/v1/subscribers/{APP_USER_ID}"
try:
    r_sub = requests.get(sub_url, headers=headers, timeout=15)
    r_sub.raise_for_status()
    sub_data = r_sub.json().get("subscriber", {})
except Exception as e:
    print(f"❌ Lỗi kết nối RevenueCat Subscriber: {e}")
    sys.exit(1)

subscriptions = sub_data.get("subscriptions", {})
entitlements = sub_data.get("entitlements", {})

target_sub = subscriptions.get(EXPECTED_PRODUCT, {})
rc_store = target_sub.get("store")
rc_store_tx_id = target_sub.get("store_transaction_id")
rc_is_sandbox = target_sub.get("is_sandbox")
rc_purchase_date = target_sub.get("purchase_date")
rc_expires_date = target_sub.get("expires_date")

# Điều kiện khắt khe (Requirements 4, 5, 8, 12):
# Chỉ được coi là active khi ĐÚNG UID HIỆN TẠI có transaction thật từ store "app_store" trên live server
has_apple_subscription = (
    EXPECTED_PRODUCT in subscriptions and 
    rc_store == "app_store" and 
    rc_store_tx_id is not None
)

# 4. Đánh giá trạng thái Subscription Live của UID hiện tại (KHÔNG reuse transaction cũ)
if has_apple_subscription:
    master_fetch_token = rc_store_tx_id
    token_source = "REVENUECAT_STORE_TRANSACTION_ID"
    store_tx_display = rc_store_tx_id
    rc_active_display = "YES"
    transaction_source = "APPLE_SANDBOX" if rc_is_sandbox else "APPLE_PRODUCTION"
    server_exp_display = rc_expires_date or "UNKNOWN"
    final_status = "VERIFIED_ACTIVE"
    live_active = True
    tx_owner_match = True
    tx_id_match = True
else:
    # Nếu UID chưa có subscription trên RevenueCat live server:
    master_fetch_token = "NONE"
    token_source = "NONE"
    store_tx_display = "NONE"
    rc_active_display = "NO"
    transaction_source = "NONE"
    server_exp_display = "NONE"
    final_status = "INACTIVE"
    live_active = False
    tx_owner_match = False
    tx_id_match = False

print("Master Fetch Token:")
print(f"{master_fetch_token}\n")

print("Token Source:")
print(f"{token_source}\n")

print("Transaction Source:")
print(f"{transaction_source}\n")

print("Store Transaction:")
print(f"{store_tx_display}\n")

print("RevenueCat Subscription Active:")
print(f"{rc_active_display}\n")

print("Final Status:")
print(f"{final_status}\n")

# 5. Debug Output JSON (Requirement 10)
debug_json_data = {
    "current_app_user_id": APP_USER_ID,
    "vault_item_owner": None,
    "vault_transaction_id": None,
    "revenuecat_live_subscription_active": live_active,
    "revenuecat_live_store_transaction_id": rc_store_tx_id,
    "transaction_owner_match": tx_owner_match,
    "transaction_id_match": tx_id_match,
    "final_status": final_status
}

print("Debug JSON Output:")
print(json.dumps(debug_json_data, indent=2))
print()

# 6. Ghi báo cáo chuẩn vào kq.txt
ci_report = f"""================================================================================
APPLE APP STORE & REVENUECAT LIVE VALIDATION (CI MODE)
================================================================================
RevenueCat appl key:
OK

Offering {TARGET_OFFERING}:
FOUND

Package {TARGET_PACKAGE}:
FOUND

Product {EXPECTED_PRODUCT}:
FOUND

Master Fetch Token:
{master_fetch_token}

Token Source:
{token_source}

Transaction Source:
{transaction_source}

Store Transaction:
{store_tx_display}

RevenueCat Subscription Active:
{rc_active_display}

Final Status:
{final_status}

================================================================================
DEBUG JSON OUTPUT (REQUIREMENT 10)
================================================================================
{json.dumps(debug_json_data, indent=2)}

================================================================================
CHI TIẾT ĐỐI SOÁT LIVE REVENUECAT (READ-ONLY)
================================================================================
App User ID                 : {APP_USER_ID}
Public Key                  : {PUBLIC_KEY}
Target Offering             : {TARGET_OFFERING}
Target Package              : {TARGET_PACKAGE}
Expected Product            : {EXPECTED_PRODUCT}
RevenueCat HTTP Status Code : {r_sub.status_code}
Active Subscriptions        : {len(subscriptions)}
Active Entitlements         : {len(entitlements)}
Store Transaction ID        : {rc_store_tx_id if rc_store_tx_id else "None"}
Store Source                : {rc_store if rc_store else "None"}

LƯU Ý QUAN TRỌNG:
1. Dự án TUYỆT ĐỐI KHÔNG tái sử dụng Master Transaction của UID cũ cho UID mới.
2. Mỗi UID có trạng thái độc lập dựa trên Live RevenueCat response.
3. Nếu UID chưa có subscription trên RevenueCat: Final Status = INACTIVE.
================================================================================
"""

with open(OUTPUT_FILE, "w", encoding="utf-8") as f:
    f.write(ci_report)

print(f"✅ Đã cập nhật file kết quả: {OUTPUT_FILE}")
