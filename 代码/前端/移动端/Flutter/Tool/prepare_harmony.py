"""Build the shared client and bind the Harmony host to one HTTPS origin."""
from pathlib import Path
import argparse
import json
import shutil
import subprocess
import sys
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[1]


# JOBS_INPUT_CHOICE_STYLE_BEGIN
# 只格式化已展开的提示，答案、默认值和 EOF 仍由原 input 处理。
def jobs_prompt_render(message):
    import os
    import re
    import sys
    plain = re.sub(r"\x1b\[[0-9;]*m", "", str(message))
    if ("NO_COLOR" in os.environ or os.environ.get("TERM", "") in ("", "dumb")
            or os.environ.get("PLAIN_OUTPUT") == "1"
            or os.environ.get("IS_SOURCETREE_RUNTIME") == "1"
            or not sys.stdin.isatty() or not sys.stdout.isatty()):
        return plain
    red = re.compile(r"(?:输入)?(?:任意|任何)(?:非空)?(?:字符|内容|输入|键)|非空(?:字符|内容|输入)?|其它输入|其他输入|type (?:anything|any[^ ]*)|press any key", re.I)
    green = re.compile(r"(?:直接|仅|只需|只|按下|按)?\s*(?:回车|回車)|\b(?:enter|return)\b", re.I)
    def green_position(value):
        match = green.search(value)
        if match is None:
            return None
        prefix = re.sub(r"[“”‘’「」『』\"']", "", value[:match.start()])
        typed = re.search(r"(?:输入|键入|填写|type)[^；;|]*[\w+-]+\s*(?:后|再|并)?\s*$", prefix, re.I)
        return None if typed else match
    def segment(value, inherited):
        red_match = red.search(value)
        green_match = green_position(value)
        if inherited:
            return f"\x1b[1;{inherited}m{value}\x1b[0m" if value else value
        if red_match and green_match and green_match.start() < red_match.start():
            return segment(value[:red_match.start()], 0) + segment(value[red_match.start():], 31)
        match, color = (red_match, 31) if red_match else (green_match, 32)
        if match is None:
            return value
        return value[:match.start()] + f"\x1b[1;{color}m" + value[match.start():] + "\x1b[0m"
    output = []
    inherited = 0
    depth = 0
    for index, part in enumerate(re.split(r"([；;/|，,、？?：:=＝（）()\[\]【】])", plain)):
        if not index % 2:
            output.append(segment(part, inherited))
            previous = part
            continue
        output.append(part)
        if part in "（([【":
            depth += 1
            if red.search(previous):
                inherited = 31
            elif green_position(previous):
                inherited = 32
        elif part in "）)]】":
            depth = max(0, depth - 1)
        elif part in "：:=＝":
            if not inherited:
                inherited = 31 if red.search(previous) else 32 if green.search(previous) else 0
        elif not depth:
            inherited = 0
    return "".join(output)
# JOBS_INPUT_CHOICE_STYLE_END

def endpoint_config(value: str) -> tuple[str, str]:
    """Derive a same-origin hosted page; never use a file-origin production page."""
    api = urlparse(value)
    if (api.scheme != 'https' or not api.hostname or api.username or api.password
            or api.query or api.fragment or api.path.rstrip('/') != '/api/v1'):
        raise ValueError('--api requires https://domain/api/v1 without credentials/query/fragment')
    try:
        port = api.port
    except ValueError as error:
        raise ValueError('Invalid HTTPS port') from error
    hostname = api.hostname.encode('idna').decode('ascii').lower()
    if any(c.isspace() for c in hostname) or any(c in hostname for c in '\\/@?#'):
        raise ValueError('Invalid HTTPS hostname')
    if ':' in hostname:
        hostname = f'[{hostname}]'
    origin = f'https://{hostname}'
    if port is not None and port != 443:
        if port == 0:
            raise ValueError('Invalid HTTPS port')
        origin += f':{port}'
    return origin, f'{origin}/client/?host=harmony'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--api', required=True, help='HTTPS API address ending in /api/v1')
    parser.add_argument('--check', action='store_true', help='Check paths and tools without building or writing')
    args = parser.parse_args()
    try:
        origin, page = endpoint_config(args.api)
    except ValueError as error:
        parser.error(str(error))
    flutter = shutil.which('flutter')
    if not flutter:
        parser.error('Flutter is missing; install the current stable SDK first')
    destination = ROOT.parent / '鸿蒙/entry/src/main/ets/Config/Endpoint.ets'
    print(f'Flutter: {flutter}\nAPI origin: {origin}\nHosted page: {page}\nConfig: {destination}')
    if args.check:
        return
    print('知序鸿蒙准备：构建并更新当前工程 Dist/Client 与 HTTPS 宿主配置。\n'
          '不会安装 SDK、改变系统代理、签名或发布；Ctrl+C 取消。')
    if not sys.stdin.isatty():
        parser.error('No interactive input; run --check for a read-only check, or use a terminal to build')
    try:
        if input(jobs_prompt_render('按回车开始；输入任意字符取消：')):
            raise SystemExit('已取消，未构建或写入配置。')
    except EOFError:
        raise SystemExit('输入结束，未构建或写入配置。')
    subprocess.run([flutter, 'build', 'web', '--release', '--no-web-resources-cdn',
                    '--base-href', '/client/', '--output', 'Dist/Client'], cwd=ROOT, check=True)
    if not (ROOT / 'Dist/Client/index.html').is_file():
        raise SystemExit('Build did not produce index.html')
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.is_symlink():
        raise SystemExit('Refusing a symlink destination')
    destination.write_text('// Generated by Tool/prepare_harmony.py.\n'
                           f'export const CLIENT_ORIGIN: string = {json.dumps(origin)};\n'
                           f'export const CLIENT_URL: string = {json.dumps(page)};\n')
    print('Copy Dist/Client to ../../../后端/后端代码/client-web on the configured HTTPS server.\n'
          'Open ../鸿蒙/ in DevEco Studio, configure signing, then build HAP and APP.\n'
          'The ArkWeb host keeps the configured origin inside the app. User-triggered HTTP(S) links open with the system browser handler.\n'
          'Index.ets is the single maintained host source; this tool generates Endpoint.ets only.\n'
          'The production host loads HTTPS, so first launch requires a working network; invalid TLS is rejected.')


if __name__ == '__main__':
    main()
