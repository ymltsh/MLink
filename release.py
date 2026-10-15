#!/usr/bin/env python3
"""MLink 发布工具。仅依赖 Python 标准库，上传使用 GitHub CLI。"""
import argparse
import base64
from datetime import datetime, timedelta, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
from urllib.parse import quote
import zipfile

ROOT = Path(__file__).resolve().parent
VERSION_RE = re.compile(r'^version:\s*(\d+\.\d+\.\d+)(?:\+(\d+))?\s*$', re.M)


def run(*args, capture=False):
    result = subprocess.run(list(map(str, args)), cwd=ROOT, check=True,
                            text=True, encoding='utf-8', capture_output=capture)
    return result.stdout.strip() if capture else None


def read_json(path):
    return json.loads(path.read_text(encoding='utf-8'))


def write_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def version_key(version, build):
    if not re.fullmatch(r'\d+\.\d+\.\d+', version) or build < 1:
        raise ValueError('版本号须为 x.y.z，构建号须为正整数')
    return (*map(int, version.split('.')), build)


def source_fingerprint():
    paths = run('git', 'ls-files', '--cached', '--others', '--exclude-standard', '-z', capture=True)
    digest = hashlib.sha256()
    for name in sorted(set(paths.split('\0')) - {'', 'version.json'}):
        path = ROOT / name
        if path.is_file():
            digest.update(name.encode('utf-8'))
            digest.update(b'\0')
            digest.update(path.read_bytes())
    return digest.hexdigest()


def validate_release_target(version, build, current, current_build, manifest, explicit_build):
    target = version_key(version, build)
    baseline = version_key(current, current_build)
    published = [manifest['latest'], *manifest.get('history', [])]
    published_build = max(int(item['build']) for item in published)
    if target[:3] < baseline[:3] or build < current_build:
        raise ValueError('不能回退版本或构建号')
    if build <= published_build:
        raise ValueError('新发布构建号必须高于所有已发布构建号')
    if build == current_build and (version != current or not explicit_build):
        raise ValueError('新版本必须递增构建号；同次重试须显式复用相同版本和 --build')


def flutter_executable():
    flutter = os.getenv('FLUTTER_BIN') or shutil.which('flutter')
    if not flutter:
        raise ValueError('请配置 FLUTTER_BIN 或将 Flutter 加入 PATH')
    return flutter


def remote_build_floor(gh, repo):
    """包括 Beta；根据每个已公开 Release 的标签源码核对构建号。"""
    tags = run(gh, 'api', '--paginate', f'repos/{repo}/releases',
               '--jq', '.[] | select(.draft == false) | .tag_name', capture=True)
    highest = 0
    for tag in tags.splitlines():
        content = json.loads(run(gh, 'api',
                                 f'repos/{repo}/contents/pubspec.yaml?ref={quote(tag, safe="")}',
                                 capture=True))
        if content.get('encoding') != 'base64':
            raise ValueError(f'无法确认已发布版本 {tag} 的构建号')
        source = base64.b64decode(''.join(content['content'].split()), validate=True).decode('utf-8')
        match = VERSION_RE.search(source)
        if not match:
            raise ValueError(f'已发布版本 {tag} 缺少源码版本记录')
        highest = max(highest, int(match[2] or 1))
    return highest


def toolchain(flutter, iscc=None):
    info = json.loads(run(flutter, '--version', '--machine', capture=True))
    result = {'flutter': {key: info.get(key) for key in
                          ('frameworkVersion', 'frameworkRevision', 'engineRevision', 'dartSdkVersion')},
              'python': '.'.join(map(str, sys.version_info[:3])), 'platform': sys.platform}
    if iscc:
        result['inno_sha256'] = hashlib.sha256(Path(iscc).read_bytes()).hexdigest()
    return result


def run_checks(flutter, skip=False):
    fingerprint = source_fingerprint()
    if skip:
        return {'status': 'skipped_explicitly', 'source_sha256': fingerprint}
    versions = toolchain(flutter)
    run(flutter, 'analyze')
    run(flutter, 'test')
    run(sys.executable, '-m', 'unittest', 'discover', '-s', 'tests')
    if source_fingerprint() != fingerprint:
        raise ValueError('检查期间源码或配置发生变化，请重试')
    return {'status': 'passed', 'source_sha256': fingerprint, 'toolchain': versions}


def verify_artifacts(metadata, files, version, build, tag):
    if metadata.get('schema') != 2:
        raise ValueError('产物记录缺少检查与工具链信息，请重新构建')
    if any(metadata.get(k) != v for k, v in dict(version=version, build=build, tag=tag).items()):
        raise ValueError('复用产物版本不匹配')
    if metadata.get('source_sha256') != source_fingerprint():
        raise ValueError('源码或项目配置已变化，请重新 --local-only 构建')
    if not metadata.get('build_toolchain'):
        raise ValueError('缺少构建工具链记录，请重新构建')
    for path in files.values():
        if not path.is_file() or metadata.get('sha256', {}).get(path.name) != hashlib.sha256(path.read_bytes()).hexdigest():
            raise ValueError(f'产物缺失或校验失败：{path.name}')


def manifest_for(old, version, build, name, notes, repo, tag, files):
    latest = dict(version=version, build=build, name=name,
                  date=datetime.now(timezone(timedelta(hours=8))).strftime('%Y-%m-%d'),
                  notes=notes, urls={key: f'https://github.com/{repo}/releases/download/{tag}/{path.name}'
                                    for key, path in files.items()},
                  page=f'https://github.com/{repo}/releases/tag/{tag}')
    history = list(old.get('history', []))
    previous = old.get('latest')
    if previous and (previous['version'], previous['build']) != (version, build):
        history.insert(0, previous)
    return dict(latest=latest, history=history)


def compiler():
    candidates = [os.getenv('INNO_SETUP_COMPILER'), shutil.which('ISCC.exe')]
    for env in ('LOCALAPPDATA', 'ProgramFiles(x86)', 'ProgramFiles'):
        base = Path(os.getenv(env, 'C:/'))
        candidates.extend([base / 'Inno Setup 6/ISCC.exe', base / 'Programs/Inno Setup 6/ISCC.exe'])
    for path in candidates:
        if path and Path(path).is_file():
            return str(path)
    raise ValueError('请安装 Inno Setup 6，或设置 INNO_SETUP_COMPILER')


def main(argv=None):
    config = read_json(ROOT / 'release_config.json')
    pubspec = ROOT / 'pubspec.yaml'
    app_config = ROOT / 'lib/core/config/app_config.dart'
    match = VERSION_RE.search(pubspec.read_text(encoding='utf-8'))
    if not match:
        raise ValueError('pubspec.yaml 缺少版本号')
    current, current_build = match[1], int(match[2] or 1)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--version')
    parser.add_argument('--build', type=int)
    parser.add_argument('--name')
    parser.add_argument('--notes')
    parser.add_argument('--notes-file', type=Path)
    channel = parser.add_mutually_exclusive_group()
    channel.add_argument('--beta', action='store_true')
    channel.add_argument('--beta2', action='store_true')
    parser.add_argument('--android', action='store_true', help='同时构建 APK（当前使用调试签名）')
    parser.add_argument('--dry-run', action='store_true')
    parser.add_argument('--skip-build', action='store_true')
    parser.add_argument('--skip-checks', action='store_true')
    parser.add_argument('--no-push', action='store_true', help='发布 Release，但不提交/推送清单')
    parser.add_argument('--local-only', action='store_true', help='只构建本地产物，不创建 Release')
    args = parser.parse_args(argv)
    if argv is None and len(sys.argv) == 1:
        args.version = input(f'版本号（当前 {current}）：').strip()
        args.build = int(input(f'构建号 [{current_build + 1}]：') or current_build + 1)
        choice = input('发布类型 [stable/beta/beta2]：').strip() or 'stable'
        if choice not in ('stable', 'beta', 'beta2'):
            raise ValueError('发布类型无效')
        args.beta, args.beta2 = choice == 'beta', choice == 'beta2'
        print('输入发布说明，以空行结束：')
        lines = []
        while True:
            line = input()
            if not line:
                break
            lines.append(line)
        args.notes = '\n'.join(lines)
    if not args.version and args.dry_run:
        major, minor, patch = map(int, current.split('.'))
        args.version = f'{major}.{minor}.{patch + 1}'
    if not args.version:
        parser.error('请提供 --version')
    build = args.build or current_build + 1
    if args.build is not None and args.build < 1:
        parser.error('--build 必须为正整数')
    old = read_json(ROOT / 'version.json')
    key = version_key(args.version, build)
    validate_release_target(args.version, build, current, current_build, old, args.build is not None)
    suffix = '-beta2' if args.beta2 else '-beta' if args.beta else ''
    # 预发布不替换稳定更新入口。
    if not suffix and key < version_key(old['latest']['version'], old['latest']['build']):
        raise ValueError('稳定更新清单不能回退')
    asset = args.version + suffix
    tag = 'v' + asset
    name = args.name or f"{config['name']} {tag}"
    notes = args.notes_file.read_text(encoding='utf-8') if args.notes_file else (args.notes or '')
    if not args.dry_run and not notes.strip():
        raise ValueError('请提供发布说明 --notes 或 --notes-file')
    out = ROOT / 'build/releases' / f'{asset}+{build}'
    prefix = config['asset_prefix']
    files = {'windows': out / f'{prefix}-setup-{asset}.exe',
             'windows_portable': out / f'{prefix}-windows-{asset}.zip'}
    if args.android:
        files['android'] = out / f'{prefix}-{asset}.apk'
    print(json.dumps(dict(repo=config['repo'], tag=tag, version=args.version, build=build,
                         prerelease=bool(suffix), files={k: str(v) for k, v in files.items()},
                         local_only=args.local_only, push=not args.no_push and not args.local_only),
                     ensure_ascii=False, indent=2))
    if args.dry_run:
        return
    gh = shutil.which('gh')
    if not args.local_only:
        if not gh:
            raise ValueError('请安装 GitHub CLI 并执行 gh auth login，或使用 --local-only')
        run(gh, 'auth', 'status')
        if run('git', 'branch', '--show-current', capture=True) != config['branch']:
            raise ValueError(f"发布需在 {config['branch']} 分支执行")
        if run('git', 'status', '--porcelain', capture=True):
            raise ValueError('请先提交源码和配置，再发布；发布工具不会提交业务改动')
        # 确保 Release 标签指向当前构建源码，而不是远端默认分支的旧提交。
        remote_sha = run('git', 'ls-remote', 'origin', f"refs/heads/{config['branch']}", capture=True).split()
        head = run('git', 'rev-parse', 'HEAD', capture=True)
        if not remote_sha or remote_sha[0] != head:
            raise ValueError('请先推送当前源码；远端分支必须与本地 HEAD 一致')
        if run('git', 'remote', 'get-url', 'origin', capture=True).removesuffix('.git').split('github.com')[-1].lstrip('/:') != config['repo']:
            raise ValueError('origin 与 release_config.json 的 repo 不一致')
        if f"{current}+{current_build}" != f"{args.version}+{build}":
            raise ValueError('正式上传前请先使用 --local-only 同步版本，再提交并推送源码')
        if build <= remote_build_floor(gh, config['repo']):
            raise ValueError('构建号必须高于远端所有已公开 Release（包括 Beta）的构建号')
        probe = subprocess.run([gh, 'release', 'view', tag, '--repo', config['repo']],
                               cwd=ROOT, capture_output=True)
        if probe.returncode == 0:
            raise ValueError('Release 已存在；为避免覆盖，请使用新版本或在 GitHub 手动恢复草稿')
    source = app_config.read_text(encoding='utf-8')
    if args.skip_build:
        metadata = read_json(out / 'artifacts.json')
        verify_artifacts(metadata, files, args.version, build, tag)
        # 复用二进制不代表跳过检查；默认对同一源码重新执行严格检查。
        checks = run_checks(None if args.skip_checks else flutter_executable(), args.skip_checks)
        metadata['checks'] = checks
        write_json(out / 'artifacts.json', metadata)
        if (current, current_build) != (args.version, build):
            raise ValueError('复用产物前需同步源码版本')
    else:
        if sys.platform != 'win32':
            raise ValueError('Windows 发布需在 Windows 主机执行')
        flutter = flutter_executable()
        iscc = compiler()
        pubspec.write_text(VERSION_RE.sub(f'version: {args.version}+{build}', pubspec.read_text(encoding='utf-8'), count=1), encoding='utf-8')
        source, count1 = re.subn(r"static const appVersion = '[\d.]+';", f"static const appVersion = '{args.version}';", source)
        source, count2 = re.subn(r'static const appBuild = \d+;', f'static const appBuild = {build};', source)
        if (count1, count2) != (1, 1):
            raise ValueError('AppConfig 版本字段无效')
        app_config.write_text(source, encoding='utf-8')
        run(flutter, 'pub', 'get')
        checks = run_checks(flutter, args.skip_checks)
        build_toolchain = toolchain(flutter, iscc)
        # 不终止任何进程，尤其当前二进制名 code.exe 可能与其他程序重名。
        run(flutter, 'build', 'windows', '--release')
        bundle = ROOT / 'build/windows/x64/runner/Release'
        if not (bundle / config['windows_exe']).is_file():
            raise ValueError('Windows 可执行文件缺失')
        out.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / 'LICENSE', bundle / 'LICENSE')
        with zipfile.ZipFile(files['windows_portable'], 'w', zipfile.ZIP_DEFLATED) as archive:
            for path in sorted(bundle.rglob('*')):
                if path.is_file() and path.suffix.lower() not in ('.zip', '.pdb'):
                    archive.write(path, path.relative_to(bundle))
        run(iscc, f'/DAppVersion={args.version}', f'/DAssetSuffix={asset}',
            f'/DReleaseDir={bundle}', f'/O{out}', ROOT / config['installer'])
        if args.android:
            run(flutter, 'build', 'apk', '--release')
            shutil.copy2(ROOT / 'build/app/outputs/flutter-apk/app-release.apk', files['android'])
        fingerprint = source_fingerprint()
        if fingerprint != checks['source_sha256']:
            raise ValueError('构建期间源码或配置已变化，请重新构建')
        write_json(out / 'artifacts.json', dict(schema=2, version=args.version, build=build, tag=tag,
                   checks=checks, build_toolchain=build_toolchain, source_sha256=fingerprint,
                   sha256={p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in files.values()}))
    verify_artifacts(read_json(out / 'artifacts.json'), files, args.version, build, tag)
    if args.local_only:
        print('本地产物已生成；提交并推送源码后，用相同版本/构建号和 --skip-build 发布。')
        return
    checksum = out / 'SHA256SUMS.txt'
    checksum.write_text(''.join(f'{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.name}\n' for p in files.values()), encoding='utf-8')
    notes_path = out / 'release-notes.md'
    notes_path.write_text(notes, encoding='utf-8')
    cmd = [gh, 'release', 'create', tag, '--repo', config['repo'], '--target', head,
           '--title', name, '--notes-file', notes_path, '--draft']
    if suffix:
        cmd.append('--prerelease')
    run(*cmd)
    # 上传失败保留草稿，清单不会引用缺失的资产。
    run(gh, 'release', 'upload', tag, *files.values(), checksum, '--repo', config['repo'])
    run(gh, 'release', 'edit', tag, '--draft=false', '--repo', config['repo'])
    if suffix:
        print('预发布已完成，稳定 version.json 保持不变。')
        return
    write_json(ROOT / 'version.json', manifest_for(old, args.version, build, name, notes, config['repo'], tag, files))
    if not args.no_push:
        # 防止发布期间出现新的暂存改动；只提交清单。
        if run('git', 'diff', '--cached', '--name-only', capture=True):
            raise ValueError('暂存区有其他改动，请手动提交 version.json')
        run('git', 'add', '--', 'version.json')
        run('git', 'commit', '-m', f'chore: update manifest to {tag}', '--', 'version.json')
        run('git', 'push', 'origin', config['branch'])


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f'发布失败：{error}', file=sys.stderr)
        sys.exit(1)
