from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).with_name("app_version.sh")


class AppVersionTests(unittest.TestCase):
    def setUp(self):
        self.repo = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.repo)
        (self.repo / "LibraryMerger.xcodeproj").mkdir()
        self.git("init", "-q")
        self.set_floor("0.31.0")

    def git(self, *args):
        subprocess.run(
            ["git", "-c", "user.name=t", "-c", "user.email=t@t", *args],
            cwd=self.repo, check=True, capture_output=True,
        )

    def set_floor(self, version):
        """Commit the minimum version to a fictional Xcode project."""
        (self.repo / "LibraryMerger.xcodeproj/project.pbxproj").write_text(
            f"\t\t\t\tMARKETING_VERSION = {version};\n"
            "\t\t\t\tMARKETING_VERSION = 1.0;\n"
        )
        self.git("add", ".")
        self.git("commit", "-q", "-m", version)

    def version(self):
        return subprocess.run(
            [SCRIPT], cwd=self.repo, check=True, capture_output=True, text=True
        ).stdout.strip()

    def test_uses_the_project_without_tags(self):
        self.assertEqual(self.version(), "0.31.0")

    def test_goes_one_minor_past_the_newest_release(self):
        self.git("tag", "v0.31.0")
        self.git("commit", "-q", "--allow-empty", "-m", "next")
        self.assertEqual(self.version(), "0.32.0")
        self.git("tag", "v0.32.0")
        self.git("tag", "v0.32.0-beta")
        self.git("commit", "-q", "--allow-empty", "-m", "after")
        self.assertEqual(self.version(), "0.33.0")

    def test_ignores_a_tag_on_the_commit_itself(self):
        self.git("tag", "v0.31.0")
        self.assertEqual(self.version(), "0.31.0")

    def test_a_higher_project_version_wins(self):
        self.git("tag", "v0.31.0")
        self.set_floor("1.0.0")
        self.assertEqual(self.version(), "1.0.0")


if __name__ == "__main__":
    unittest.main()
