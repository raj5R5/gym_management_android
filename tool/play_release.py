#!/usr/bin/env python3
"""Fail-closed local Play preparation. Standard library only; never uploads."""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import ssl
import struct
import subprocess
import sys
import urllib.error
import urllib.request
from urllib.parse import urlsplit
import zipfile

ROOT = Path(__file__).resolve().parents[1]
PRODUCTION_API = "https://gym-api.semgroup.in/api/v1/"
FIELDS = {"APP_ENV", "API_BASE_URL", "PLAY_APPLICATION_ID", "PLAY_APP_NAME",
          "PUBLISHER_NAME", "SUPPORT_EMAIL", "PRIVACY_POLICY_URL", "ACCOUNT_DELETION_URL"}


class HttpsRedirects(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        if urlsplit(newurl).scheme != "https":
            raise ValueError("Public release checks refuse a non-HTTPS redirect.")
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def validate_config(config):
    errors = []
    if set(config) != FIELDS or any(not isinstance(v, str) or not v.strip() for v in config.values()):
        errors.append("Use exactly the nonempty public fields in release/production.example.json; no secrets.")
    for key in sorted(FIELDS):
        value = config.get(key)
        if not isinstance(value, str) or not value.strip():
            errors.append(f"{key} is missing or empty.")
    for key in FIELDS:
        value = config.get(key, "")
        if not isinstance(value, str):
            continue
        if re.search(r"replace|placeholder|example\.|\.test(?:/|$)|\.invalid(?:/|$)", value, re.I):
            errors.append(f"{key} is still a placeholder.")
    if config.get("APP_ENV") != "production":
        errors.append("APP_ENV must be production.")
    if config.get("API_BASE_URL") != PRODUCTION_API:
        errors.append("API_BASE_URL must be the approved MuscleDesk production API URL.")
    if config.get("PLAY_APP_NAME") != "MuscleDesk":
        errors.append("PLAY_APP_NAME must be MuscleDesk.")
    app_id = config.get("PLAY_APPLICATION_ID", "")
    if not isinstance(app_id, str) or not re.fullmatch(r"[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*){2,}", app_id):
        errors.append("PLAY_APPLICATION_ID must be the final reverse-domain Android ID.")
    for key in ["API_BASE_URL", "PRIVACY_POLICY_URL", "ACCOUNT_DELETION_URL"]:
        value = config.get(key, "")
        if not isinstance(value, str):
            continue
        try:
            url = urlsplit(value)
            if (url.scheme != "https" or not url.hostname or url.username or url.password or
                    url.query or url.fragment or url.hostname in ["localhost", "127.0.0.1", "::1"]):
                raise ValueError()
        except ValueError:
            errors.append(f"{key} must be a public HTTPS URL without credentials, query or fragment.")
    if not re.fullmatch(r"[^\s@]+@[^\s@]+\.[^\s@]+", str(config.get("SUPPORT_EMAIL", ""))):
        errors.append("SUPPORT_EMAIL must be a public support/privacy email.")
    return errors


def verify_elf(data):
    """Check every 64-bit ELF PT_LOAD, not ZIP padding or runtime compatibility."""
    if data[:5] != b"\x7fELF\x02" or data[5] != 1:
        raise ValueError("Expected a little-endian 64-bit ELF library.")
    offset = struct.unpack_from("<Q", data, 32)[0]
    size, count = struct.unpack_from("<HH", data, 54)
    loads = 0
    for index in range(count):
        start = offset + index * size
        if struct.unpack_from("<I", data, start)[0] == 1:
            loads += 1
            file_offset, address = struct.unpack_from("<QQ", data, start + 8)
            alignment = struct.unpack_from("<Q", data, start + 48)[0]
            if alignment < 16384 or alignment & (alignment - 1) or file_offset % 16384 != address % 16384:
                raise ValueError("A load segment does not support 16 KB alignment.")
    if not loads:
        raise ValueError("No loadable segments.")


def verify_jar_signature(path):
    # Ordinary verification exits 0 even for unsigned entries added after signing.
    # Strict status 4 also covers the normal untrusted chain of a self-signed
    # upload key; accept only that known warning, never expired/invalid dates.
    result = subprocess.run(
        ["jarsigner", "-J-Duser.language=en", "-J-Duser.country=US",
         "-verify", "-strict", str(path)], capture_output=True, text=True)
    output = (result.stdout + result.stderr).lower()
    # Even strict jarsigner can exit 0 for a wholly unsigned archive.
    if not re.search(r"\bjar verified\b", output):
        raise ValueError("Bundle has no verified JAR signature.")
    if result.returncode == 0:
        return
    if (result.returncode == 4 and
            ("self-signed" in output or "certificate chain is invalid" in output) and
            not re.search(r"expired|not yet valid", output)):
        print("JAR signature verified; self-signed upload-key chain warning accepted.")
        return
    raise ValueError("Bundle signature verification failed or includes unsigned/invalid entries.")


def verify_bundle(path):
    with zipfile.ZipFile(path) as bundle:
        names = bundle.namelist()
        if len(names) != len(set(names)):
            raise ValueError("Bundle contains ambiguous duplicate archive entries.")
        if "base/manifest/AndroidManifest.xml" not in names:
            raise ValueError("Not an Android App Bundle.")
        if not any(re.fullmatch(r"META-INF/[^/]+\.(RSA|DSA|EC)", n, re.I) for n in names):
            raise ValueError("Bundle is not signed.")
        libraries = [n for n in names if n.endswith(".so") and "/lib/" in n]
        for abi in ["arm64-v8a", "armeabi-v7a", "x86_64"]:
            for library in ["libapp.so", "libflutter.so"]:
                if f"base/lib/{abi}/{library}" not in names:
                    raise ValueError(f"Missing {abi}/{library}.")
        checked = 0
        for name in libraries:
            if "/arm64-v8a/" in name or "/x86_64/" in name:
                verify_elf(bundle.read(name))
                checked += 1
    verify_jar_signature(path)
    certificate = subprocess.check_output(["keytool", "-printcert", "-jarfile", str(path)], text=True)
    if re.search(r"CN\s*=\s*Android Debug", certificate, re.I):
        raise ValueError("Debug signing certificate is forbidden.")
    print(f"Signed bundle verified; {checked} native 64-bit libraries pass ELF alignment checks.")
    print("Still run Play pre-launch tests and a 16 KB emulator/device check; ELF inspection alone is not runtime proof.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, default=ROOT / "release/production.json")
    parser.add_argument("--check-urls", action="store_true", help="Read-only public HTTPS policy/health checks")
    parser.add_argument("--build", action="store_true", help="Run analyze, full tests, then build a signed AAB")
    parser.add_argument("--verify-bundle", type=Path)
    parser.add_argument("--flutter", default=os.environ.get("FLUTTER", "flutter"))
    parser.add_argument("--ca-file", type=Path, help="Optional trusted CA bundle for Python TLS checks; TLS verification is never disabled")
    args = parser.parse_args()
    if args.verify_bundle:
        verify_bundle(args.verify_bundle)
        return 0
    if args.build and not args.check_urls:
        print("BLOCKED: --build requires --check-urls; an unpublished or explicitly unapproved privacy policy must not be skipped.")
        return 2
    if not args.config.is_file():
        print("BLOCKED: Final public identity/contact/URLs are deferred. Copy release/production.example.json when decided.")
        return 2
    config = json.loads(args.config.read_text())
    errors = validate_config(config) if isinstance(config, dict) else ["Config must be a JSON object."]
    if errors:
        print("\n".join(f"BLOCKED: {message}" for message in errors))
        return 2
    if args.check_urls:
        context = ssl.create_default_context(cafile=str(args.ca_file) if args.ca_file else None)
        opener = urllib.request.build_opener(urllib.request.HTTPSHandler(context=context), HttpsRedirects())
        for key in ["PRIVACY_POLICY_URL", "ACCOUNT_DELETION_URL"]:
            request = urllib.request.Request(config[key], headers={"User-Agent": "GymReleaseReadiness/1.0"})
            try:
                response = opener.open(request, timeout=20)
            except urllib.error.HTTPError as error:
                print(f"BLOCKED: {key} returned HTTP {error.code}; it must serve the approved public HTML page.")
                return 2
            with response:
                if urlsplit(response.url).scheme != "https" or response.status != 200 or "text/html" not in response.headers.get("Content-Type", ""):
                    raise ValueError(f"{key} must return a public HTTPS HTML page.")
                if key == "PRIVACY_POLICY_URL":
                    document = response.read().decode("utf-8", errors="replace")
                    if re.search(r"DRAFT\s*(?:—|&mdash;|&#8212;|-)\s*NOT APPROVED FOR PUBLICATION", document, re.I):
                        print("BLOCKED: PRIVACY_POLICY_URL still serves an explicitly unapproved draft.")
                        return 2
            print(f"{key}: reachable; manually review content and deletion submission.")
        with opener.open(config["API_BASE_URL"].rstrip("/") + "/health", timeout=20) as response:
            body = json.load(response)
            if response.status != 200 or body.get("success") is not True:
                raise ValueError("Production API health check failed.")
        print("API health reachable; this does not verify database backups or mutation flows.")
    print("Public production configuration is valid. No credentials were printed.")
    if args.build:
        flutter = shutil.which(args.flutter)
        if not flutter:
            raise ValueError("Flutter executable not found; set --flutter or FLUTTER.")
        for command in [[flutter, "analyze", "--no-pub"], [flutter, "test", "--no-pub"],
                        [flutter, "build", "appbundle", "--release", "--no-pub", f"--dart-define-from-file={args.config.resolve()}"]]:
            subprocess.run(command, cwd=ROOT, check=True)
        verify_bundle(ROOT / "build/app/outputs/bundle/release/app-release.aab")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (ValueError, OSError, subprocess.CalledProcessError, zipfile.BadZipFile) as error:
        # Values/credentials never enter errors from our validators.
        print(f"Release preparation failed: {type(error).__name__}. Review the preceding validation/build output.")
        sys.exit(1)
