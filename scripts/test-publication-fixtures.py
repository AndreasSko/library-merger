#!/usr/bin/env python3
"""Offline publication fixture contracts; no catalog, web, or simulator needed."""
import importlib.util
import json
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
FIXTURES = ROOT / 'LibraryMergerTests/Fixtures'
spec = importlib.util.spec_from_file_location('validator', ROOT / 'scripts/validate-playlist-fixtures.py')
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)


def snapshot(name):
    value = validator.inspect_archive(FIXTURES / (name + '.jwlibrary'))
    if value['errors']:
        raise AssertionError(value['errors'])
    return value


def item(value):
    return value['playlists'][0]['items'][0]


class PublicationFixtureTests(unittest.TestCase):
    def test_real_identity_and_duration_are_retained_offline(self):
        contract = json.loads((FIXTURES / 'publication-source.json').read_text())
        self.assertEqual(contract['naturalKey'], 'pub-jwb-142_E_1_VIDEO')
        self.assertEqual(contract['sourceURL'], 'https://www.jw.org/finder?wtlocale=E&lank=pub-jwb-142_1_VIDEO')
        for name in contract['fixtures']:
            value = snapshot(name)
            self.assertEqual(len(value['playlists']), 1)
            occurrence = item(value)
            self.assertEqual(len(occurrence['locations']), 1)
            self.assertEqual(occurrence['independentMedia'], [])
            location = occurrence['locations'][0]
            self.assertEqual(location['KeySymbol'], 'jwb-142')
            self.assertEqual(location['Track'], 1)
            self.assertEqual(location['Type'], 3)
            self.assertEqual(location['MajorMultimediaType'], 2)
            self.assertEqual(location['BaseDurationTicks'], 34346400000)
            self.assertIsNotNone(occurrence['item']['thumbnailSha256'])

    def test_action_is_the_only_semantic_setting_difference(self):
        base, changed = snapshot('publication-base'), snapshot('publication-action')
        self.assertEqual(item(base)['item']['EndAction'], 0)
        self.assertEqual(item(changed)['item']['EndAction'], 3)
        item(changed)['item']['EndAction'] = 0
        self.assertEqual(validator.semantic(base), validator.semantic(changed))
        self.assertEqual(item(base)['item']['StartTrimOffsetTicks'], 25000000)

    def test_thumbnail_is_the_only_cosmetic_difference(self):
        base, changed = snapshot('publication-base'), snapshot('publication-thumbnail-new')
        self.assertNotEqual(item(base)['item']['thumbnailSha256'], item(changed)['item']['thumbnailSha256'])
        item(changed)['item']['thumbnailSha256'] = item(base)['item']['thumbnailSha256']
        self.assertEqual(base['playlists'], changed['playlists'])

    def test_absent_title_and_language_are_not_fabricated(self):
        base = item(snapshot('publication-base'))['locations'][0]
        self.assertEqual(base['Title'], 'JW Broadcasting—October 2026')
        self.assertEqual(base['MepsLanguage'], 0)
        missing = item(snapshot('publication-missing-title'))['locations'][0]
        unknown = item(snapshot('publication-unknown-language'))['locations'][0]
        self.assertIsNone(missing['Title'])
        self.assertIsNone(unknown['MepsLanguage'])
        missing['Title'] = base['Title']
        unknown['MepsLanguage'] = base['MepsLanguage']
        self.assertEqual(missing, base)
        self.assertEqual(unknown, base)


if __name__ == '__main__':
    unittest.main()
