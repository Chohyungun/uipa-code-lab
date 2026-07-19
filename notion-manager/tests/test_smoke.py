"""수집 0건(pytest exit 5) 방지용 스모크 — 최초 커밋부터 pytest가 성공 종료해야 한다."""
from __future__ import annotations

import sys


def test_python_version():
    assert sys.version_info >= (3, 12)


def test_smoke():
    assert 1 + 1 == 2
