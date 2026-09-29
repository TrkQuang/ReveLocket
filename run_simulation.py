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
APP_USER_ID = "1a73l0yKjleF7djpO7oYeP4u8ri1"
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
print("APPLE APP STORE CONFIG CHECK (ZERO TEST STORE / ZERO FAKE PURCHASE)")
print("================================================================================")

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

# Điều kiện khắt khe (Yêu cầu 6, 7, 8):
# Chỉ được coi là active khi có transaction thật từ store "app_store"
has_apple_subscription = (
    EXPECTED_PRODUCT in subscriptions and 
    rc_store == "app_store" and 
    rc_store_tx_id is not None
)

# 4. Đánh giá trạng thái StoreKit Purchase
# Vì trong môi trường CI/Terminal không có runtime StoreKit 2 device để thực thi Sandbox purchase:
if has_apple_subscription:
    apple_purchase_status = "EXECUTED (Apple Verified on Server)"
    master_fetch_token = rc_store_tx_id
    store_tx_display = rc_store_tx_id
    rc_active_display = "YES"
    transaction_source = "APPLE_SANDBOX" if rc_is_sandbox else "APPLE_PRODUCTION"
    final_status = "VERIFIED_ACTIVE"
else:
    apple_purchase_status = "NOT EXECUTED IN CI (DEVICE/SANDBOX ENVIRONMENT REQUIRED)"
    master_fetch_token = "NONE"
    store_tx_display = "NONE"
    rc_active_display = "NO"
    transaction_source = "APPLE_SANDBOX"
    final_status = "APPLE_SANDBOX_PURCHASE_REQUIRED"

print("Apple StoreKit Sandbox Purchase:")
print(f"{apple_purchase_status}\n")

print("Master Fetch Token:")
print(f"{master_fetch_token}\n")

print("Store Transaction:")
print(f"{store_tx_display}\n")

print("RevenueCat Subscription Active:")
print(f"{rc_active_display}\n")

print("Final Status:")
print(f"{final_status}\n")

# 5. Ghi báo cáo chuẩn vào kq.txt
ci_report = f"""================================================================================
APPLE APP STORE CONFIG CHECK (CI MODE)
================================================================================
RevenueCat appl key:
OK

Offering {TARGET_OFFERING}:
FOUND

Package {TARGET_PACKAGE}:
FOUND

Product {EXPECTED_PRODUCT}:
FOUND

Apple StoreKit Sandbox Purchase:
{apple_purchase_status}

Master Fetch Token:
{master_fetch_token}

Store Transaction:
{store_tx_display}

RevenueCat Subscription Active:
{rc_active_display}

Final Status:
{final_status}

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
1. Dự án ĐÃ XÓA HOÀN TOÀN RevenueCat Test Store (Không dùng test_ key, không tạo test_store_token).
2. Để chuyển trạng thái thành VERIFIED_ACTIVE:
   Cần chạy trực tiếp ứng dụng iOS trên Xcode/Simulator/Thiết bị thật đã đăng nhập tài khoản
   Apple Sandbox Tester, thực hiện purchase gói {EXPECTED_PRODUCT} qua StoreKit 2.
================================================================================
"""

with open(OUTPUT_FILE, "w", encoding="utf-8") as f:
    f.write(ci_report)

print(f"✅ Đã cập nhật file kết quả: {OUTPUT_FILE}")
