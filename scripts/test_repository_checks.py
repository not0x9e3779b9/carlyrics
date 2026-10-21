import unittest

from validate_repository import configuration_issues, inspect_file


class RepositorySafeguardTests(unittest.TestCase):
    def test_local_configuration_is_rejected_without_reading_its_value(self):
        for path in ["Config.local.xcconfig", ".env", "ios/.env.production"]:
            self.assertTrue(inspect_file(path, b""), path)

    def test_signing_files_and_build_state_are_rejected(self):
        for path in ["certificate.p12", "private.p8", "signing.pfx", "secret.key", "profile.mobileprovision", "ios/xcuserdata/state", ".build/output"]:
            self.assertTrue(inspect_file(path, b""), path)

    def test_high_confidence_secret_pattern_is_rejected_and_redacted(self):
        synthetic = b"ghp_" + b"Z" * 36
        result = inspect_file("example.txt", synthetic)
        self.assertTrue(result)
        self.assertNotIn(synthetic.decode(), " ".join(result))

    def test_private_key_header_is_rejected(self):
        header = b"-----BEGIN " + b"PRIVATE KEY-----"
        self.assertTrue(inspect_file("unsafe.txt", header))

    def test_encrypted_private_key_is_rejected(self):
        header = b"-----BEGIN " + b"ENCRYPTED PRIVATE KEY-----"
        self.assertTrue(inspect_file("unsafe.pem", header))

    def test_literal_oauth_material_is_rejected(self):
        assignment = b'let clientSecret = ' + b'"synthetic-sensitive-material"'
        result = inspect_file("Sources/Unsafe.swift", assignment)
        self.assertTrue(result)
        self.assertNotIn("synthetic-sensitive-material", " ".join(result))

    def test_swift_response_coding_keys_are_not_credentials(self):
        source = b'case accessToken = "access_token", refreshToken = "refresh_token"'
        self.assertEqual(inspect_file("Sources/Response.swift", source), [])

    def test_public_client_placeholders_and_test_names_are_allowed(self):
        self.assertEqual(inspect_file("Config.example.xcconfig", b"SPOTIFY_CLIENT_ID = REPLACE_WITH_SPOTIFY_CLIENT_ID"), [])
        self.assertEqual(inspect_file("Test.swift", b"let refreshToken = fixture.refreshToken"), [])

    def test_core_platform_boundary_is_enforced(self):
        self.assertTrue(inspect_file("Sources/LyricsCore/Bad.swift", b"import SwiftUI"))
        self.assertEqual(inspect_file("Sources/LyricsCore/Good.swift", b"import Foundation"), [])
        self.assertEqual(inspect_file("ios/App.swift", b"import SwiftUI"), [])

    def test_missing_or_unsafe_configuration_is_reported(self):
        issues = configuration_issues("SPOTIFY_LYRICS_ENABLED = YES\nSPOTIFY_CLIENT_SECRET = value\n", "")
        self.assertTrue(any("client secret" in issue for issue in issues))
        self.assertTrue(any("disabled" in issue for issue in issues))
        self.assertTrue(any("Missing example" in issue for issue in issues))


if __name__ == "__main__":
    unittest.main()
