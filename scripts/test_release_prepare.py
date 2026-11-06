"""Check release preparation without credentials or App Store writes."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).with_name('prepare_release.sh').resolve()


class PrepareReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / 'whats-new.txt').write_text('A useful update.')
        self.log = self.root / 'calls.jsonl'
        asc = self.root / 'asc'
        asc.write_text('''#!/usr/bin/env python3
import json, os, sys
args = sys.argv[1:]
with open(os.environ['CALLS'], 'a') as log:
    log.write(json.dumps(args) + '\\n')
if args[:2] == ['versions', 'list']:
    print(os.environ['VERSIONS'])
elif args[:2] == ['builds', 'list']:
    print('{"data":[{"id":"tested-build"}]}')
''')
        asc.chmod(0o755)
        self.env = {**os.environ, 'PATH': f'{self.root}:{os.environ["PATH"]}',
                    'ASC_APP_ID': 'fictional', 'VERSION': '0.10.1', 'IOS_BUILD': '12',
                    'RUNNER_TEMP': str(self.root), 'CALLS': str(self.log),
                    'GITHUB_STEP_SUMMARY': str(self.root / 'summary')}

    def run_prepare(self, state, version='0.10.1'):
        """Run against an existing version and return recorded ASC calls."""
        self.env['VERSIONS'] = json.dumps({'data': [{'id': 'version-id', 'attributes': {
            'versionString': version, 'appStoreState': state, 'releaseType': 'MANUAL'}}]})
        result = subprocess.run([SCRIPT], env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        return [json.loads(line) for line in self.log.read_text().splitlines()]

    def test_prepares_the_tested_build_without_submitting(self):
        calls = self.run_prepare('PREPARE_FOR_SUBMISSION')
        attach = next(c for c in calls if c[:2] == ['versions', 'attach-build'])
        self.assertIn('tested-build', attach)
        update = next(c for c in calls if c[:2] == ['localizations', 'update'])
        self.assertIn('A useful update.', update)
        self.assertIn(['validate', '--app', 'fictional', '--version-id', 'version-id', '--output', 'table'], calls)
        self.assertFalse(any(c[0] == 'review' for c in calls))

    def test_preserves_existing_manual_release_setting(self):
        calls = self.run_prepare('PREPARE_FOR_SUBMISSION')
        self.assertFalse(any('--release-type' in c for c in calls))

    def test_versions_in_review_are_left_alone(self):
        calls = self.run_prepare('WAITING_FOR_REVIEW')
        self.assertEqual(len(calls), 1)

    def test_released_versions_are_left_alone(self):
        calls = self.run_prepare('READY_FOR_DISTRIBUTION')
        self.assertEqual(len(calls), 1)
