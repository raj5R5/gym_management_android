import copy
import contextlib
import io
import json
import struct
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import urllib.request
import urllib.error
import warnings
import zipfile
from pathlib import Path
from play_release import validate_config, verify_elf, verify_jar_signature, verify_bundle, HttpsRedirects, PRODUCTION_API, main

VALID = {"APP_ENV": "production", "API_BASE_URL": PRODUCTION_API,
         "PLAY_APPLICATION_ID": "in.company.gym", "PLAY_APP_NAME": "MuscleDesk",
         "PUBLISHER_NAME": "Gym Company", "SUPPORT_EMAIL": "support@gym-company.com",
         "PRIVACY_POLICY_URL": "https://gym-company.com/privacy",
         "ACCOUNT_DELETION_URL": "https://gym-company.com/delete-account"}


class ReleaseChecks(unittest.TestCase):
    def test_valid(self):
        self.assertEqual(validate_config(VALID), [])

    def test_build_requires_url_checks_before_any_network_or_build_work(self):
        with patch("sys.argv", ["play_release.py", "--build"]), \
                patch("play_release.urllib.request.build_opener") as opener, \
                patch("play_release.subprocess.run") as run, \
                contextlib.redirect_stdout(io.StringIO()) as output:
            self.assertEqual(main(), 2)
            opener.assert_not_called()
            run.assert_not_called()
        self.assertIn("--build requires --check-urls", output.getvalue())

    def test_unpublished_privacy_page_names_http_blocker_and_never_builds(self):
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory) / "public-test-config.json"
            config.write_text(json.dumps(VALID))
            output = io.StringIO()
            with patch("sys.argv", ["play_release.py", "--config", str(config), "--check-urls", "--build"]), \
                    patch("play_release.urllib.request.build_opener") as opener, \
                    patch("play_release.subprocess.run") as run, contextlib.redirect_stdout(output):
                opener.return_value.open.side_effect = urllib.error.HTTPError(
                    VALID["PRIVACY_POLICY_URL"], 404, "Not Found", {}, None)
                self.assertEqual(main(), 2)
                run.assert_not_called()
            self.assertIn("PRIVACY_POLICY_URL returned HTTP 404", output.getvalue())
            self.assertNotIn(VALID["SUPPORT_EMAIL"], output.getvalue())

    def test_http_200_privacy_draft_never_reaches_the_build(self):
        class PublicResponse(io.BytesIO):
            url = VALID["PRIVACY_POLICY_URL"]
            status = 200
            headers = {"Content-Type": "text/html; charset=utf-8"}
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory) / "public-test-config.json"
            config.write_text(json.dumps(VALID))
            output = io.StringIO()
            with patch("sys.argv", ["play_release.py", "--config", str(config), "--check-urls", "--build"]), \
                    patch("play_release.urllib.request.build_opener") as opener, \
                    patch("play_release.subprocess.run") as run, contextlib.redirect_stdout(output):
                opener.return_value.open.return_value = PublicResponse(
                    '<html>DRAFT — NOT APPROVED FOR PUBLICATION.</html>'.encode())
                self.assertEqual(main(), 2)
                run.assert_not_called()
            self.assertIn("explicitly unapproved draft", output.getvalue())

    def test_public_html_and_health_pass_the_readiness_checks_without_building(self):
        class PublicResponse(io.BytesIO):
            status = 200
            def __init__(self, url, body, content_type):
                super().__init__(body)
                self.url = url
                self.headers = {"Content-Type": content_type}
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory) / "public-test-config.json"
            config.write_text(json.dumps(VALID))
            with patch("sys.argv", ["play_release.py", "--config", str(config), "--check-urls"]), \
                    patch("play_release.urllib.request.build_opener") as opener, \
                    patch("play_release.subprocess.run") as run, contextlib.redirect_stdout(io.StringIO()):
                opener.return_value.open.side_effect = [
                    PublicResponse(VALID["PRIVACY_POLICY_URL"], b'<html>Privacy policy test fixture</html>', 'text/html'),
                    PublicResponse(VALID["ACCOUNT_DELETION_URL"], b'<html>Deletion test fixture</html>', 'text/html'),
                    PublicResponse(PRODUCTION_API + 'health', b'{"success":true}', 'application/json'),
                ]
                self.assertEqual(main(), 0)
                self.assertEqual(opener.return_value.open.call_count, 3)
                run.assert_not_called()

    def test_incomplete_placeholder_or_unsafe_config_is_rejected(self):
        for key, value in [("APP_ENV", "development"), ("PLAY_APPLICATION_ID", "com.example.gym"),
                           ("PLAY_APP_NAME", "REPLACE"), ("SUPPORT_EMAIL", "not-an-email"),
                           ("PRIVACY_POLICY_URL", "http://gym-company.com/privacy"),
                           ("ACCOUNT_DELETION_URL", "https://user:secret@gym-company.com/delete"),
                           ("API_BASE_URL", "https://localhost/api/")]:
            with self.subTest(key=key):
                config = copy.deepcopy(VALID); config[key] = value
                self.assertTrue(validate_config(config))

    def test_unknown_fields_cannot_smuggle_secrets_into_dart_defines(self):
        config = {**VALID, "JWT_SECRET": "synthetic-only"}
        self.assertTrue(validate_config(config))

    def test_release_cannot_target_another_https_api(self):
        for url in ["https://staging.gym-company.com/api/v1/",
                    "https://gym-api.semgroup.in/", "https://gym-api.semgroup.in/api/v2/"]:
            with self.subTest(url=url):
                self.assertTrue(validate_config({**VALID, "API_BASE_URL": url}))

    def test_missing_public_details_are_named_without_values(self):
        errors = validate_config({**VALID, "PUBLISHER_NAME": "", "PRIVACY_POLICY_URL": ""})
        self.assertIn("PUBLISHER_NAME is missing or empty.", errors)
        self.assertIn("PRIVACY_POLICY_URL is missing or empty.", errors)

    def test_missing_or_non_string_fields_are_rejected(self):
        for value in [None, 123, ""]:
            config = {**VALID, "SUPPORT_EMAIL": value}
            self.assertTrue(validate_config(config))
        config = dict(VALID); del config["PLAY_APP_NAME"]
        self.assertTrue(validate_config(config))

    def test_native_alignment(self):
        data = bytearray(120); data[:6] = b"\x7fELF\x02\x01"
        struct.pack_into("<Q", data, 32, 64)
        struct.pack_into("<HH", data, 54, 56, 1)
        struct.pack_into("<I", data, 64, 1)
        struct.pack_into("<Q", data, 112, 16384)
        verify_elf(data)
        struct.pack_into("<Q", data, 112, 4096)
        with self.assertRaises(ValueError): verify_elf(data)
        with self.assertRaises(ValueError): verify_elf(b"not an ELF")

    def test_https_checks_never_follow_an_insecure_redirect(self):
        request = urllib.request.Request("https://gym-company.com/privacy")
        with self.assertRaises(ValueError):
            HttpsRedirects().redirect_request(request, None, 302, "Found", {}, "http://gym-company.com/privacy")

    def test_signature_verification_accepts_valid_or_self_signed_upload_key(self):
        for code, message in [(0, "jar verified."),
                              (4, "jar verified, with signer errors. This jar contains entries whose signer certificate is self-signed.")]:
            with self.subTest(code=code), patch("play_release.subprocess.run") as run:
                run.return_value = subprocess.CompletedProcess([], code, stdout=message, stderr="")
                verify_jar_signature(Path("synthetic.aab"))
                self.assertIn("-strict", run.call_args.args[0])

    def test_unsigned_payload_or_invalid_signature_never_passes(self):
        # Strict warning bits are OR-combined: 20 includes chain + unsigned entry.
        for code in [1, 8, 16, 20, 32, 64]:
            with self.subTest(code=code), patch("play_release.subprocess.run") as run:
                run.return_value = subprocess.CompletedProcess([], code, stdout="jar verified, with signer errors. self-signed", stderr="")
                with self.assertRaises(ValueError):
                    verify_jar_signature(Path("synthetic.aab"))

    def test_expired_not_yet_valid_or_unknown_certificate_warning_is_rejected(self):
        for message in ["self-signed; signer certificate has expired",
                        "certificate chain is invalid; signer certificate is not yet valid",
                        "unknown certificate warning"]:
            with self.subTest(message=message), patch("play_release.subprocess.run") as run:
                run.return_value = subprocess.CompletedProcess([], 4, stdout="jar verified, with signer errors. " + message, stderr="")
                with self.assertRaises(ValueError):
                    verify_jar_signature(Path("synthetic.aab"))

    def test_wholly_unsigned_jar_is_rejected_even_when_tool_exits_zero(self):
        with patch("play_release.subprocess.run") as run:
            run.return_value = subprocess.CompletedProcess([], 0, stdout="jar is unsigned.", stderr="")
            with self.assertRaises(ValueError):
                verify_jar_signature(Path("synthetic.aab"))

    def test_duplicate_bundle_entries_are_rejected_before_signature_tools(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "synthetic.aab"
            with zipfile.ZipFile(path, "w") as bundle, warnings.catch_warnings():
                warnings.simplefilter("ignore", UserWarning)
                bundle.writestr("base/manifest/AndroidManifest.xml", b"first")
                bundle.writestr("base/manifest/AndroidManifest.xml", b"duplicate")
            with patch("play_release.subprocess.run") as run:
                with self.assertRaisesRegex(ValueError, "duplicate"):
                    verify_bundle(path)
                run.assert_not_called()


if __name__ == "__main__":
    unittest.main()
