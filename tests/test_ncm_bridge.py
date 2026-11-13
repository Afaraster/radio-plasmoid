"""Regression checks for permission filtering, stable IDs and safe CLI invocation."""
import importlib.machinery
import importlib.util
import subprocess
from unittest import TestCase, main
from unittest.mock import patch
from pathlib import Path

loader = importlib.machinery.SourceFileLoader('radio_ncm', str(Path(__file__).parents[1] / 'bin/radio-ncm'))
spec = importlib.util.spec_from_loader(loader.name, loader)
bridge = importlib.util.module_from_spec(spec)
loader.exec_module(bridge)


class BridgeTests(TestCase):
    def test_permission_filter_and_stable_favorites(self):
        song = {'id': 'A' * 32, 'originalId': 42, 'name': '曲目', 'visible': True,
                'playFlag': True, 'artists': [{'name': '歌手'}]}
        hidden = dict(song, id='B' * 32, visible=False)
        unavailable = dict(song, id='C' * 32, playFlag=False)
        with patch.object(bridge, 'cli', return_value={'data': {'records': [song, hidden, unavailable, song]}}):
            result = bridge.search('xxx')
        self.assertEqual(result['songs'], [{'name': '曲目 — 歌手', 'url': 'ncm://' + 'A' * 32 + '/42'}])
        self.assertEqual(result['unavailable'], 2)

    def test_shell_characters_stay_one_argument(self):
        query = "xxx'; touch /tmp/should-not-exist; $(id)"
        response = subprocess.CompletedProcess([], 0, '{"code":200,"data":{"records":[]}}', '')
        with patch.object(bridge.shutil, 'which', return_value='/test/ncm-cli'), \
                patch.object(bridge.subprocess, 'run', return_value=response) as run:
            bridge.search(query)
        argv = run.call_args.args[0]
        self.assertEqual(argv[argv.index('--keyword') + 1], query)
        self.assertNotIn('shell', run.call_args.kwargs)

    def test_invalid_ids_never_reach_player(self):
        with patch.object(bridge, 'cli') as cli:
            with self.assertRaises(bridge.NcmError):
                bridge.main(['play', 'ncm://$(id)/42', '80'])
        cli.assert_not_called()

    def test_api_errors_are_not_empty_results(self):
        response = subprocess.CompletedProcess([], 0, '{"code":429,"message":"请求总量超限"}', '')
        with patch.object(bridge.shutil, 'which', return_value='/test/ncm-cli'), \
                patch.object(bridge.subprocess, 'run', return_value=response):
            with self.assertRaisesRegex(bridge.NcmError, '请求总量超限'):
                bridge.search('xxx')

    def test_cli_without_json_does_not_report_play_success(self):
        response = subprocess.CompletedProcess([], 0, '', '')
        with patch.object(bridge.shutil, 'which', return_value='/test/ncm-cli'), \
                patch.object(bridge.subprocess, 'run', return_value=response):
            with self.assertRaises(bridge.NcmError):
                bridge.main(['play', 'ncm://' + 'A' * 32 + '/42', '80'])


if __name__ == '__main__':
    main()
