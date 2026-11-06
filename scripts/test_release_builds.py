"""Exercise promotion against real Git history and a fake GitHub status API."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).with_name('testflight_builds.sh').resolve()


class BuildSelectionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.repo = Path(self.temp.name)
        self.git('init', '-q')
        (self.repo / 'app.swift').write_text('original')
        self.commit()
        self.built = self.git('rev-parse', 'HEAD').strip()
        bin_dir = self.repo / 'bin'
        bin_dir.mkdir()
        gh = bin_dir / 'gh'
        gh.write_text('#!/bin/bash\nif [[ $2 == *"/$BUILT/status" ]]; then\n'
                      '  echo "${STATUS:-0.10.1 (12)}"\nfi\n')
        gh.chmod(0o755)
        self.env = {**os.environ, 'PATH': f'{bin_dir}:{os.environ["PATH"]}',
                    'GITHUB_REPOSITORY': 'fictional/app', 'BUILT': self.built}

    def git(self, *args):
        return subprocess.check_output(
            ['git', '-c', 'core.fsmonitor=false', '-c', 'user.name=Test', '-c', 'user.email=test@example.com', *args],
            cwd=self.repo, text=True)

    def commit(self):
        """Commit only app and documentation fixtures, excluding fake tools."""
        self.git('add', 'app.swift', '*.md') if list(self.repo.glob('*.md')) else self.git('add', 'app.swift')
        self.git('commit', '-qm', 'fixture')

    def run_script(self):
        return subprocess.run([SCRIPT, 'HEAD'], cwd=self.repo, env=self.env,
                              text=True, capture_output=True)

    def test_selects_the_uploaded_build(self):
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, f'commit={self.built}\nversion=0.10.1\nios=12\n')

    def test_documentation_can_reuse_the_build(self):
        (self.repo / 'README.md').write_text('Documentation')
        self.commit()
        self.assertEqual(self.run_script().returncode, 0)

    def test_app_change_requires_a_new_build(self):
        (self.repo / 'app.swift').write_text('changed')
        self.commit()
        result = self.run_script()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('app changed', result.stderr)

    def test_missing_status_stops_promotion(self):
        self.env['BUILT'] = 'missing'
        self.assertNotEqual(self.run_script().returncode, 0)

    def test_malformed_status_stops_promotion(self):
        self.env['STATUS'] = 'not a version'
        self.assertNotEqual(self.run_script().returncode, 0)
