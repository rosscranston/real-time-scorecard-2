import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("test_decisions", Path(__file__).resolve().parents[1] / "scripts/test_decisions.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class ConnectionHarnessTests(unittest.TestCase):
    def valid_response(self):
        return {"answers": [
            {"name": "tax_software", "type": "choice", "choice": "Drake", "confidence": 0.97},
            {"name": "hosting_environment", "type": "choice", "choice": "on_premises", "confidence": 0.93},
        ]}

    def test_response_checked_by_name_not_order(self):
        response = self.valid_response()
        response["answers"].reverse()
        self.assertEqual(len(module.validate_answers(response)), 2)

    def test_refusal_wrong_choice_duplicates_and_nonfinite_rejected(self):
        for change in ({"type": "refusal"}, {"choice": "Lacerte"}, {"confidence": float("nan")}, {"name": "hosting_environment"}):
            with self.subTest(change=change):
                response = self.valid_response()
                response["answers"][0].update(change)
                with self.assertRaises(ValueError):
                    module.validate_answers(response)

    def test_env_is_data_and_process_env_takes_precedence(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / ".env"
            path.write_text('OPENAI_API_KEY="fake-file-key"\nOPENAI_DECISIONS_MODEL=$(do-not-run)\n')
            with patch.dict(module.os.environ, {"OPENAI_API_KEY": "fake-process-key"}, clear=True):
                settings = module.read_settings(path)
            self.assertEqual(settings["OPENAI_API_KEY"], "fake-process-key")
            self.assertEqual(settings["OPENAI_DECISIONS_MODEL"], "$(do-not-run)")

    def test_redirect_does_not_forward_credentials(self):
        self.assertIsNone(module.NoRedirect().redirect_request(None, None, 302, "", {}, "https://example.com"))

    def test_dry_run_neither_reads_keys_nor_sends_request(self):
        with patch.object(module.sys, "argv", ["test_decisions.py", "--dry-run"]), patch.object(module, "read_settings") as read, patch.object(module.urllib.request, "build_opener") as network:
            self.assertEqual(module.main(), 0)
            read.assert_not_called()
            network.assert_not_called()


if __name__ == "__main__":
    unittest.main()
