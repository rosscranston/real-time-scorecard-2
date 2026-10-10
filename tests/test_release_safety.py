import pathlib
import subprocess
import tempfile
import unittest
import zipfile

ROOT = pathlib.Path(__file__).resolve().parent.parent


class ReleaseSafetyTests(unittest.TestCase):
    def scan(self, members):
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / 'release.zip'
            with zipfile.ZipFile(path, 'w') as archive:
                for name, content in members.items():
                    archive.writestr(name, content)
            return subprocess.run(['python3', str(ROOT / 'scripts/verify-release.py'), str(path)],
                                  capture_output=True, text=True)

    def test_rejects_credentials_without_printing_them(self):
        credential = 'sk-proj-' + 'a' * 40
        result = self.scan({'project/settings.txt': credential})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('credential pattern', result.stdout)
        self.assertNotIn(credential, result.stdout + result.stderr)

    def test_rejects_private_runtime_files_and_unsafe_paths(self):
        result = self.scan({'project/.env': '', 'project/private-data/call.json': '{}', '../escape': 'x'})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('private/runtime file', result.stdout)
        self.assertIn('private/build content', result.stdout)
        self.assertIn('unsafe path', result.stdout)

    def test_allows_placeholder_example_and_source(self):
        result = self.scan({'project/.env.example': 'OPENAI_API_KEY=\n', 'project/README.md': 'Build instructions'})
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()
