"""Extract local Android Firebase config without logging API keys or tokens."""
import argparse
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("config", type=Path, help="Your downloaded google-services.json")
    args = parser.parse_args()
    package = re.search(r"applicationId\s+['\"]([^'\"]+)", (ROOT / "android/app/build.gradle").read_text()).group(1)
    data = json.loads(args.config.expanduser().read_text())
    clients = [c for c in data["client"] if c["client_info"].get("android_client_info", {}).get("package_name") == package]
    if len(clients) != 1:
        raise SystemExit("Configuration must contain exactly one app matching the Gradle applicationId. Nothing changed.")
    client = clients[0]
    web = next((c["client_id"] for c in client.get("oauth_client", []) if c["client_type"] == 3), "")
    if not web:
        raise SystemExit("Enable Google sign-in and register your signing SHA-1, then download updated config. Web OAuth client missing; nothing changed.")
    result = dict(apiKey=client["api_key"][0]["current_key"], appId=client["client_info"]["mobilesdk_app_id"], projectId=data["project_info"]["project_id"], senderId=data["project_info"]["project_number"], webClientId=web)
    path = ROOT / "android/app/src/main/assets/firebase.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(result, indent=2) + "\n")
    print("Local Android Firebase configuration written. Keep it out of commits.")

if __name__ == "__main__":
    main()
