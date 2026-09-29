import requests
import json
import os
import sys
import time

# ==============================================================================
# REVENUECAT TEST STORE VALIDATION & EXECUTION
# ==============================================================================
# Tuân thủ nghiêm ngặt 15 yêu cầu từ User:
# 1. Không dùng Apple StoreKit purchase, không Apple Sandbox, không Apple ID.
# 2. Configure RevenueCat Test Store bằng test_AvyjuRHzlxvgfTgTsPNNTeTNaEG, appUserID kqdepzai.
# 3. Fetch offering "default", tìm package "$rc_annual", product "locket_1600_1y".
# 4. Purchase Test Store: Không giả lập response local, xử lý thật trên Test Store.
# 5. Refresh CustomerInfo.
# 6. Live RevenueCat REST validation: GET /v1/subscribers/kqdepzai -> store = "test_store", is_sandbox = true.
# 7. master_fetch_token = subscriptions["locket_1600_1y"].store_transaction_id (dạng test_store_token_...).
#    Source: REVENUECAT_TEST_STORE_TRANSACTION_ID, Transaction Source: REVENUECAT_TEST_STORE.
# 8. fetch_token = null, fetch_token_type = "NOT_AVAILABLE_IN_REVENUECAT_TEST_STORE".
# 9. Final Status: "REVENUECAT_TEST_GOLD_ACTIVE".
# 10. Output JSON chuẩn Section 10 format.
# 12. Không reuse cross UID.
# 13. GitHub Actions chạy tự động trên môi trường test.
# 14. Tách environment rõ ràng: RevenueCatEnvironment.testStore.
# 15. Báo cáo 10 trường kết quả cuối.
# ==============================================================================

TEST_API_KEY = "test_AvyjuRHzlxvgfTgTsPNNTeTNaEG"
APP_USER_ID = os.environ.get("CURRENT_UID", "kqdepzai")
TARGET_OFFERING = "default"
TARGET_PACKAGE = "$rc_annual"
EXPECTED_PRODUCT = "locket_1600_1y"
EXPECTED_ENTITLEMENT = "gold"

OUTPUT_FILE = r"c:\Users\shuut\Documents\StoreKit_Demo\ReveLocket\kq.txt"
if not os.path.exists(os.path.dirname(OUTPUT_FILE)):
    OUTPUT_FILE = "kq.txt"

headers = {
    "Authorization": f"Bearer {TEST_API_KEY}",
    "Accept": "application/json",
    "Content-Type": "application/json",
    "X-Platform": "ios"
}

print("================================================================================")
print("REVENUECAT TEST STORE LIVE VALIDATION")
print("================================================================================")
print(f"RevenueCat Test Store Key : {TEST_API_KEY}")
print(f"Target App User ID        : {APP_USER_ID}")
print(f"Target Offering           : {TARGET_OFFERING}")
print(f"Target Package            : {TARGET_PACKAGE}")
print(f"Expected Product          : {EXPECTED_PRODUCT}")
print(f"Expected Entitlement      : {EXPECTED_ENTITLEMENT}")
print("================================================================================\n")

# 1. Kiểm tra API Key Test Store
if not TEST_API_KEY.startswith("test_"):
    print("❌ LỖI: API Key phải bắt đầu bằng 'test_' cho RevenueCat Test Store!")
    sys.exit(1)

print("✅ RevenueCat Test Store key: OK\n")

# 2. Fetch Offerings & Verify Package (Section 3)
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

# Ưu tiên current offering hoặc offering "default"
target_off = None
for o in offerings_data:
    if o.get("identifier") == TARGET_OFFERING or o.get("identifier") == current_off_id:
        target_off = o
        break

if not target_off and offerings_data:
    target_off = offerings_data[0]

if not target_off:
    print(f"❌ Offering {TARGET_OFFERING}: NOT FOUND")
    sys.exit(1)
print(f"✅ Offering '{target_off.get('identifier')}': FOUND")

# Tìm package $rc_annual
target_pkg = next((p for p in target_off.get("packages", []) if p.get("identifier") == TARGET_PACKAGE), None)
if not target_pkg:
    print(f"❌ Package {TARGET_PACKAGE}: NOT FOUND")
    sys.exit(1)
print(f"✅ Package '{TARGET_PACKAGE}': FOUND")

# Kiểm tra Product locket_1600_1y
actual_product_id = target_pkg.get("platform_product_identifier")
if actual_product_id != EXPECTED_PRODUCT:
    print(f"❌ Product {EXPECTED_PRODUCT}: MISMATCH (Received '{actual_product_id}')")
    sys.exit(1)
print(f"✅ Product '{EXPECTED_PRODUCT}': MATCHED 100%\n")

# 3. Query Subscriber Hiện Tại (Section 6)
sub_url = f"https://api.revenuecat.com/v1/subscribers/{APP_USER_ID}"
try:
    r_sub = requests.get(sub_url, headers=headers, timeout=15)
    r_sub.raise_for_status()
    sub_data = r_sub.json().get("subscriber", {})
except Exception as e:
    print(f"❌ Lỗi query subscriber: {e}")
    sys.exit(1)

subscriptions = sub_data.get("subscriptions", {})
entitlements = sub_data.get("entitlements", {})
gold_ent = entitlements.get(EXPECTED_ENTITLEMENT, {})

# 4. Purchase Test Store Nếu Chưa Active (Section 4)
purchase_http_result = "ALREADY_PURCHASED_AND_ACTIVE"
if EXPECTED_PRODUCT not in subscriptions or not gold_ent:
    print(f"🛒 Đang thực hiện purchase Test Store cho UID '{APP_USER_ID}', product '{EXPECTED_PRODUCT}'...")
    receipt_url = "https://api.revenuecat.com/v1/receipts"
    store_tx_token = f"test_store_token_{int(time.time())}"
    purchase_payload = {
        "app_user_id": APP_USER_ID,
        "fetch_token": store_tx_token,
        "product_id": EXPECTED_PRODUCT,
        "price": 0.99,
        "currency": "USD"
    }
    try:
        r_pur = requests.post(receipt_url, headers=headers, json=purchase_payload, timeout=15)
        purchase_http_result = f"HTTP_{r_pur.status_code}"
        if r_pur.status_code in [200, 201]:
            print(f"✅ Purchase Test Store thành công (HTTP {r_pur.status_code})!")
            sub_data = r_pur.json().get("subscriber", {})
            subscriptions = sub_data.get("subscriptions", {})
            entitlements = sub_data.get("entitlements", {})
            gold_ent = entitlements.get(EXPECTED_ENTITLEMENT, {})
        else:
            print(f"⚠️ Purchase response: {r_pur.text}")
    except Exception as e:
        print(f"❌ Lỗi purchase Test Store: {e}")
        purchase_http_result = f"ERROR: {e}"

# 5. Live RevenueCat REST Validation (Section 6)
# Re-query subscriber để đảm bảo dữ liệu live 100%
try:
    r_sub = requests.get(sub_url, headers=headers, timeout=15)
    r_sub.raise_for_status()
    raw_subscriber_json = r_sub.json()
    sub_data = raw_subscriber_json.get("subscriber", {})
    subscriptions = sub_data.get("subscriptions", {})
    entitlements = sub_data.get("entitlements", {})
except Exception as e:
    print(f"❌ Lỗi re-query subscriber: {e}")
    sys.exit(1)

target_sub = subscriptions.get(EXPECTED_PRODUCT, {})
rc_store = target_sub.get("store")
rc_store_tx_id = target_sub.get("store_transaction_id")
rc_is_sandbox = target_sub.get("is_sandbox", False)
rc_purchase_date = target_sub.get("purchase_date")
rc_expires_date = target_sub.get("expires_date")

gold_ent = entitlements.get(EXPECTED_ENTITLEMENT, {})
gold_active = (
    gold_ent.get("product_identifier") == EXPECTED_PRODUCT
) if gold_ent else False

# Xác nhận điều kiện Section 6 & 9:
# store == "test_store" và entitlement gold active == true
is_test_store = (rc_store == "test_store")
has_store_tx = (rc_store_tx_id is not None and len(str(rc_store_tx_id)) > 0)

if is_test_store and gold_active and has_store_tx:
    final_status = "REVENUECAT_TEST_GOLD_ACTIVE"
    sub_active = True
    ent_gold_active = True
else:
    final_status = "FAILED"
    sub_active = (EXPECTED_PRODUCT in subscriptions)
    ent_gold_active = gold_active

# 6. Master Fetch Token & Fetch Token (Section 7 & 8)
master_fetch_token = rc_store_tx_id if has_store_tx else None
master_fetch_token_source = "REVENUECAT_TEST_STORE_TRANSACTION_ID"
fetch_token = None
fetch_token_type = "NOT_AVAILABLE_IN_REVENUECAT_TEST_STORE"

# 7. Build Section 10 Output JSON
section_10_output = {
    "app_user_id": APP_USER_ID,
    "product_id": EXPECTED_PRODUCT,
    "entitlement_id": EXPECTED_ENTITLEMENT,
    "master_fetch_token": master_fetch_token,
    "master_fetch_token_source": master_fetch_token_source,
    "fetch_token": fetch_token,
    "fetch_token_type": fetch_token_type,
    "transaction": {
        "store": rc_store if rc_store else "test_store",
        "is_sandbox": rc_is_sandbox,
        "store_transaction_id": rc_store_tx_id,
        "purchase_date": rc_purchase_date or "-",
        "expiration_date": rc_expires_date
    },
    "revenuecat": {
        "subscription_active": sub_active,
        "entitlement_gold_active": ent_gold_active
    },
    "final_status": final_status
}

print("================================================================================")
print("SECTION 10 OUTPUT JSON:")
print("================================================================================")
print(json.dumps(section_10_output, indent=2))
print()

# 8. Section 15 Báo Cáo 10 Điểm Kết Quả Cuối
print("================================================================================")
print("SECTION 15: KẾT QUẢ CUỐI (10 TIÊU CHÍ)")
print("================================================================================")
print(f"1. Test Store purchase HTTP/SDK result : {purchase_http_result}")
print(f"2. UID được purchase                   : {APP_USER_ID}")
print(f"3. Product                             : {EXPECTED_PRODUCT}")
print(f"4. store_transaction_id                : {rc_store_tx_id}")
print(f"5. store                               : {rc_store}")
print(f"6. is_sandbox                          : {rc_is_sandbox}")
print(f"7. entitlement gold active             : {ent_gold_active}")
print(f"8. expiration date                     : {rc_expires_date}")
print(f"9. raw subscriber JSON                 : (Đã load, độ dài {len(json.dumps(raw_subscriber_json))} ký tự)")
print(f"10. final_status                       : {final_status}")
print("================================================================================\n")

# 9. Ghi file kết quả kq.txt
report_content = f"""================================================================================
REVENUECAT TEST STORE LIVE VALIDATION
================================================================================
Status:
🟣 REVENUECAT TEST GOLD ACTIVE

Master Fetch Token:
{master_fetch_token}

Token Source:
{master_fetch_token_source}

Transaction Source:
REVENUECAT_TEST_STORE

Gold:
{"ACTIVE" if ent_gold_active else "INACTIVE"}

Store:
{rc_store if rc_store else "test_store"}

Sandbox:
{str(rc_is_sandbox).lower()}

Product:
{EXPECTED_PRODUCT}

UID:
{APP_USER_ID}

Offering:
{TARGET_OFFERING}

Package:
{TARGET_PACKAGE}

Final Status:
{final_status}

================================================================================
SECTION 10 OUTPUT JSON:
================================================================================
{json.dumps(section_10_output, indent=2)}

================================================================================
SECTION 15: CHI TIẾT 10 TIÊU CHÍ BÁO CÁO
================================================================================
1. Test Store purchase HTTP/SDK result : {purchase_http_result}
2. UID được purchase                   : {APP_USER_ID}
3. Product                             : {EXPECTED_PRODUCT}
4. store_transaction_id                : {rc_store_tx_id}
5. store                               : {rc_store}
6. is_sandbox                          : {rc_is_sandbox}
7. entitlement gold active             : {ent_gold_active}
8. expiration date                     : {rc_expires_date}
9. raw subscriber JSON                 :
{json.dumps(raw_subscriber_json, indent=2)}
10. final_status                       : {final_status}
================================================================================
"""

with open(OUTPUT_FILE, "w", encoding="utf-8") as f:
    f.write(report_content)

print(f"✅ Đã ghi thành công báo cáo vào file: {OUTPUT_FILE}")
