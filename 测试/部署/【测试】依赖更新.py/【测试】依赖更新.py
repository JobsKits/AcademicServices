#!/usr/bin/env python3
"""官方元数据消费者、版本化缓存与取消隔离；仅临时项目和假下载。"""
from __future__ import annotations
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tarfile
import tempfile
import time
import unittest

ROOT = next(p for p in Path(__file__).resolve().parents if (p / '代码').is_dir() and (p / '部署').is_dir())
PLATFORMS = ('MacOS','Ubuntu','Debian','RockyLinux','AlibabaCloudLinux','Alpine','FreeBSD')

def entry(platform):
    name = '【MacOS】部署.command' if platform == 'MacOS' else '【FreeBSD】部署.sh' if platform == 'FreeBSD' else '【Linux】部署.sh'
    return ROOT / '部署' / platform / name / name

class DependencyUpdateTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='依赖更新 中文 空格 ')
        self.addCleanup(self.temp.cleanup)
        self.work = Path(self.temp.name).resolve()
        self.project = self.work / 'project'
        self.project.mkdir()
        (self.project / 'go.mod').write_text('module fixture.invalid/project\ngo 1.27.3\n')
        (self.project / '.runtime').mkdir()
        self.tools = self.work / 'fake'; self.tools.mkdir()
        self.log = self.work / 'run.log'; self.log.touch()
        self.cli = self.tool('resolver', '''import os,re,sys,time
args=sys.argv[1:]
with open(os.environ['ARGUMENT_LOG'],'a') as f:f.write(repr(args)+'\\n')
if '--compare' in args:
 def version(v):
  v=v.removeprefix('go').removeprefix('v')
  if not re.fullmatch(r'[0-9]+\\.[0-9]+(?:\\.[0-9]+)?',v):sys.exit(2)
  n=tuple(map(int,v.split('.')));return n+(0,)*(3-len(n))
 result=version(args[args.index('--compare')+1])>=version(args[args.index('--at-least')+1])
 print('1' if result else '0');sys.exit(0 if result else 1)
name=args[args.index('--tool')+1]
if name!='go' and '--minimum-go' in args:sys.exit(2)
scenario=os.environ.get('SCENARIO','')
if scenario=='retry':sys.exit(75)
if scenario=='invalid':sys.exit(2)
version={'go':'1.27.4','fzf':'0.75.0','cloudflared':'2026.11.0'}[name]
kind='unsupported' if scenario=='unsupported' else 'tar.gz'
print('\\t'.join([name,args[args.index('--os')+1],args[args.index('--arch')+1],version,'fixture.tar.gz',os.environ['ASSET_SHA'],'https://github.com/junegunn/fzf/releases/download/v0.75.0/fixture.tar.gz',kind]))
''')
        self.old = self.tool('fzf', self.fzf('0.74.5'))
        new = self.tool('fzf-new', self.fzf('0.75.0'))
        self.archive = self.work / 'fixture.tar.gz'
        with tarfile.open(self.archive,'w:gz') as tar: tar.add(new,arcname='fzf')
        self.env = {**os.environ,'HOME':str(self.work/'home'),'XDG_CACHE_HOME':str(self.work/'cache'),
                    'PATH':str(self.tools)+os.pathsep+os.environ['PATH'],'ARGUMENT_LOG':str(self.work/'arguments'),
                    'ASSET_SHA':hashlib.sha256(self.archive.read_bytes()).hexdigest(),'FZF_BIN':'','GO_BIN':'','CLOUDFLARED_BIN':'',
                    'FIXTURE_ARCHIVE':str(self.archive),'NO_COLOR':'1','TERM':'dumb'}
        self.base = f'''\nSERVER_ROOT={self.quote(self.project)}
LOG_FILE={self.quote(self.log)}
DEPLOY_ROOT={self.quote(ROOT/'部署')}
GO_ARCH=arm64
DEPENDENCY_RESOLVER={self.quote(self.cli)}
lc_context
mkdir -p "$LC_STATE"
dependency_cache_context
lc_cache_begin
mkdir -p "$DEPENDENCY_CACHE_ROOT/.runtime/test-run"
DEPENDENCY_RUN_DIR="$DEPENDENCY_CACHE_ROOT/.runtime/test-run"
ensure_transfer_tools() {{ :; }}
download_dependency() {{ cp "$FIXTURE_ARCHIVE" "$2"; }}
'''
    @staticmethod
    def quote(value): return "'"+str(value).replace("'","'\\''")+"'"
    @staticmethod
    def fzf(version):
        return "import sys\nif '--version' in sys.argv: print('"+version+" fixture')\nelif '--help' in sys.argv: print('--accept-nth --height')\n"
    def tool(self,name,body):
        p=self.tools/name;p.write_text('#!'+sys.executable+'\n'+body);p.chmod(0o755);return p
    def script(self,body,platform='MacOS'):
        p=self.work/(platform+'-fixture.sh')
        p.write_text(entry(platform).read_text().rsplit('main "$@"',1)[0]+self.base+body+'\n')
        return p
    def run_native(self,body,*,platform='MacOS',changes=None):
        shell='zsh' if platform=='MacOS' else 'sh' if platform in ('Alpine','FreeBSD') else 'bash'
        return subprocess.run([shell,str(self.script(body,platform))],cwd='/',env={**self.env,**(changes or {})},capture_output=True,text=True,timeout=15)
    def assert_ok(self,result): self.assertEqual(result.returncode,0,result.stdout+result.stderr)

    def test_01_all_native_metadata_flags_and_no_cloud_in_server(self):
        for platform in PLATFORMS:
            with self.subTest(platform=platform):
                previous=self.project;self.project=self.work/platform;self.project.mkdir();(self.project/'go.mod').write_text('module fixture\ngo 1.27.3\n')
                self.base=self.base.replace(str(previous),str(self.project))
                # 独立子进程复用同一空缓存，无真实下载；严格CLI拒绝非Go的minimum-go。
                result=self.run_native('resolve_latest_dependency go\nresolve_latest_dependency fzf\nresolve_latest_dependency cloudflared\nselect_archive() { :; }\nprepare_dependency_resolver() { :; }\nensure_latest_dependency() { printf "CHECK:%s:%s\\n" "$DEPLOY_MODE" "$1"; }\nDEPLOY_MODE=server\nprepare_latest_dependencies\nDEPLOY_MODE=local\nprepare_latest_dependencies',platform=platform)
                self.assert_ok(result)
                self.assertIn('CHECK:server:go',result.stdout);self.assertIn('CHECK:server:fzf',result.stdout);self.assertNotIn('CHECK:server:cloudflared',result.stdout)
                self.assertIn('CHECK:local:cloudflared',result.stdout)
        source=entry('MacOS').read_text()
        self.assertIn('if [ "$DEPLOY_MODE" = local ]; then ensure_latest_dependency cloudflared; fi',source)
        pwsh=shutil.which('pwsh')
        if pwsh:
            fixture=self.work/'metadata-contract.ps1'
            fixture.write_text(r"""
param($Source,$Root,$Deploy,$Resolver)
$ErrorActionPreference='Stop'
$tokens=$null;$errors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile($Source,[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors|Out-String)}
foreach($definition in $ast.FindAll({param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst]},$true)){. ([scriptblock]::Create($definition.Extent.Text))}
$ServerRoot=$Root;$DeployRoot=$Deploy;$DependencyResolver=$Resolver
function Get-ToolArchitecture { 'arm64' }
foreach($name in @('go','fzf','cloudflared')) { $record=Resolve-LatestDependency $name; if($record.tool -cne $name){throw 'wrong tool'} }
function Prepare-DependencyResolver { }
function Ensure-LatestDependency($Name) { Write-Host "CHECK:${DeployMode}:$Name"; return 'fixture' }
$DeployMode='server';Prepare-LatestDependencies
$DeployMode='local';Prepare-LatestDependencies
""")
            result=subprocess.run([pwsh,'-NoLogo','-NoProfile','-File',str(fixture),str(ROOT/'部署/Windows/【Windows】部署.ps1/【Windows】部署.ps1'),str(self.project),str(ROOT/'部署'),str(self.cli)],env=self.env,cwd='/',capture_output=True,text=True,timeout=20)
            self.assert_ok(result)
            self.assertIn('CHECK:server:go',result.stdout);self.assertIn('CHECK:server:fzf',result.stdout);self.assertNotIn('CHECK:server:cloudflared',result.stdout)
            self.assertIn('CHECK:local:cloudflared',result.stdout)

    def test_02_old_path_cannot_bypass_latest_and_owned_new_version_is_reversible(self):
        result=self.run_native('''ensure_latest_dependency fzf
printf '%s\\n' "$FZF_EXE"
[ "$FZF_EXE" != "'''+str(self.old)+'''" ]
"$FZF_EXE" --version
lc_cache_seal
PATH=/usr/bin:/bin:/usr/sbin:/sbin
lc_find_fzf
[ "$LC_FZF" = "$FZF_EXE" ]
lc_restore_cache
[ ! -d "$DEPENDENCY_CACHE_ROOT/.tools" ]''')
        self.assert_ok(result);self.assertIn('0.75.0',result.stdout)
        self.assertIn('0.74.5',self.old.read_text())

    def test_03_explicit_old_path_fails_without_install_or_overwrite(self):
        original=self.old.read_bytes()
        result=self.run_native('ensure_latest_dependency fzf\nprintf unexpected',changes={'FZF_BIN':str(self.old)})
        self.assertNotEqual(result.returncode,0);self.assertIn('显式',result.stdout);self.assertNotIn('unexpected',result.stdout)
        self.assertEqual(self.old.read_bytes(),original)

    def test_04_bad_digest_and_metadata_error_stop_without_old_version_fallback(self):
        for changes in ({'ASSET_SHA':'0'*64},{'SCENARIO':'invalid'}):
            with self.subTest(changes=changes):
                previous=self.project;self.project=self.work/('case-'+str(len(list(self.work.glob('case-*')))));self.project.mkdir();(self.project/'go.mod').write_text('module fixture\ngo 1.27.3\n')
                self.base=self.base.replace(str(previous),str(self.project))
                result=self.run_native('ensure_latest_dependency fzf\nprintf unexpected',changes=changes)
                self.assertNotEqual(result.returncode,0);self.assertNotIn('unexpected',result.stdout)
                self.assertNotIn('采用版本｜fzf 0.74.5',result.stdout)

    def test_05_unsupported_requires_new_enough_explicit_native_tool(self):
        self.old.write_text('#!'+sys.executable+'\n'+self.fzf('0.75.0'))
        result=self.run_native('ensure_latest_dependency fzf\nprintf unexpected',changes={'SCENARIO':'unsupported'})
        self.assertNotEqual(result.returncode,0);self.assertIn('没有',result.stdout)
        previous=self.project;self.project=self.work/'supported-explicit';self.project.mkdir();(self.project/'go.mod').write_text('module fixture\ngo 1.27.3\n');self.base=self.base.replace(str(previous),str(self.project))
        result=self.run_native('ensure_latest_dependency fzf',changes={'SCENARIO':'unsupported','FZF_BIN':str(self.tools/'fzf-new')})
        self.assert_ok(result)

    def test_06_existing_cache_and_later_modified_files_are_preserved(self):
        result=self.run_native('''mkdir -p "$DEPENDENCY_CACHE_ROOT/.tools/existing"
printf original > "$DEPENDENCY_CACHE_ROOT/.tools/existing/tool"
# 当前会话已开始，专门重新建立独立原点夹具。
rm -f "$LC_STATE/cache-origin/root" "$LC_STATE/cache-origin/before.tsv"
LC_CACHE_ACTIVE=0
lc_cache_begin
ensure_latest_dependency fzf
lc_cache_seal
lc_restore_cache
[ "$(cat "$DEPENDENCY_CACHE_ROOT/.tools/existing/tool")" = original ]''')
        self.assert_ok(result)
        # 恢复后的同一收据可重试；另用独立项目防止重写首个原点。
        self.project=self.work/'other-project';self.project.mkdir();(self.project/'go.mod').write_text('module fixture\ngo 1.27.3\n')
        self.base=self.base.replace(str(self.work/'project'),str(self.project))
        result=self.run_native('''ensure_latest_dependency fzf
lc_cache_seal
printf '\\nexternally changed\\n' >> "$FZF_EXE"
if lc_restore_cache; then exit 91; fi
[ -f "$FZF_EXE" ]''')
        self.assert_ok(result)

    def test_07_retry_wait_cancellation_reaps_child_and_does_not_continue(self):
        self.cancel_case('resolve_latest_dependency fzf',{'SCENARIO':'retry'})

    def test_08_download_cancellation_reaps_child_and_does_not_continue(self):
        # 覆盖真实原生传输函数，而非base中的假安装函数。
        original=entry('MacOS').read_text().split('download_dependency() {',1)[1].split('\n}',1)[0]
        self.cancel_case("download_dependency() {"+original+"\n}\ncurl() { exec /bin/sh -c 'echo $$ > \"$FIXTURE_CHILD\"; exec sleep 100'; }\ndownload_dependency https://go.dev/dl/fixture \"$DEPENDENCY_RUN_DIR/download\"",{})

    def test_09_real_report_helper_and_fake_sdk_preserve_source_locks(self):
        resolver=os.environ.get('DEPENDENCY_TEST_RESOLVER')
        if not resolver or not Path(resolver).is_file(): self.skipTest('设置DEPENDENCY_TEST_RESOLVER为本机标准库查询器可执行文件')
        sdk=self.tool('module-go', 'import json\nprint(json.dumps({"Path":"fixture.invalid/dependency","Version":"v1.0.0","Update":{"Version":"v1.1.0"}}))\n')
        before=(self.project/'go.mod').read_bytes()
        result=self.run_native('DEPENDENCY_RESOLVER="$REAL_REPORT_RESOLVER"\nGO_EXE="$FAKE_MODULE_GO"\ncheck_business_dependency_updates\nprintf CONTINUE',changes={'REAL_REPORT_RESOLVER':resolver,'FAKE_MODULE_GO':str(sdk)})
        self.assert_ok(result);self.assertIn('v1.1.0',result.stdout);self.assertIn('CONTINUE',result.stdout)
        self.assertNotIn('未完成',result.stdout);self.assertEqual((self.project/'go.mod').read_bytes(),before)

    def test_10_business_validation_failure_stops_but_query_failure_can_continue(self):
        for code,continues in [(2,False),(3,True),(130,False)]:
            previous=self.project;self.project=self.work/('report-'+str(code));self.project.mkdir();(self.project/'go.mod').write_text('module fixture\ngo 1.27.3\n');self.base=self.base.replace(str(previous),str(self.project))
            cli=self.tool('report-cli-'+str(code),'import sys\nsys.exit('+str(code)+')\n')
            result=self.run_native('DEPENDENCY_RESOLVER="'+str(cli)+'"\ncheck_business_dependency_updates\nprintf CONTINUE')
            self.assertEqual('CONTINUE' in result.stdout,continues,result.stdout+result.stderr)
            if code==130:self.assertEqual(result.returncode,130)

    def test_11_powershell_cache_origin_new_existing_and_modified(self):
        pwsh=shutil.which('pwsh')
        if not pwsh:self.skipTest('PowerShell未安装，不冒充Windows原生验收')
        fixture=self.work/'cache.ps1'
        fixture.write_text(r"""
param($Source,$Root,$UndoSource)
$ErrorActionPreference='Stop'
$tokens=$null;$errors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile($Source,[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors|Out-String)}
foreach($definition in $ast.FindAll({param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst]},$true)){. ([scriptblock]::Create($definition.Extent.Text))}
$ServerRoot=$Root;$script:DependencyCacheStarted=$false
Start-Origin $Root
$cache=Get-DependencyCacheRoot $Root
$old=Join-Path $cache '.tools/existing/tool'
New-Item -ItemType Directory -Force -Path ([IO.Path]::GetDirectoryName($old))|Out-Null
[IO.File]::WriteAllText($old,'original')
Start-DependencyCache
$new=Join-Path $cache '.tools/fzf/windows-arm64/0.75.0/fzf.exe'
New-Item -ItemType Directory -Force -Path ([IO.Path]::GetDirectoryName($new))|Out-Null
[IO.File]::WriteAllText($new,$env:SELECTOR_FIXTURE)
if($env:OS -ne 'Windows_NT') { & chmod u+x $new }
Complete-Origin $cache ''
$undoAst=[System.Management.Automation.Language.Parser]::ParseFile($UndoSource,[ref]$tokens,[ref]$errors)
$definition=$undoAst.Find({param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Find-UndoSelector'},$true)
. ([scriptblock]::Create($definition.Extent.Text))
function Get-Command { $null }
$selected=Find-UndoSelector
if($selected -cne $new){throw 'external selector not found'}
if($env:MODIFY_CACHE -eq '1'){
 [IO.File]::AppendAllText($new,'later-change')
 try{Restore-DependencyCache $Root;throw 'unexpected restore'}catch{if($_.Exception.Message -eq 'unexpected restore'){throw}}
 if(-not(Test-Path -LiteralPath $new)){throw 'changed cache removed'}
}else{
 Restore-DependencyCache $Root
 if(Test-Path -LiteralPath $new){throw 'new cache remained'}
 if([IO.File]::ReadAllText($old) -cne 'original'){throw 'original cache changed'}
}
Write-Output 'CACHE-ORIGIN-OK'
""")
        for modified in ('0','1'):
            project=self.work/('ps-project-'+modified);project.mkdir()
            result=subprocess.run([pwsh,'-NoLogo','-NoProfile','-File',str(fixture),str(ROOT/'部署/Windows/【Windows】部署.ps1/【Windows】部署.ps1'),str(project),str(ROOT/'部署/Windows/【Windows】反部署.ps1/【Windows】反部署.ps1')],env={**self.env,'LOCALAPPDATA':str(self.work/'ps-cache'),'MODIFY_CACHE':modified,'SELECTOR_FIXTURE':'#!'+sys.executable+'\n'+self.fzf('0.75.0')},cwd='/',capture_output=True,text=True,timeout=20)
            self.assert_ok(result);self.assertIn('CACHE-ORIGIN-OK',result.stdout)

    def cancel_case(self,body,changes):
        child=self.work/'child-pid';env={**self.env,**changes,'FIXTURE_CHILD':str(child)}
        script=self.script("trap 'stop_dependency_children; exit 130' INT TERM\n"+body+'\nprintf unexpected')
        process=subprocess.Popen(['zsh',str(script)],cwd='/',env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
        try:
            deadline=time.monotonic()+4
            while time.monotonic()<deadline:
                if child.exists() or '重试' in self.log.read_text(): break
                time.sleep(.03)
            process.send_signal(signal.SIGTERM)
            stdout,stderr=process.communicate(timeout=4)
            self.assertEqual(process.returncode,130,stdout+stderr);self.assertNotIn('unexpected',stdout)
            if child.exists():
                pid=int(child.read_text())
                with self.assertRaises(ProcessLookupError):os.kill(pid,0)
        finally:
            if process.poll() is None:process.kill();process.wait()

if __name__=='__main__':unittest.main(verbosity=2)
