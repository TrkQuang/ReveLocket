import requests
import json

PUBLIC_KEY = "appl_JngFETzdodyLmCREOlwTUtXdQik"
APP_USER_ID = "1a73l0yKjleF7djpO7oYeP4u8ri1"

headers = {
    "Authorization": f"Bearer {PUBLIC_KEY}",
    "Accept": "application/json",
    "X-Platform": "ios",
}

def get_json(url):
    r = requests.get(url, headers=headers, timeout=20)

    print(f"\nGET {url}")
    print("HTTP:", r.status_code)

    try:
        data = r.json()
        print(json.dumps(data, indent=2, ensure_ascii=False))
        return data
    except Exception:
        print(r.text)
        return None


# 1. Customer / subscriber info
subscriber = get_json(
    f"https://api.revenuecat.com/v1/subscribers/{APP_USER_ID}"
)

# 2. Offerings / packages / product IDs
offerings = get_json(
    f"https://api.revenuecat.com/v1/subscribers/{APP_USER_ID}/offerings"
)


# 3. Tóm tắt riêng cho dễ nhìn
if subscriber:
    s = subscriber.get("subscriber", {})

    print("\n========== SUMMARY ==========")

    print("\nORIGINAL APP USER ID:")
    print(s.get("original_app_user_id"))

    print("\nALIASES:")
    print(json.dumps(s.get("other_purchases", {}), indent=2))

    print("\nSUBSCRIPTIONS:")
    for product_id, info in s.get("subscriptions", {}).items():
        print(f"\nProduct: {product_id}")
        print(json.dumps(info, indent=2, ensure_ascii=False))

    print("\nENTITLEMENTS:")
    for entitlement_id, info in s.get("entitlements", {}).items():
        print(f"\nEntitlement: {entitlement_id}")
        print(json.dumps(info, indent=2, ensure_ascii=False))


if offerings:
    print("\n========== OFFERINGS ==========")

    print("Current offering:")
    print(offerings.get("current_offering_id"))

    for offering in offerings.get("offerings", []):
        print("\nOffering:", offering.get("identifier"))

        for package in offering.get("packages", []):
            print(
                "  Package:",
                package.get("identifier"),
                "→ Product:",
                package.get("platform_product_identifier")
            )