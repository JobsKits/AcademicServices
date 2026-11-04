"""PowerShell pipeline-output regression using an isolated fake SDK."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = next(parent for parent in Path(__file__).resolve().parents if (parent / '代码').is_dir() and (parent / '测试').is_dir())


class BootstrapTests(unittest.TestCase):
    def test_windows_bootstrap_returns_only_python_path(self):
        pwsh = shutil.which("pwsh")
        if not pwsh or os.name == "nt":
            self.skipTest("POSIX PowerShell fixture unavailable; Windows native remains separate")
        source = ROOT / "代码/前端/PC端/Python/Zhixu/Scripts/bootstrap.ps1"
        with tempfile.TemporaryDirectory(prefix="知序 运行环境夹具 ") as temp:
            temp = Path(temp)
            tools = temp / ".tools/uv"
            tools.mkdir(parents=True)
            executable = tools / "uv.exe"
            executable.write_text('#!/bin/sh\ncase "$2" in\n install) echo fixture-install-log ;;\n find) printf "%s\\n" "$FIXTURE_PYTHON" ;;\n *) echo uv-fixture ;;\nesac\n')
            executable.chmod(0o755)
            expected = str(temp / "managed-python")
            script = temp / "fixture.ps1"
            script.write_text(r'''param($Source,$Project,$Expected)
$ErrorActionPreference='Stop'
$tokens=$null;$errors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile($Source,[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Source syntax error'}
$function=$ast.FindAll({param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Install-Python'},$true)[0]
. ([scriptblock]::Create($function.Extent.Text))
function Confirm-Enter([string]$Text) {}
function Invoke-WebRequest {param([switch]$UseBasicParsing,$Uri,$OutFile);if($Uri.EndsWith('.sha256')){[IO.File]::WriteAllText($OutFile,('0'*64))}else{[IO.File]::WriteAllText($OutFile,'fixture')}}
function Get-FileHash {param($Path,$Algorithm);[pscustomobject]@{Hash=('0'*64)}}
function Expand-Archive {param($LiteralPath,$DestinationPath,[switch]$Force)}
$result=Install-Python
if($result -isnot [string] -or $result -ne $Expected){throw 'SDK logs contaminated the returned Python path'}
Write-Output 'PATH_ONLY_OK'
''')
            result = subprocess.run([pwsh, "-NoLogo", "-NoProfile", "-File", str(script), str(source), str(temp), expected], env={**os.environ, "FIXTURE_PYTHON": expected}, capture_output=True, text=True, timeout=20)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("PATH_ONLY_OK", result.stdout)
            self.assertIn("uv-fixture", result.stdout)


if __name__ == "__main__":
    unittest.main()
