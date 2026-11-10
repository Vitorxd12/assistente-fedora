import importlib.machinery
import importlib.util
from pathlib import Path
import unittest

source = Path(__file__).resolve().parents[1] / 'bin/battery-saver'
loader = importlib.machinery.SourceFileLoader('battery_saver', str(source))
spec = importlib.util.spec_from_loader(loader.name, loader)
module = importlib.util.module_from_spec(spec)
loader.exec_module(module)


class Fake:
    target = module.Hardware.target

    def __init__(self, screen=65, boost=0, idle=900):
        self.values = {'screen:panel': screen, 'intel-no-turbo': boost, 'idle-delay': idle}
        self.writes = []
        self.fail = False

    def read(self):
        return dict(self.values)

    def write(self, key, value):
        if self.fail:
            raise PermissionError('mock')
        self.writes.append((key, value))
        self.values[key] = value


class SaverTests(unittest.TestCase):
    def run_saver(self, hw, state, battery):
        module.apply(hw, state, battery, lambda value: None)

    def test_battery_and_restore(self):
        hw, state = Fake(), {}
        original = hw.read()
        self.run_saver(hw, state, True)
        self.assertEqual(hw.read(), {'screen:panel': 65, 'intel-no-turbo': 1, 'idle-delay': 300})
        self.run_saver(hw, state, False)
        self.assertEqual(hw.read(), original)
        self.assertEqual(state['restore'], {})

    def test_repeated_hooks_keep_original_snapshot(self):
        hw, state = Fake(), {}
        self.run_saver(hw, state, True)
        self.run_saver(hw, state, True)
        self.assertEqual(hw.values['screen:panel'], 65)
        self.run_saver(hw, state, False)
        self.assertEqual(hw.values['screen:panel'], 65)

    def test_does_not_brighten_or_enable_turbo(self):
        hw, state = Fake(screen=4, boost=1, idle=120), {}
        self.run_saver(hw, state, True)
        self.assertEqual(hw.writes, [])
        self.run_saver(hw, state, False)
        self.assertEqual(hw.writes, [])

    def test_ac_start_does_not_change_anything(self):
        hw, state = Fake(), {}
        self.run_saver(hw, state, False)
        self.assertEqual(hw.writes, [])

    def test_legacy_screen_snapshot_is_discarded_without_writing(self):
        for battery in (True, False):
            with self.subTest(battery=battery):
                hw = Fake(screen=40)
                state = {'restore': {'screen:panel': 65}}
                self.run_saver(hw, state, battery)
                self.assertNotIn('screen:panel', state['restore'])
                self.assertEqual(hw.values['screen:panel'], 40)
                self.assertFalse(any(key.startswith('screen:') for key, _ in hw.writes))

    def test_permission_failure_keeps_saved_value(self):
        hw, state = Fake(), {}
        hw.fail = True
        with self.assertRaises(PermissionError):
            self.run_saver(hw, state, True)
        self.assertEqual(state['restore']['intel-no-turbo'], 0)
        hw.fail = False
        self.run_saver(hw, state, True)
        self.run_saver(hw, state, False)
        self.assertEqual(hw.values['screen:panel'], 65)

    def test_no_invented_network_or_gpu_settings(self):
        config = {'gpu_mode': 'eco', 'gpu_auto': 0, 'performance_1': 1}
        want = module.preferences(config, '/helper --apply')
        self.assertEqual(want['performance_1'], 1)
        self.assertEqual(want['auto_boost_1'], 1)
        self.assertEqual(config['gpu_mode'], 'eco')
        self.assertFalse(any('gpu' in x or 'wifi' in x or 'bluetooth' in x for x in want))

    def test_preserve_existing_mode_commands(self):
        with self.assertRaises(ValueError):
            module.preferences({'mode_command_2': 'user-command'}, '/helper --apply')

    def test_maximum_ac_and_uninstall_restore(self):
        hw, state = Fake(screen=65, boost=1), {}
        module.performance_ac(hw, state, lambda value: None)
        self.assertEqual(hw.values['screen:panel'], 65)
        self.assertEqual(hw.values['intel-no-turbo'], 0)
        self.run_saver(hw, state, True)
        self.run_saver(hw, state, False)
        module.performance_ac(hw, state, lambda value: None)
        module.restore_ac_original(hw, state, lambda value: None)
        self.assertEqual(hw.values['screen:panel'], 65)
        self.assertEqual(hw.values['intel-no-turbo'], 1)

    def test_maximum_ac_repeated_does_not_lose_backup(self):
        hw, state = Fake(boost=1), {}
        module.performance_ac(hw, state, lambda value: None)
        module.performance_ac(hw, state, lambda value: None)
        self.assertNotIn('screen:panel', state['original_ac'])
        self.assertEqual(state['original_ac']['intel-no-turbo'], 1)


if __name__ == '__main__':
    unittest.main()
