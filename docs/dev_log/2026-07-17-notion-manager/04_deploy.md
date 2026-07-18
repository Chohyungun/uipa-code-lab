# 배포·운영 리뷰 — notion_manager M1 MVP

> 리뷰 대상: `docs/dev_log/2026-07-17-notion-manager/01_spec_planner.md`
> 참조: `00_cto_brief.md`(불변 제약 7·8), `notion-manager/pyproject.toml`, `notion-manager/uv.lock`,
> `notion-manager/.env.example`, `notion-manager/README.md`, `.gitignore`,
> `notion-manager/docs/NOTION_AGENT_HANDOVER.md` 2장.
> 현재 상태 확인: `notion-manager/tests/` 없음, `.github/workflows` 없음(CI 부재),
> `notion-manager/agent/workspace_map.json`은 BOM 없는 UTF-8 한국어 JSON(확인됨),
> `uv run pytest` 실행 결과 **exit code 5**(수집된 테스트 0개, 실측 확인).

## Critical (must fix before implementation)

- **[C1] Windows 콘솔/파일 인코딩(cp949) 미대응 — 한국어 파일 로드·로그 출력이 크래시/깨짐 위험**
  — §4.1(로그 마스킹/`setup_logging`), §5.6-5(`load_workspace_map`), §2.1(응답에 ✅⚠️👀📝 등 이모지
  포함), `notion-manager/agent/workspace_map.json`(BOM 없는 UTF-8, 한국어 실제 확인됨).
  스펙은 Python 3.12(D1, `.python-version`=3.12)를 고정하는데, 3.12는 PEP 686 UTF-8 기본 모드
  이전 버전이라 Windows에서 `open()`/`json.load(open(path))`/`Path.read_text()`를 `encoding="utf-8"`
  없이 호출하면 로케일 코드페이지(한국어 Windows 기본 cp949)로 디코딩을 시도한다.
  `load_workspace_map()`이 UTF-8로 저장된 JSON을 cp949로 열면 `UnicodeDecodeError`로 죽거나
  깨진 문자열이 시스템 프롬프트에 들어간다. 반대 방향으로, 콘솔/로그에 한국어+이모지
  (✅/⚠️/👀/📝, §2.1·§5.5)를 출력할 때도 스트림 인코딩이 cp949면 `UnicodeEncodeError`(이모지는
  cp949 표현 범위 밖) 또는 로그 손실이 발생한다. 스펙 §6 어디에도 `encoding="utf-8"` 강제,
  `PYTHONUTF8=1`/`sys.stdout.reconfigure(encoding="utf-8")` 같은 대응이 없다.
  — **해결 제안**: (1) 모든 텍스트 파일 I/O에 `encoding="utf-8"` 명시를 `config.py`/`agent/prompts.py`
  공개 인터페이스 계약에 못박기, (2) `main.py` 진입점 또는 실행 문서(README)에
  `PYTHONUTF8=1` 환경변수 설정(또는 `uv run python -X utf8 main.py`) 명시, (3) 로깅 핸들러
  스트림에 `errors="backslashreplace"` 등 완화 처리 고려.

- **[C2] `uv run pytest` 게이트가 구현 착수 시점부터 즉시 실패(exit 5) — 그린 유지 계획 부재**
  — 브리프 불변 제약 7·8, 스펙 §1 DoD 항목 8("`uv run pytest` / `uv run ruff check .` 그린"),
  §7("TDD RED→GREEN … 구현 순서 권장"). 실측: 현재 `notion-manager/tests/` 디렉터리가 없는
  상태에서 `uv run pytest`를 실행하면 `collected 0 items` + **exit code 5**를 반환한다(재현 확인).
  `uv run ruff check .`는 대상 파일이 없어도 exit 0으로 통과하지만 pytest는 그렇지 않다.
  스펙은 "그린 유지"를 최종 완료 조건으로만 서술하고, CI가 없는 상태(`.github/workflows` 부재
  확인)에서 구현 중간 단계마다 이 게이트를 누가·어떻게 확인하는지, 그리고 첫 커밋 시점에
  `tests/` 자체가 없어 즉시 게이트가 깨지는 구조적 문제를 다루지 않는다.
  — **해결 제안**: 구현 순서(§7)의 0번째 단계로 "`tests/conftest.py` + 최소 스모크 테스트
  1개(`assert True` 수준이라도)를 다른 어떤 실 코드보다 먼저 커밋"을 명시하거나,
  `pyproject.toml`의 `[tool.pytest.ini_options]`에 `addopts = "-p no:cacheprovider"` 류가 아니라
  빈 컬렉션을 실패로 취급하지 않는 러너 래퍼(예: `uv run pytest || [ $? -eq 5 ]`)를 구현 문서에
  명시. CI가 없으므로 "그린 게이트"를 로컬에서 강제할 절차(예: 각 서브에이전트 커밋 전 실행
  체크리스트)를 §7에 문장으로 못박을 것.

- **[C3] 런타임 파일 경로(workspace_map.json, sessions.db)가 실행 위치(cwd)에 안전하다는 계약이
  스펙에 없음 — fail-fast 위반 가능성**
  — §2.2("파일: `notion-manager/data/sessions.db`"), §5.6-5(`load_workspace_map(path)`),
  §6 `config.py` Settings 필드(`db_path: Path` 등), §4.1(".env 위치는 `pathlib` 기준 명시 경로로
  탐색"). `.env` 로딩만 "명시 경로"로 콕 집어 요구했을 뿐, `db_path`와 `workspace_map.json` 경로는
  `Path(__file__).resolve().parent` 기준 절대경로로 앵커링하라는 요구가 없다. README(§6 변경목록)는
  `cd notion-manager && uv run python main.py`를 전제하지만, 실제 상시 구동(작업 스케줄러/서비스
  등록, 다른 cwd에서 기동)에서 상대경로를 쓰면: (a) `workspace_map.json`을 못 찾아 첫 실제 요청
  처리 중(시스템 프롬프트 조립 시점)에야 크래시하거나 — 브리프 불변 제약 7·DoD가 요구하는
  "기동 시점 검증(fail-fast)"을 정면으로 위반, (b) `data/sessions.db`가 의도치 않은 위치에 새로
  생성되어 기존 세션 기록과 단절된 채 조용히 새 DB로 동작(에러 없이 데이터만 유실) — DoD
  항목 3("재시작 후에도 후속 피드백 이어짐")을 무력화.
  — **해결 제안**: `config.py`의 `load_settings`/`Settings.db_path`와 `agent/prompts.py`의
  `load_workspace_map` 기본 경로를 전부 `Path(__file__).resolve().parent` 기준으로 계산하도록
  공개 인터페이스 계약에 명시. `main.py`에서 두 파일 모두 기동 시점에 존재 확인 후 없으면
  `.env` 필수 키 누락과 동일한 수준으로 즉시 종료(현재는 `.env` 키만 그렇게 다룸).

## Important (should fix)

- **[I1] `pyproject.toml` 의존성 하한이 스펙이 전제하는 SDK 메이저 버전과 불일치**
  — §2.3/§2.5/§3.2/§3.3(정확히 openai 2.46.0/anthropic 0.117.0/notion-client 3.1.0/
  discord-py 2.7.1/aiosqlite 0.22.1을 "고정"으로 서술), `notion-manager/pyproject.toml`
  (`discord-py>=2.4`, `openai>=1.60`, `anthropic>=0.40`, `notion-client>=2.3`, `aiosqlite>=0.20`).
  `uv.lock` 실측 확인 결과 현재 고정 버전은 스펙과 일치하나(문제 없음), `pyproject.toml`의
  하한은 훨씬 낡은 범위를 여전히 허용한다. 특히 `notion-client>=2.3`은 실제로 작동 불가능한
  범위를 포함한다 — §2.5가 쓰는 `client.data_sources.query()`(data source 기반 API)는
  notion-client 3.x부터 존재하므로, 2.3~2.x대에서 lock을 재생성하면 코드 자체가 동작하지
  않는 버전이 설치될 수 있다. §6은 "pyproject.toml 변경 최소 — 의존성 추가 없음"이라고만
  적어 이 하한 불일치를 그대로 남기기로 했는데, 이는 "신규 의존성 추가 없음"과
  "정확한 버전 요구사항이 하한에 반영됨"을 혼동한 것이다. `uv.lock`이 커밋되어 있어 당장
  `uv sync`는 안전하지만(lock이 최신이면 재해석 없이 그대로 설치), `uv lock --upgrade`나
  pyproject.toml 편집으로 인한 재해석 시 조용히 깨질 잠재 트랩이다.
  — **해결 제안**: 하한을 실측 고정 버전에 맞춰 좁히거나(예: `notion-client>=3.1,<4`), 최소한
  구현 문서에 "`uv lock --upgrade` 금지, `uv sync`(lock 그대로 설치)만 사용"을 명시.

- **[I2] 크래시 시 부분 실행(Notion 쓰기 성공 + 세션 기록 유실) 시나리오 미대응**
  — §3.3 "에이전트 루프" 4번("종료 시 이번 요청에서 생성된 중립 메시지 전부를 SessionStore에
  저장(원자적으로 커밋)"), §5.1. 히스토리 커밋이 루프 **종료 시점에만** 일어나므로, 루프 도중
  (예: 3번째 tool 턴에서 `create_schedule_entry`가 이미 Notion에 페이지를 만든 직후) 프로세스가
  죽으면 그 Notion 쓰기는 실제로 일어났지만 세션 히스토리에는 전혀 기록되지 않는다. 재기동 후
  사용자가 같은 스레드에 후속 메시지를 보내면(DoD 3) 에이전트는 방금 만든 페이지의 존재를
  전혀 모른 채 재질의/재생성을 시도할 수 있다 — L2 쓰기 상한(요청당 3회, §4.4)이 있어도
  중복 생성 자체를 막지는 못한다. 이 시나리오는 "재시작 시 상태 복구"의 핵심 리스크인데
  §9 리스크 목록에도 없다.
  — **해결 제안**: 최소한 각 tool 결과가 성공(`ok:true`)할 때마다 해당 메시지 1건씩 즉시
  `append_messages`로 부분 커밋(현재 시그니처로도 가능 — 루프 종료까지 기다리지 않고 턴마다
  호출)하도록 §3.3 4번을 수정. 안 되면 최소한 §9 리스크 표에 정직하게 추가.

- **[I3] 감사 추적(누가 뭘 시켰는가) 스키마 공백**
  — §2.2 `messages` 테이블 DDL(`role`, `content`, `created_at`만 존재, 발화자 컬럼 없음),
  §4.2("사용자 제한: 길드 내 사람 전원 허용, 트리거 C는 멘션 불필요"), §5.6("사용자 메시지
  주입 형식 `[요청자: {display_name}]\n...`"). 트리거 C(등록된 스레드의 모든 메시지, §2.1)는
  작성자 제한이 없어 A가 만든 스레드에 B가 이어 쓸 수 있고, 이는 같은 세션으로 처리된다.
  그런데 `messages` 테이블에는 실제 디스코드 작성자 ID가 저장되지 않고, `sessions.created_by`는
  세션 "최초" 생성자 1명만 기록한다. `[요청자: 표시명]` 문구는 LLM 호출 시점에 프롬프트에
  합성될 뿐 §2.4의 저장 포맷 예시에는 없어, DB만으로는 "이 트래커 항목 변경을 실제로 누가
  요청했는지" 사후 재구성이 불가능하다. 5인 사설 길드라 위협은 낮지만, 배포·운영 관점에서
  최소한의 변경 이력 추적조차 안 되는 것은 "감사 추적" 요건(리뷰 포커스 명시)에 못 미친다.
  — **해결 제안**: `messages` 테이블에 `author_id INTEGER` 컬럼 1개만 추가(스키마 변경 비용 거의
  0, 최경량 원칙과 상충 없음). append 시 실제 Discord `message.author.id`를 같이 저장.

- **[I4] 로그 파일 위치·로테이션 완전 미정 — 상시 구동 시 사후 분석 불가**
  — 리뷰 포커스 명시 항목, §6 `config.py::setup_logging(settings) -> None` 시그니처만 있고
  파일 출력 여부/경로/로테이션 언급 없음. `.gitignore`(레포 루트)에는 이미 `logs/`, `*.log`가
  준비돼 있어 파일 로깅을 암묵적으로 기대하는 정황인데, 스펙 §6 변경 목록의 어떤 파일도
  로그 파일 경로를 결정하지 않는다. 콘솔 로그만 남기면: (a) 상시 구동 중 터미널이 닫히거나
  원격/서비스로 무인 실행되는 순간 로그가 전부 사라지고, (b) E6("계속 실패하면 스터디장에게
  알려 주세요", §5.5)의 실효성이 로그 부재로 떨어진다 — 스터디장이 원인을 재구성할 자료가
  없다.
  — **해결 제안**: `setup_logging`이 콘솔 핸들러 외에 `logs/notion_manager.log`
  (C3의 절대경로 앵커링 규칙 적용, `RotatingFileHandler` 또는 `TimedRotatingFileHandler`,
  `encoding="utf-8"` 명시 — C1과 연동)를 추가하도록 §6 계약에 명시.

- **[I5] 폴백 장기 지속 시 감지·경보 메커니즘 부재**
  — §3.3 폴백 규칙, §9 리스크 10번("비용: opus-4-8 폴백은 gpt-5.5 대비 고비용일 수 있다").
  OpenAI 장애/키 문제가 길게 지속되면 매 요청이 계속 Anthropic으로 폴백되는데, 유일한 신호는
  스레드 푸터 한 줄(§2.1)과 WARNING 로그 한 줄(§3.3)뿐이다. 로그를 상시 들여다보는 사람이
  없는 5인 스터디 운영 특성상, 값비싼 opus-4-8 호출이 며칠간 누적돼도 아무도 인지하지 못할
  수 있다. §9는 리스크를 인지했지만 완화책이 "요청당 1회 제한"뿐이라 장기 누적을 막지 못한다.
  — **해결 제안**: M1 범위를 넘지 않는 선에서, 최소 "폴백이 연속 N회 발생하면 ERROR 레벨로
  한 번 더 강조 로그"정도의 저비용 장치만이라도 §3.3에 추가 고려. 부담되면 최소한 §9에
  "운영자가 로그를 주기적으로 확인해야 한다"는 운영 절차를 README에 명문화할 것을 권고.

- **[I6] 잘못된 모델 ID(`gpt-5.5` 오탈자 등)는 폴백을 우회하고 즉시 전면 장애를 일으킨다**
  — §3.3 폴백 조건 표("`BadRequestError` 등 나머지 4xx → ❌"), §8 OQ6(모델 ID 미검증 인정).
  존재하지 않는 모델 ID를 호출하면 OpenAI SDK는 보통 404(`NotFoundError`)를 던지는데, 이는
  스펙의 폴백 표 기준 "나머지 4xx"로 분류되어 **폴백 없이** 바로 사용자에게 에러가 노출된다
  (§5.5 E2/E6 경로). 즉 모델 ID가 틀리면 Anthropic 폴백이 전혀 구제해주지 못하고 봇 전체가
  100% 실패 상태가 된다. OQ6이 "실호출 전 검증 불가"를 이미 인정했지만, 그 실패가 폴백을
  우회하는 전면 장애라는 구체적 결과까지는 §9에 명시돼 있지 않다.
  — **해결 제안**: §9 리스크 1번에 "모델 ID 오류는 폴백 대상이 아니므로 전면 장애로 즉시
  드러난다"는 문장을 추가해 운영자가 첫 실 스모크(S3) 전 리스크 수준을 정확히 인지하게 할 것.

## Minor (nice to have)

- **[M1] `data/sessions.db` 백업 정책 없음(OQ8, 이미 인지됨)에 대한 저비용 완화책 미포함**
  — §8 OQ8은 "없음(M3)"으로 정직하게 인정했으나, README 변경 목록(§6)에 "정기적으로
  `notion-manager/data/sessions.db`를 백업하라"는 한 줄 권고조차 없다. 비용이 거의 0이므로
  M1 README에 문장 하나 추가를 권장.

- **[M2] ruff lint 규칙 셋 미지정**
  — `notion-manager/pyproject.toml`의 `[tool.ruff]`에 `line-length`/`target-version`만 있고
  `[tool.ruff.lint] select=[...]`가 없어 기본 규칙(E4/E7/E9/F류)만 적용된다. "그린 게이트"의
  실효성을 높이려면 import 정렬(I), 버그 위험 패턴(B) 등을 추가로 켜는 것을 고려할 만하나
  M1 완료를 막을 사안은 아님.

- **[M3] 봇 초대 URL 권한 비트 계산 근거가 스펙에 없음**
  — §6 README 변경 목록은 "필요 권한 비트"를 언급만 하고 값/계산법을 주지 않는다. §2.1에
  나열된 6개 권한(View Channels, Send Messages, Create Public Threads, Send Messages in
  Threads, Read Message History, Add Reactions)으로부터 계산한 permission integer를 스펙에
  박아두면 구현자가 별도로 Discord permission calculator를 찾아 헤맬 필요가 없다.

## Questions for the CTO

- pytest exit-5 게이트 문제(C2)를 프로세스 규칙(구현 착수 시 conftest.py+스모크 테스트를
  가장 먼저 커밋)으로 풀지, 아니면 다른 방식으로 풀지 결정이 필요합니다.
- `pyproject.toml` 의존성 하한(I1)을 이번 스펙의 변경 범위에 포함해 좁힐지, 아니면 별도
  chore로 미루고 지금은 "`uv lock --upgrade` 금지"만 문서화할지 확인 부탁드립니다.
- 크래시 시 부분 실행 유실(I2)을 M1에서 턴 단위 부분 커밋으로 완화할지, 아니면 M3로 미루고
  §9 리스크에만 정직하게 추가할지 판단 부탁드립니다.
- `messages` 테이블에 `author_id` 컬럼(I3)을 M1에 추가할지 — 스키마 변경 비용은 거의 0이지만
  최경량 원칙과의 우선순위 판단이 필요합니다.
- 로그 파일 위치/로테이션(I4)을 M1 산출물에 포함할지, 아니면 브리프의 M3("로깅·감사 추적")
  범위로 명확히 미룰지 — 현재 스펙은 애매하게 비워둔 상태라 명시적 결정이 필요합니다.
