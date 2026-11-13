"""Offline contract checks for the Harmony endpoint binding."""
from pathlib import Path
import importlib.util
import json
import subprocess
import unittest

ROOT = next(parent for parent in Path(__file__).resolve().parents if (parent / '代码').is_dir() and (parent / '测试').is_dir())

spec = importlib.util.spec_from_file_location('prepare', ROOT / '代码/前端/移动端/Flutter/Tool/prepare_harmony.py')
prepare = importlib.util.module_from_spec(spec)
spec.loader.exec_module(prepare)


class EndpointTests(unittest.TestCase):
    def test_same_https_origin(self):
        self.assertEqual(prepare.endpoint_config('https://service.example/api/v1'),
                         ('https://service.example', 'https://service.example/client/?host=harmony'))

    def test_explicit_port_preserved(self):
        self.assertEqual(prepare.endpoint_config('https://service.example:8443/api/v1/')[0],
                         'https://service.example:8443')
        self.assertEqual(prepare.endpoint_config('https://SERVICE.example:443/api/v1')[0],
                         'https://service.example')
        self.assertEqual(prepare.endpoint_config('https://[::1]:8443/api/v1')[0],
                         'https://[::1]:8443')

    def test_rejects_credentials_non_https_and_ambiguous_paths(self):
        for value in ['file:///web/index.html', 'http://service.example/api/v1',
                      'https://user:pass@service.example/api/v1', 'https://service.example/api/v1?x=1',
                      'https://service.example/api/v1#fragment', 'https://service.example/wrong',
                      'https://service.example:bad/api/v1']:
            with self.subTest(value=value):
                with self.assertRaises(ValueError):
                    prepare.endpoint_config(value)

    def test_host_never_uses_file_origin_or_tls_bypass(self):
        text = (prepare.ROOT.parent / '鸿蒙/entry/src/main/ets/Pages/Index.ets').read_text()
        self.assertNotIn('$rawfile(', text)
        self.assertIn('.fileAccess(false)', text)
        self.assertIn('MixedMode.None', text)
        self.assertIn('.onErrorReceive', text)
        self.assertIn('.onHttpErrorReceive', text)
        self.assertIn('navigationKind(target, CLIENT_ORIGIN', text)
        self.assertNotIn('handleConfirm', text)

    def test_navigation_policy_runs_against_valid_invalid_and_gesture_cases(self):
        source = prepare.ROOT.parent / '鸿蒙/entry/src/main/ets/Pages/Index.ets'
        cases = [
            ('https://service.example/client/#orders', True, False, 'internal'),
            ('https://SERVICE.example:443/client/', True, False, 'internal'),
            ('https://outside.example/course?q=1', True, True, 'external'),
            ('http://outside.example/course', True, True, 'external'),
            ('https://outside.example/course', True, False, 'blocked'),
            ('https://outside.example/frame', False, True, 'blocked'),
            ('https://service.example.evil.example/client/', True, True, 'external'),
            ('https://service.example.evil.example/client/', True, False, 'blocked'),
            ('https://user:pass@outside.example/', True, True, 'blocked'),
            ('https://outside.example:bad/', True, True, 'blocked'),
            ('https://outside.example:0/', True, True, 'blocked'),
            ('https://outside.example/has space', True, True, 'blocked'),
            ('https://outside.example\\path', True, True, 'blocked'),
            ('javascript:alert(1)', True, True, 'blocked'),
            ('data:text/html,hello', True, True, 'blocked'),
            ('file:///private/data', True, True, 'blocked'),
            ('about:blank', True, True, 'blocked'),
        ]
        script = r'''
const fs=require('fs'),vm=require('vm');
const source=fs.readFileSync(process.argv[1],'utf8');
let policy=source.slice(source.indexOf('export function navigationKind'),source.indexOf('@Entry'));
policy=policy.replace('export function','function').replace(/: (string|boolean)/g,'');
const scope={url:{URL:{parseURL:value=>new URL(value)}}};
vm.createContext(scope);vm.runInContext(policy,scope);
const cases=JSON.parse(fs.readFileSync(0,'utf8'));
const results=cases.map(([target,main,gesture])=>scope.navigationKind(target,'https://service.example',main,gesture));
if(scope.navigationKind('https://outside.example/','',true,true)!=='blocked')throw Error('unconfigured external origin');
if(scope.navigationKind('about:blank','',true,false)!=='internal')throw Error('unconfigured blank page');
process.stdout.write(JSON.stringify(results));
'''
        result = subprocess.run(['node', '-e', script, str(source)], input=json.dumps(cases),
                                capture_output=True, text=True, check=True)
        self.assertEqual(json.loads(result.stdout), [case[3] for case in cases])

    def test_window_open_releases_handler_and_only_browses_user_http_requests(self):
        text = (prepare.ROOT.parent / '鸿蒙/entry/src/main/ets/Pages/Index.ets').read_text()
        self.assertIn('.multiWindowAccess(true)', text)
        self.assertIn('.allowWindowOpenMethod(true)', text)
        self.assertIn('event.handler.setWebController(null)', text)
        self.assertIn('if (!event.isUserTrigger)', text)
        self.assertIn('event.data.isRequestGesture() && !event.data.isRedirect()', text)
        self.assertIn("action: 'ohos.want.action.viewData'", text)
        self.assertIn("entities: ['entity.system.browsable']", text)
        self.assertNotIn('com.huawei.hmos.browser', text)
        self.assertIn('this.controller.loadUrl(event.targetUrl)', text)
        tool = (prepare.ROOT / 'Tool/prepare_harmony.py').read_text()
        self.assertIn('this tool generates Endpoint.ets only', tool)


if __name__ == '__main__':
    unittest.main(verbosity=2)
