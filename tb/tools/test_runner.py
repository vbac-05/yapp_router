"""Unit-test result classification without requiring a simulator."""
import unittest
import json
import re
from run import classify, case_name, SIM, TB


class ClassificationTest(unittest.TestCase):
    def test_clean_completion(self):
        self.assertEqual(classify("UVM_INFO tb(1) @ 10: test [TEST_PASS] smoke\nUVM_ERROR : 0", 0)[0], "PASS")

    def test_exit_zero_is_not_sufficient(self):
        self.assertEqual(classify("compile finished", 0)[0], "FAIL")

    def test_error_overrides_pass(self):
        text = "UVM_ERROR tb(1) @ 10: sb [PACKET_MISMATCH] data\n[TEST_PASS]"
        self.assertEqual(classify(text, 0)[0], "FAIL")

    def test_assertion_overrides_pass(self):
        self.assertEqual(classify("SVA_FAILURE output\n[TEST_PASS]", 0)[0], "FAIL")

    def test_expected_negative(self):
        text = "UVM_ERROR tb(1) @ 10: sb [PACKET_MISMATCH] data\n[TEST_FAIL]"
        self.assertEqual(classify(text, 0, ["PACKET_MISMATCH"])[0], "EXPECTED_FAIL")

    def test_negative_requires_exact_ids(self):
        text = "UVM_ERROR tb(1) @ 10: sb [UNEXPECTED_PACKET] data\n[TEST_FAIL]"
        self.assertEqual(classify(text, 0, ["PACKET_MISMATCH"])[0], "FAIL")

    def test_compile_failure_not_expected_negative(self):
        self.assertEqual(classify("xmvlog: *E,NOT_FOUND", 1, ["PACKET_MISMATCH"])[0], "FAIL")

    def test_timeout_not_expected_negative(self):
        self.assertEqual(classify("[PACKET_MISMATCH]", 1, ["PACKET_MISMATCH"], True)[0], "FAIL")

    def test_summary_failure(self):
        self.assertEqual(classify("[TEST_PASS]\nUVM_ERROR : 1", 0)[0], "FAIL")

    def test_fatal_not_expected_negative(self):
        text = "UVM_FATAL tb(1) @ 10: test [PACKET_MISMATCH] fatal\n[TEST_FAIL]"
        self.assertEqual(classify(text, 1, ["PACKET_MISMATCH"])[0], "FAIL")

    def test_manifest_cases_have_unique_names_and_real_classes(self):
        tests = json.loads((SIM / "regression.json").read_text(encoding="utf-8"))["tests"]
        source = (TB / "tests/router_tests.svh").read_text(encoding="utf-8")
        ids = [case_name(test) for test in tests]
        self.assertEqual(len(ids), len(set(ids)))
        for test in tests:
            self.assertRegex(source, rf"class\s+{re.escape(test['name'])}\s+extends\b")
            self.assertTrue(test["seeds"])
            self.assertTrue(all(seed > 0 for seed in test["seeds"]))


if __name__ == "__main__":
    unittest.main()
