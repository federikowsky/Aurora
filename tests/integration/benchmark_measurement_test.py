import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('measurement', Path(__file__).resolve().parents[2] / 'benchmarks/compare_admission.py')
measurement = importlib.util.module_from_spec(spec)
spec.loader.exec_module(measurement)
RAW = '100 requests in 5.0s\nRequests/sec: 20.0\np50_us=1.0 p95_us=2.0 p99_us=3.0 p999_us=4.0\n'

class MeasurementTest(unittest.TestCase):
    def test_errors_are_ineligible(self):
        for error in ['Non-2xx or 3xx responses: 100', 'Socket errors: connect 0, read 1, write 0, timeout 0']:
            result = measurement.parse_wrk(RAW + error)
            self.assertIs(result.get('eligible'), False)
            self.assertTrue(result['errors'])

    def test_all_percentiles_are_required(self):
        with self.assertRaises(ValueError):
            measurement.parse_wrk(RAW.replace('p999_us=4.0', ''))

    def test_complete_clean_output_is_eligible(self):
        result = measurement.parse_wrk(RAW)
        self.assertIs(result.get('eligible'), True)
        self.assertEqual(result['requests'], 100)
        self.assertEqual(result['p999'], 4)

if __name__ == '__main__':
    unittest.main()
