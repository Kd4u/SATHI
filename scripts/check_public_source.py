"""Check tracked public source for common credentials and accidental local files.

This focused check is a guardrail, not a complete secret scanner or security audit.
"""
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
paths = subprocess.check_output(["git", "ls-files", "-z"], cwd=ROOT).decode().split("\0")
patterns = [
    re.compile(r"AIza[0-9A-Za-z_-]{35}"),
    re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"),
    re.compile(r"gh[pousr]_[A-Za-z0-9]{30,}"),
    re.compile(r"[0-9]{8,}-[a-z0-9]+\.apps\.googleusercontent\.com"),
    re.compile(r"/(?:Users|Volumes)/[^\s\"'<>]+"),
]
bad = []
for name in filter(None, paths):
    path = ROOT / name
    if path.name in {"GoogleService-Info.plist", "google-services.json", "signing.properties", "local.properties"}:
        bad.append((name, "local configuration file"))
    if path.suffix.lower() in {".p12", ".p8", ".jks", ".keystore", ".mobileprovision", ".provisionprofile", ".apk", ".ipa", ".aab"}:
        bad.append((name, "private signing file or generated build"))
    if "xcuserdata" in path.parts or ("Accounts" in path.parts and "SyncChecks" not in path.parts):
        bad.append((name, "local user data"))
    if name.endswith("/assets/firebase.json"):
        bad.append((name, "production Firebase configuration"))
    try:
        text = path.read_text()
    except (UnicodeDecodeError, IsADirectoryError):
        continue
    if any(pattern.search(text) for pattern in patterns):
        bad.append((name, "credential or local-path pattern"))

if bad:
    for name, reason in bad:
        print(f"FAIL: {name}: {reason}")
    raise SystemExit(1)
print(f"Public-source check passed for {sum(bool(p) for p in paths)} tracked files.")
