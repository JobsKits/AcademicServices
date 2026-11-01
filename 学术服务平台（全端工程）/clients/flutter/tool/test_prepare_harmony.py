"""Offline contract checks for the Harmony endpoint binding."""
from pathlib import Path
import importlib.util
import unittest

spec = importlib.util.spec_from_file_location('prepare', Path(__file__).with_name('prepare_harmony.py'))
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
        text = (prepare.ROOT / 'harmony/entry/src/main/ets/pages/Index.ets').read_text()
        self.assertNotIn('$rawfile(', text)
        self.assertIn('.fileAccess(false)', text)
        self.assertIn('MixedMode.None', text)
        self.assertIn('.onErrorReceive', text)
        self.assertIn('.onHttpErrorReceive', text)
        self.assertIn('CLIENT_ORIGIN +', text)
        self.assertNotIn('handleConfirm', text)


if __name__ == '__main__':
    unittest.main(verbosity=2)
