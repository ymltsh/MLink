import contextlib
import base64
import hashlib
import io
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import release


class ReleaseChecksTests(unittest.TestCase):
    def test_remote_build_floor_includes_beta_and_is_independent_of_machine(self):
        sources = ['version: 1.0.0+2\n', 'version: 1.1.0+20\n']
        contents = [json.dumps({'encoding': 'base64', 'content': base64.b64encode(text.encode()).decode()}) for text in sources]
        with patch.object(release, 'run', side_effect=['v1.0.0\nv1.1.0-beta', *contents]) as command:
            self.assertEqual(release.remote_build_floor('gh', 'example/project'), 20)
            self.assertIn('v1.1.0-beta', command.call_args.args[-1])

    def test_remote_missing_source_fails_instead_of_assuming_zero_build(self):
        with patch.object(release, 'run', side_effect=['legacy-tag', '{"encoding":"none"}']):
            with self.assertRaises(ValueError):
                release.remote_build_floor('gh', 'example/project')

    def test_build_must_increase_independently_of_version_and_all_history(self):
        manifest = {'latest': {'version': '1.0.0', 'build': 5},
                    'history': [{'version': '0.9.0', 'build': 7}]}
        for version, build in [('2.0.0', 1), ('2.0.0', 5), ('2.0.0', 7), ('0.9.0', 8)]:
            with self.assertRaises(ValueError):
                release.validate_release_target(version, build, '1.0.0', 6, manifest, True)
        release.validate_release_target('2.0.0', 8, '1.0.0', 6, manifest, True)

    def test_same_build_is_only_for_explicit_same_prepared_version_retry(self):
        manifest = {'latest': {'version': '1.0.0', 'build': 1}}
        release.validate_release_target('1.0.1', 2, '1.0.1', 2, manifest, True)
        for version, explicit in [('1.0.2', True), ('1.0.1', False)]:
            with self.assertRaises(ValueError):
                release.validate_release_target(version, 2, '1.0.1', 2, manifest, explicit)

    def fixture(self, directory):
        root = Path(directory)
        (root / 'lib/core/config').mkdir(parents=True)
        (root / 'pubspec.yaml').write_text('version: 1.0.1+2\n', encoding='utf-8')
        (root / 'lib/core/config/app_config.dart').write_text(
            "static const appVersion = '1.0.1';\nstatic const appBuild = 2;\n", encoding='utf-8')
        release.write_json(root / 'version.json', {'latest': {'version': '1.0.0', 'build': 1}})
        release.write_json(root / 'release_config.json', {'repo': 'example/project', 'branch': 'main',
                                                        'name': 'Test', 'asset_prefix': 'mlink'})
        out = root / 'build/releases/1.0.1+2'
        out.mkdir(parents=True)
        files = [out / 'mlink-setup-1.0.1.exe', out / 'mlink-windows-1.0.1.zip']
        for file in files:
            file.write_bytes(b'artifact')
        metadata = dict(schema=2, version='1.0.1', build=2, tag='v1.0.1', source_sha256='source',
                        checks={'status': 'skipped_explicitly'}, build_toolchain={'flutter': 'test'},
                        sha256={file.name: hashlib.sha256(file.read_bytes()).hexdigest() for file in files})
        release.write_json(out / 'artifacts.json', metadata)
        return root, out, files

    def invoke_reuse(self, root, *, skip=False, failing=False, publish=False):
        calls = []

        def command(*args, **kwargs):
            calls.append(args)
            if args[:3] == ('flutter', '--version', '--machine'):
                return json.dumps({'frameworkVersion': '3.32.8', 'flutterRoot': 'private-path'})
            if args[:2] == ('flutter', 'analyze') and failing:
                raise subprocess.CalledProcessError(1, args)
            if args[:3] == ('git', 'branch', '--show-current'):
                return 'main'
            if args[:3] == ('git', 'status', '--porcelain'):
                return ''
            if args[:2] == ('git', 'ls-remote'):
                return 'abc refs/heads/main'
            if args[:3] == ('git', 'rev-parse', 'HEAD'):
                return 'abc'
            if args[:3] == ('git', 'remote', 'get-url'):
                return 'https://github.com/example/project.git'
            return '' if kwargs.get('capture') else None

        args = ['--version', '1.0.1', '--build', '2', '--skip-build', '--notes', 'test']
        if not publish:
            args.append('--local-only')
        if skip:
            args.append('--skip-checks')
        with patch.object(release, 'ROOT', root), \
             patch.object(release, 'source_fingerprint', return_value='source'), \
             patch.object(release, 'flutter_executable', return_value='flutter'), \
             patch.object(release.shutil, 'which', return_value='gh'), \
             patch.object(release, 'run', side_effect=command), \
             patch.object(release.subprocess, 'run') as probe, \
             contextlib.redirect_stdout(io.StringIO()):
            probe.return_value.returncode = 1
            if failing:
                with self.assertRaises(subprocess.CalledProcessError):
                    release.main(args)
            else:
                release.main(args)
        return calls

    def test_reuse_of_unchecked_build_runs_all_checks_and_records_provenance(self):
        with tempfile.TemporaryDirectory() as directory:
            root, out, _ = self.fixture(directory)
            calls = self.invoke_reuse(root)
            self.assertIn(('flutter', 'analyze'), calls)
            self.assertIn(('flutter', 'test'), calls)
            self.assertTrue(any(call[1:] == ('-m', 'unittest', 'discover', '-s', 'tests') for call in calls))
            metadata = release.read_json(out / 'artifacts.json')
            self.assertEqual(metadata['checks']['status'], 'passed')
            self.assertEqual(metadata['checks']['source_sha256'], 'source')
            self.assertNotIn('private-path', json.dumps(metadata))

    def test_reuse_check_failure_cannot_create_release_or_mark_checks_passed(self):
        with tempfile.TemporaryDirectory() as directory:
            root, out, _ = self.fixture(directory)
            before = (out / 'artifacts.json').read_bytes()
            calls = self.invoke_reuse(root, failing=True, publish=True)
            self.assertFalse(any(call[:3] == ('gh', 'release', 'create') for call in calls))
            self.assertEqual((out / 'artifacts.json').read_bytes(), before)

    def test_reuse_only_skips_checks_when_explicitly_requested(self):
        with tempfile.TemporaryDirectory() as directory:
            root, out, _ = self.fixture(directory)
            calls = self.invoke_reuse(root, skip=True)
            self.assertFalse(any(call[0] == 'flutter' for call in calls))
            self.assertEqual(release.read_json(out / 'artifacts.json')['checks']['status'], 'skipped_explicitly')

    def test_reuse_rejects_legacy_metadata_changed_source_and_tampered_binary(self):
        with tempfile.TemporaryDirectory() as directory:
            _, out, files = self.fixture(directory)
            metadata = release.read_json(out / 'artifacts.json')
            with patch.object(release, 'source_fingerprint', return_value='source'):
                with self.assertRaises(ValueError):
                    release.verify_artifacts({**metadata, 'schema': 1}, {'windows': files[0]}, '1.0.1', 2, 'v1.0.1')
                with self.assertRaises(ValueError):
                    release.verify_artifacts({**metadata, 'source_sha256': 'changed'}, {'windows': files[0]}, '1.0.1', 2, 'v1.0.1')
                files[0].write_bytes(b'tampered')
                with self.assertRaises(ValueError):
                    release.verify_artifacts(metadata, {'windows': files[0]}, '1.0.1', 2, 'v1.0.1')

    def test_source_changes_during_checks_fail(self):
        with patch.object(release, 'source_fingerprint', side_effect=['before', 'after']), \
             patch.object(release, 'toolchain', return_value={}), patch.object(release, 'run'):
            with self.assertRaises(ValueError):
                release.run_checks('flutter')

    def test_dry_run_rejects_higher_version_with_same_build_without_commands(self):
        with patch.object(release, 'run', side_effect=AssertionError('unexpected command')):
            with self.assertRaises(ValueError):
                release.main(['--version', '99.0.0', '--build', '1', '--dry-run'])


if __name__ == '__main__':
    unittest.main()
