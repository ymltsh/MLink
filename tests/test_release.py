import contextlib
import io
import json
from pathlib import Path
import re
import unittest
from unittest.mock import patch
import release

class ReleaseTests(unittest.TestCase):
    def test_numeric_order_and_invalid_version(self):
        self.assertGreater(release.version_key('1.10.0', 1), release.version_key('1.9.9', 99))
        for version, build in [('1.0', 1), ('1.0.0-beta', 1), ('1.0.0', 0)]:
            with self.assertRaises(ValueError):
                release.version_key(version, build)

    def test_history_and_exact_asset_urls(self):
        old = {'latest': {'version': '1.0.0', 'build': 1}, 'history': []}
        result = release.manifest_for(old, '1.0.1', 2, '妙联', 'notes', 'ymltsh/MLink',
                                      'v1.0.1', {'windows': Path('mlink-setup-1.0.1.exe')})
        self.assertEqual(result['history'], [old['latest']])
        self.assertEqual(result['latest']['urls']['windows'],
                         'https://github.com/ymltsh/MLink/releases/download/v1.0.1/mlink-setup-1.0.1.exe')
        repeated = release.manifest_for(result, '1.0.1', 2, '妙联', 'notes', 'ymltsh/MLink', 'v1.0.1', {})
        self.assertEqual(len(repeated['history']), 1)

    def test_dry_run_has_no_mutations_or_commands(self):
        paths = [release.ROOT / 'pubspec.yaml', release.ROOT / 'version.json',
                 release.ROOT / 'lib/core/config/app_config.dart']
        before = [path.read_bytes() for path in paths]
        with patch.object(release, 'run', side_effect=AssertionError('dry-run invoked command')):
            with contextlib.redirect_stdout(io.StringIO()) as output:
                release.main(['--version', '99.0.0', '--build', '999', '--beta2', '--android', '--dry-run'])
        plan = json.loads(output.getvalue())
        self.assertEqual(plan['tag'], 'v99.0.0-beta2')
        self.assertEqual(len(plan['files']), 3)
        self.assertEqual(before, [path.read_bytes() for path in paths])

    def test_versions_are_synchronized(self):
        match = release.VERSION_RE.search((release.ROOT / 'pubspec.yaml').read_text(encoding='utf-8'))
        source = (release.ROOT / 'lib/core/config/app_config.dart').read_text(encoding='utf-8')
        self.assertEqual(re.search(r"appVersion = '([^']+)'", source)[1], match[1])
        self.assertEqual(re.search(r'appBuild = (\d+)', source)[1], match[2])

if __name__ == '__main__':
    unittest.main()
