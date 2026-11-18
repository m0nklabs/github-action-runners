"""Regression tests for the exact trusted inline helpers in semgrep-ci.yml.

Run: python3 -m unittest discover -s tests -v
Opt-in real pinned-image checks: SEMGREP_CONTAINER_TESTS=1 python3 -m unittest discover -s tests -v
No dependency installation, target-repository execution, or GPU use.
"""
import copy
import json
import os
from pathlib import Path
import subprocess
import tempfile
import textwrap
import unittest
from unittest.mock import patch


WORKFLOW = Path(__file__).resolve().parents[1] / '.github/workflows/semgrep-ci.yml'
TEXT = WORKFLOW.read_text()
IMAGE = 'semgrep/semgrep@sha256:cc1b68266f267878b39739373ea9985b9a78e5d64497dd875c8de100b22695ed'


def helper(marker):
    """Execute the workflow's body verbatim, not a reimplementation of the gate."""
    begin = f'          # BEGIN {marker}\n'
    end = f'          # END {marker}\n'
    return textwrap.dedent(TEXT.split(begin, 1)[1].split(end, 1)[0])


SCAN = helper('SCAN HELPER')
GATE = helper('REPORT GATE')


def run_():
    return {
        'tool': {'driver': {'name': 'Semgrep OSS', 'semanticVersion': '1.184.0', 'rules': [
            {'id': 'test', 'defaultConfiguration': {'level': 'error'}}
        ]}},
        'invocations': [{'executionSuccessful': True, 'toolExecutionNotifications': []}],
        'results': [],
    }


class GateTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='semgrep-gate-test-')
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.sarif = {'version': '2.1.0', 'runs': [run_()]}
        self.coverage = {'version': '1.184.0', 'results': [], 'errors': [], 'paths': {'scanned': ['test.py']}}

    def gate(self, threshold='error', sarif=True, coverage=True):
        if sarif:
            (self.directory / 'semgrep.sarif').write_text(json.dumps(self.sarif))
        if coverage:
            (self.directory / 'semgrep.json').write_text(json.dumps(self.coverage))
        return subprocess.run(
            ['python3', '-I', '-c', GATE],
            env={**os.environ, 'RUNNER_TEMP': str(self.directory.parent),
                 'REPORT_NAME': self.directory.name, 'SEMGREP_FAIL_ON': threshold},
            capture_output=True, text=True,
        )

    def finding(self, **fields):
        self.sarif['runs'][0]['results'] = [{'ruleId': 'test', 'message': {'text': 'Synthetic'}, **fields}]

    def test_clean(self):
        self.assertEqual(self.gate().returncode, 0)

    def test_error_blocks(self):
        self.finding()
        self.assertEqual(self.gate().returncode, 1)

    def test_report_first_default_contract(self):
        block = TEXT.split('      fail-on:\n', 1)[1].split('      runs-on:\n', 1)[0]
        self.assertIn('        default: none\n', block)

    def test_none_allows_findings(self):
        self.finding()
        self.assertEqual(self.gate('none').returncode, 0)

    def test_result_level_overrides_rule_default(self):
        self.finding(level='warning')
        self.assertEqual(self.gate().returncode, 0)
        self.assertEqual(self.gate('warning').returncode, 1)
        self.sarif['runs'][0]['tool']['driver']['rules'][0]['defaultConfiguration']['level'] = 'note'
        self.finding(level='error')
        self.assertEqual(self.gate().returncode, 1)

    def test_info_and_none_are_nonblocking(self):
        for severity in ('note', 'none'):
            with self.subTest(severity=severity):
                self.finding(level=severity)
                self.assertEqual(self.gate('warning').returncode, 0)

    def test_missing_default_level_is_sarif_warning(self):
        self.sarif['runs'][0]['tool']['driver']['rules'][0].pop('defaultConfiguration')
        self.finding()
        self.assertEqual(self.gate('warning').returncode, 1)

    def test_in_source_suppression_honored(self):
        for status in (None, 'accepted'):
            suppression = {'kind': 'inSource'}
            if status:
                suppression['status'] = status
            self.finding(suppressions=[suppression])
            self.assertEqual(self.gate().returncode, 0)

    def test_external_unapproved_rejected_suppressions_do_not_bypass(self):
        for suppression in ({'kind': 'external'}, {'kind': 'inSource', 'status': 'rejected'},
                            {'kind': 'inSource', 'status': 'underReview'}):
            with self.subTest(suppression=suppression):
                self.finding(suppressions=[suppression])
                self.assertEqual(self.gate().returncode, 1)

    def test_all_runs_gated(self):
        second = run_()
        second['results'] = [{'ruleId': 'test', 'message': {'text': 'Synthetic'}}]
        self.sarif['runs'].append(second)
        self.assertEqual(self.gate().returncode, 1)

    def test_no_targets_visibly_fails_even_none(self):
        self.coverage['paths']['scanned'] = []
        result = self.gate('none')
        self.assertEqual(result.returncode, 2)
        self.assertIn('NO TARGETS SCANNED', result.stdout)

    def test_missing_reports(self):
        self.assertEqual(self.gate(sarif=False).returncode, 2)
        (self.directory / 'semgrep.json').unlink()
        self.assertEqual(self.gate(coverage=False).returncode, 2)

    def test_malformed_reports_fail_closed_even_none(self):
        original_sarif = copy.deepcopy(self.sarif)
        original_coverage = copy.deepcopy(self.coverage)
        bad_sarif = [None, {}, {'version': '2.1.0', 'runs': []}]
        for field, value in [('results', None), ('results', {}), ('invocations', []),
                             ('invocations', [{'executionSuccessful': False}]),
                             ('invocations', [{}])]:
            report = copy.deepcopy(original_sarif)
            report['runs'][0][field] = value
            bad_sarif.append(report)
        for rules in ([], None, {}, [{'id': 'test'}, {'id': 'test'}], [{'id': None}]):
            report = copy.deepcopy(original_sarif)
            report['runs'][0]['tool']['driver']['rules'] = rules
            bad_sarif.append(report)
        for result in ({'ruleId': 'absent'}, {'ruleId': 'test', 'level': 'INVALID'},
                       {'ruleId': 'test', 'suppressions': {}},
                       {'ruleId': 'test', 'suppressions': [{'kind': 'bogus'}]}):
            report = copy.deepcopy(original_sarif)
            report['runs'][0]['results'] = [{'message': {'text': 'Synthetic'}, **result}]
            bad_sarif.append(report)
        for report in bad_sarif:
            with self.subTest(sarif=report):
                self.sarif = report
                self.assertEqual(self.gate('none').returncode, 2)
        self.sarif = original_sarif
        for report in ({}, {'version': '0'}, {**original_coverage, 'errors': [{}]},
                       {**original_coverage, 'paths': {}},
                       {**original_coverage, 'paths': {'scanned': [None]}}):
            with self.subTest(coverage=report):
                self.coverage = report
                self.assertEqual(self.gate('none').returncode, 2)

    def test_invalid_json(self):
        (self.directory / 'semgrep.sarif').write_text('{')
        self.assertEqual(self.gate(sarif=False).returncode, 2)

    def test_empty_report(self):
        (self.directory / 'semgrep.sarif').touch()
        self.assertEqual(self.gate(sarif=False).returncode, 2)

    def test_scanner_notifications_even_none(self):
        for key in ('toolExecutionNotifications', 'toolConfigurationNotifications'):
            for severity in ('error', 'warning'):
                self.sarif['runs'][0]['invocations'] = [{
                    'executionSuccessful': True, key: [{'level': severity}]
                }]
                self.assertEqual(self.gate('none').returncode, 2)

    def test_required_report_structure(self):
        original = copy.deepcopy(self.sarif)
        for field in ('name', 'semanticVersion'):
            self.sarif = copy.deepcopy(original)
            self.sarif['runs'][0]['tool']['driver'].pop(field)
            self.assertEqual(self.gate('none').returncode, 2)
        self.sarif = original
        self.finding()
        self.sarif['runs'][0]['results'][0].pop('message')
        self.assertEqual(self.gate('none').returncode, 2)
        self.sarif['runs'][0]['results'] = []
        for value in (None, 'not an array'):
            self.coverage['results'] = value
            self.assertEqual(self.gate('none').returncode, 2)

    def test_invalid_threshold(self):
        self.assertEqual(self.gate('invalid').returncode, 2)


class ScanFixture(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='semgrep-scan-test-')
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.workspace = self.directory / 'repo'
        self.workspace.mkdir()
        self.environment = {
            'SEMGREP_FAIL_ON': 'error', 'SEMGREP_CONFIG': 'p/default',
            'SEMGREP_JOBS': '2', 'SEMGREP_IMAGE': IMAGE,
            'GITHUB_WORKSPACE': str(self.workspace), 'SEMGREP_SRC_DIR': '.',
            'RUNNER_TEMP': str(self.directory), 'REPORT_NAME': 'report',
        }


class ScanTests(ScanFixture):
    def scan(self, **changes):
        with patch.dict(os.environ, {**self.environment, **changes}), patch('subprocess.run') as run:
            exec(compile(SCAN, str(WORKFLOW), 'exec'), {})
            return run

    def test_one_scan_exact_outputs_readonly_source(self):
        run = self.scan()
        run.assert_called_once()
        command = run.call_args.args[0]
        self.assertIn(IMAGE, command)
        self.assertIn(f'{self.workspace}:/src:ro', command)
        self.assertIn('--sarif', command)
        self.assertIn('--json-output=/out/semgrep.json', command)
        self.assertIn('--strict', command)
        self.assertNotIn('--error', command)
        self.assertNotIn('--fail-on', command)
        self.assertTrue(run.call_args.kwargs['check'])

    def test_nondefault_inputs_and_literal_metacharacters(self):
        (self.workspace / 'app').mkdir()
        run = self.scan(SEMGREP_SRC_DIR='app', SEMGREP_JOBS='3', SEMGREP_FAIL_ON='warning',
                        SEMGREP_CONFIG='p/python "rules with spaces.yml" "$(touch sentinel)"')
        command = run.call_args.args[0]
        for value in ('/src/app', '--jobs=3', '--config=p/python',
                      '--config=rules with spaces.yml', '--config=$(touch sentinel)'):
            self.assertIn(value, command)
        self.assertFalse((self.workspace / 'sentinel').exists())

    def test_invalid_inputs_never_invoke_docker(self):
        for changes in ({'SEMGREP_FAIL_ON': 'oops'}, {'SEMGREP_CONFIG': ''},
                        {'SEMGREP_CONFIG': '"'}, {'SEMGREP_CONFIG': '""'},
                        {'SEMGREP_JOBS': '0'}, {'SEMGREP_JOBS': '1.5'},
                        {'SEMGREP_JOBS': '17'}, {'SEMGREP_SRC_DIR': '..'},
                        {'SEMGREP_SRC_DIR': '/tmp'}):
            with self.subTest(changes=changes), self.assertRaises((SystemExit, ValueError)):
                self.scan(**changes)

    def test_symlink_escape_rejected(self):
        (self.workspace / 'escape').symlink_to(self.directory, target_is_directory=True)
        with self.assertRaises(SystemExit):
            self.scan(SEMGREP_SRC_DIR='escape')

    def test_stale_report_directory_rejected(self):
        (Path(self.environment['RUNNER_TEMP']) / self.environment['REPORT_NAME']).mkdir()
        with self.assertRaises(FileExistsError):
            self.scan()

    def test_scanner_runtime_failure_propagates_even_none(self):
        with patch.dict(os.environ, {**self.environment, 'SEMGREP_FAIL_ON': 'none'}), \
                patch('subprocess.run', side_effect=subprocess.CalledProcessError(125, 'docker')):
            with self.assertRaises(subprocess.CalledProcessError):
                exec(compile(SCAN, str(WORKFLOW), 'exec'), {})

    def test_trusted_inline_and_no_secrets(self):
        self.assertEqual(TEXT.count("'semgrep', 'scan'"), 1)
        self.assertNotIn('continue-on-error', TEXT)
        self.assertNotIn('secrets: inherit', TEXT)
        self.assertNotIn('upload-sarif', TEXT)
        self.assertNotIn('output-format:', TEXT)
        self.assertIn('persist-credentials: false', TEXT)
        self.assertEqual(TEXT.count('python3 -I -'), 2)


@unittest.skipUnless(os.environ.get('SEMGREP_CONTAINER_TESTS') == '1', 'opt-in pinned Docker image validation')
class ContainerTests(ScanFixture):
    # Only synthetic fixtures are mounted into the scanner.
    def actual_scan(self, code, config='rules.yml', filename='test.py'):
        (self.workspace / filename).write_text(code)
        (self.workspace / 'rules.yml').write_text('''rules:
  - id: test-error
    languages: [python]
    severity: ERROR
    message: Synthetic test finding
    pattern: danger(...)
  - id: test-warning
    languages: [python]
    severity: WARNING
    message: Synthetic warning
    pattern: caution(...)
''')
        return subprocess.run(
            ['python3', '-I', '-c', SCAN],
            env={**os.environ, **self.environment, 'SEMGREP_CONFIG': config},
            capture_output=True, text=True,
        )

    def actual_gate(self, threshold='error'):
        return subprocess.run(['python3', '-I', '-c', GATE],
                              env={**os.environ, **self.environment, 'SEMGREP_FAIL_ON': threshold},
                              capture_output=True, text=True)

    def test_actual_clean_scan(self):
        result = self.actual_scan('safe = 1\n')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.actual_gate().returncode, 0)
        self.assertEqual(((Path(self.environment['RUNNER_TEMP']) / self.environment['REPORT_NAME']) / 'semgrep.sarif').stat().st_uid, os.getuid())

    def test_actual_error_and_suppression(self):
        result = self.actual_scan('danger(1)\ncaution(2)\ndanger(3)  # nosemgrep: test-error\n')
        self.assertEqual(result.returncode, 0, result.stderr)
        gate = self.actual_gate()
        self.assertEqual(gate.returncode, 1, gate.stdout)
        self.assertIn('1 ERROR, 1 WARNING', gate.stdout)
        self.assertIn('1 in-source suppressed', gate.stdout)
        self.assertEqual(self.actual_gate('none').returncode, 0)

    def test_actual_warning_only(self):
        result = self.actual_scan('caution(2)\n')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.actual_gate().returncode, 0)
        self.assertEqual(self.actual_gate('warning').returncode, 1)

    def test_actual_bad_config(self):
        result = self.actual_scan('safe = 1\n', config='missing-rules.yml')
        self.assertNotEqual(result.returncode, 0)
        self.assertNotEqual(self.actual_gate('none').returncode, 0)

    def test_actual_no_applicable_targets(self):
        # Python-only rules cannot certify a PowerShell-only target as clean.
        # p/default generic rules may scan it; that is not language coverage.
        result = self.actual_scan('Write-Output "not Python"\n', filename='unsupported.ps1')
        self.assertEqual(result.returncode, 0, result.stderr)
        result = self.actual_gate('none')
        self.assertEqual(result.returncode, 2, result.stdout)
        self.assertIn('NO TARGETS SCANNED', result.stdout)


if __name__ == '__main__':
    unittest.main()
