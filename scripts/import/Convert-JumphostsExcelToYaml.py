#!/usr/bin/env python3
"""Legacy-Wrapper – bitte Convert-ImportWorkbookToYaml.py verwenden."""
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
DEFAULT = REPO / 'docs' / 'import' / 'Jumphosts_Import.xlsx'
SCRIPT = Path(__file__).resolve().parent / 'Convert-ImportWorkbookToYaml.py'


def main():
    input_path = DEFAULT
    if len(sys.argv) > 1:
        input_path = Path(sys.argv[1])
    cmd = [sys.executable, str(SCRIPT), '-i', str(input_path), '--regenerate']
    print('Hinweis: Convert-JumphostsExcelToYaml.py ist veraltet.')
    print('         Verwenden Sie import/excel/private-access-import.xlsx und')
    print('         scripts/import/Convert-ImportWorkbookToYaml.py')
    raise SystemExit(subprocess.call(cmd))


if __name__ == '__main__':
    main()
