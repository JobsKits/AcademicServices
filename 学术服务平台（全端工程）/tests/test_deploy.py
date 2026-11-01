"""Read-only/sandbox deployment regressions, never installs system packages."""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]
DEPLOY=ROOT/'backend/deploy'

class DeploymentTests(unittest.TestCase):
    def test_01_shell_syntax(self):
        for p in DEPLOY.rglob('*'):
            if p.suffix not in {'.sh','.command'}:continue
            shell=shutil.which('zsh' if p.suffix=='.command' else 'bash')
            if not shell:raise RuntimeError('Shell missing: '+p.name)
            subprocess.run([shell,'-n',str(p)],check=True,capture_output=True)
    def test_02_powershell_parse(self):
        pwsh=shutil.which('pwsh')
        if not pwsh:self.skipTest('PowerShell parser not installed; Windows remains unverified')
        path=str(DEPLOY/'Windows/deploy.ps1').replace("'","''")
        cmd=f"$e=$null;$t=$null;[System.Management.Automation.Language.Parser]::ParseFile('{path}',[ref]$t,[ref]$e)|Out-Null;$e|%{{$_.Message}};if($e.Count){{exit 1}}"
        subprocess.run([pwsh,'-NoLogo','-NoProfile','-Command',cmd],check=True,capture_output=True)
    def test_03_no_hardcoded_developer_paths(self):
        for p in DEPLOY.rglob('*'):
            if p.suffix in {'.sh','.command','.ps1','.cmd'}:
                s=p.read_text(encoding='utf-8-sig');self.assertNotIn('/Users/jobs',s,p);self.assertNotIn('rm -rf',s,p)
    def test_04_mac_check_relocated_from_unrelated_cwd(self):
        if os.uname().sysname!='Darwin':self.skipTest('Requires macOS')
        with tempfile.TemporaryDirectory(prefix='知序 移动目录 ') as temp:
            p=Path(temp)/'改名工程/backend';(p/'cmd/server').mkdir(parents=True);(p/'go.mod').write_text('module fixture\ngo 1.27\n')
            target=p/'deploy/macOS';target.mkdir(parents=True);shutil.copy2(DEPLOY/'macOS/部署.command',target)
            r=subprocess.run(['zsh',str(target/'部署.command'),'--check'],cwd='/',capture_output=True,text=True)
            self.assertEqual(r.returncode,0,r.stdout+r.stderr);self.assertIn('检查通过',r.stdout);self.assertFalse((p/'.runtime').exists())
    def test_05_eof_cancels_without_writes(self):
        if os.uname().sysname!='Darwin':self.skipTest('Requires macOS')
        with tempfile.TemporaryDirectory() as temp:
            p=Path(temp)/'backend';(p/'deploy/macOS').mkdir(parents=True);target=p/'deploy/macOS/部署.command';shutil.copy2(DEPLOY/'macOS/部署.command',target)
            r=subprocess.run(['zsh',str(target)],input='',capture_output=True,text=True)
            self.assertNotEqual(r.returncode,0);self.assertFalse((p/'.runtime').exists())
    def fixture(self,body,*,answer='\n',fake_go=None):
        with tempfile.TemporaryDirectory(prefix='go-fixture-') as temp:
            p=Path(temp);fake=p/'fake';fake.mkdir();log=p/'calls';log.write_text('')
            if fake_go:
                f=fake/'go';f.write_text('#!/bin/sh\n'+fake_go);f.chmod(0o755)
            prefix=(DEPLOY/'macOS/部署.command').read_text().rsplit('main "$@"',1)[0]
            script=p/'fixture.zsh';script.write_text(prefix+f'\nSERVER_ROOT="{p}"\nLOG_FILE="{log}"\n'+body+'\n')
            env={**os.environ,'GO_BIN':str(fake/'go') if fake_go else '', 'PATH':str(fake)+':/usr/bin:/bin:/usr/sbin:/sbin'}
            r=subprocess.run(['zsh',str(script)],input=answer,text=True,capture_output=True,env=env,cwd='/')
            return r,log.read_text()
    def test_06_healthy_go_reused_no_download(self):
        r,log=self.fixture('ensure_go\nprintf "SDK=%s\\n" "$GO_EXE"',fake_go='echo "go version go1.27.3 darwin/arm64"\n')
        self.assertEqual(r.returncode,0,r.stdout+r.stderr);self.assertIn('SDK=',r.stdout);self.assertNotIn('来源',log)
    def test_07_install_cancel_stops_before_download(self):
        r,log=self.fixture('ensure_go',answer='cancel\n')
        self.assertNotEqual(r.returncode,0);self.assertNotIn('来源｜Go',log)
    def test_08_corrupt_archive_rejected(self):
        r,log=self.fixture('printf damaged > "$SERVER_ROOT/archive"\nGO_SHA=0000000000000000000000000000000000000000000000000000000000000000\nverify_archive "$SERVER_ROOT/archive"')
        self.assertNotEqual(r.returncode,0);self.assertIn('摘要不匹配',log)
    def test_09_script_main_has_first_intro(self):
        for p in DEPLOY.rglob('*'):
            if p.suffix not in {'.sh','.command'}:continue
            lines=p.read_text().split('main() {',1)[1].split('}',1)[0].strip().splitlines()
            self.assertTrue(lines[0].strip().startswith('show_script_intro_and_wait'),p)
            for line in lines:self.assertIn(' # ',line,p)


    def test_10_dangling_config_symlink_cannot_write_outside(self):
        for platform,entry,shell in [('macOS','部署.command','zsh'),('Ubuntu','deploy.sh','bash')]:
            with tempfile.TemporaryDirectory() as temp:
                root=Path(temp);(root/'.runtime').mkdir();outside=root/'outside.env';(root/'.runtime/config.env').symlink_to(outside)
                log=root/'log';log.write_text('')
                prefix=(DEPLOY/platform/entry).read_text().rsplit('main "$@"',1)[0]
                script=root/'fixture';script.write_text(prefix+f'\nSERVER_ROOT="{root}"\nLOG_FILE="{log}"\nconfigure_server\n')
                result=subprocess.run([shell,str(script)],input='\nadmin-password-123\ncustomer-password-123\n\n',text=True,capture_output=True)
                self.assertNotEqual(result.returncode,0);self.assertFalse(outside.exists(),platform)
    def test_11_runtime_symlink_rejected_before_log_creation(self):
        if os.uname().sysname!='Darwin':self.skipTest('Requires zsh fixture')
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);outside=root/'outside';outside.mkdir();(root/'.runtime').symlink_to(outside,target_is_directory=True)
            prefix=(DEPLOY/'macOS/部署.command').read_text().rsplit('main "$@"',1)[0]
            script=root/'fixture';script.write_text(prefix+f'\nSERVER_ROOT="{root}"\nLOG_FILE="{root}/.runtime/logs/test.log"\ninitialize_runtime\n')
            result=subprocess.run(['zsh',str(script)],text=True,capture_output=True)
            self.assertNotEqual(result.returncode,0);self.assertEqual(list(outside.iterdir()),[])

    def test_12_sdk_download_failure_stops(self):
        body='confirm_install() { return 0; }\nensure_transfer_tools() { return 0; }\ncurl() { return 22; }\nensure_go\nprintf unexpected'
        result,log=self.fixture(body)
        self.assertNotEqual(result.returncode,0);self.assertIn('Go下载失败',log);self.assertNotIn('unexpected',result.stdout)
    def test_13_installed_sdk_recheck_failure_stops(self):
        body="""mkdir -p "$SERVER_ROOT/.tools"
confirm_install() { return 0; }
ensure_transfer_tools() { return 0; }
curl() { return 0; }
verify_archive() { return 0; }
tar() { mkdir -p "$staging_dir/go/bin"; printf '#!/bin/sh\\nexit 1\\n' > "$staging_dir/go/bin/go"; chmod +x "$staging_dir/go/bin/go"; }
ensure_go
printf unexpected"""
        result,log=self.fixture(body)
        self.assertNotEqual(result.returncode,0);self.assertIn('Go安装后健康检查失败',log);self.assertNotIn('unexpected',result.stdout)

if __name__=='__main__':unittest.main(verbosity=2)
