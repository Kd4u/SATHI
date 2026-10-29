"""Install your Apple Firebase configuration and matching Google callback locally."""
import argparse
import plistlib
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("config", type=Path, help="Your downloaded GoogleService-Info.plist")
    args = parser.parse_args()
    config = plistlib.loads(args.config.expanduser().read_bytes())
    project = (ROOT / "apple/SWIFT.xcodeproj/project.pbxproj").read_text()
    bundle = re.search(r"PRODUCT_BUNDLE_IDENTIFIER\s*=\s*([^;]+);", project).group(1).strip(' "')
    if config.get("BUNDLE_ID") != bundle:
        raise SystemExit("Config bundle ID does not match the app target. Nothing changed.")
    client, scheme = config.get("CLIENT_ID"), config.get("REVERSED_CLIENT_ID")
    if not client or not scheme or scheme != ".".join(reversed(client.split("."))):
        raise SystemExit("A matching Google client ID and reversed callback are required. Nothing changed.")
    path = ROOT / "apple/AppInfo.plist"
    info = plistlib.loads(path.read_bytes())
    info["GIDClientID"] = client
    info["CFBundleURLTypes"] = [{"CFBundleURLName": "Google sign-in", "CFBundleURLSchemes": [scheme]}]
    (ROOT / "apple/SWIFT/GoogleService-Info.plist").write_bytes(plistlib.dumps(config))
    path.write_bytes(plistlib.dumps(info))
    print("Local Apple Firebase configuration and callback written. Do not commit production values.")

if __name__ == "__main__":
    main()
