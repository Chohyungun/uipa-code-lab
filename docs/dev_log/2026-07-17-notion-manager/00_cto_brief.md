# 00_cto_brief — notion_manager 디스코드 봇 (2026-07-17)

## 목적 (한 줄)

스터디그룹(5명)이 디스코드에서 자연어로 요청하면 LLM 자율 에이전트가 Notion
워크스페이스(일정/트래커/자료실/멤버 페이지)를 대신 관리하고, 결과를 스레드로
보고하며 피드백 루프를 유지하는 봇.

## 검증된 사실 (ground truth)

- **저장소**: `E:\uipa-code-lab`, 사실상 빈 repo (README만 커밋). 작업 브랜치
  `feature/notion-manager-agent` 생성 완료. `.gitignore` 생성 완료 (`.env` 포함 확인).
- **`.env`**: 명세 15개 키 + LLM 프로바이더 5개 키 전부 값 채워짐 (빈 키 없음).
  `DISCORD_GUILD_ID`, `DISCORD_WATCH_CHANNEL_ID`, `NOTION_TOKEN` 등 모두 입력 상태.
  값은 절대 코드/로그/커밋에 노출 금지.
- **런타임 LLM**: `LLM_PROVIDER=openai`, `LLM_MODEL=gpt-5.5`가 1차. 토큰 부족/장애 시
  `.env`의 `CLAUDE_MODEL`(claude-opus-4-8, Anthropic)로 폴백. → **프로바이더 추상화 필수**
  (OpenAI + Anthropic 둘 다 지원하는 얇은 어댑터). 정확한 모델 ID는 공식 문서에서
  확인 후 확정·보고 (지시사항).
- **Notion 워크스페이스**: 핸드오버 문서 5장의 맵이 전부이며 **구조 변경 금지**.
  ID/스키마는 `notion-manager/agent/workspace_map.json`으로 구조화 완료.
  일정/트래커/자료실 3개 DB 모두 database_id + data_source_id 존재
  → Notion API 최신 버전(data source 기반, 2025-09-03+) 사용.
- **개발 주체 vs 런타임 주체**: 이 봇을 개발하는 에이전트(나)는 fable-5.
  봇이 런타임에 호출하는 모델은 위 LLM 설정. 혼동 금지.

## 불변 제약 (모든 하위 에이전트가 상속)

1. `.env` 시크릿을 코드/로그/커밋/문서에 절대 노출하지 않는다.
2. Notion 워크스페이스 구조(페이지 트리, DB 스키마, 홈 레이아웃, 멤버 페이지 구조)를
   임의로 변경하지 않는다. 스키마 변경은 사용자 확인 후에만.
3. 핸드오버 문서 6장 "에이전트 운영 원칙" 7개 항목을 런타임 시스템 프롬프트에 그대로 반영.
4. 삭제/대량 변경: MVP에서는 **미지원 응답** 처리. (M2에서 ✅ 리액션 확인 흐름으로 구현.)
5. 모든 노션 콘텐츠·디스코드 응답은 한국어, 비전공자도 이해할 쉬운 표현.
6. 보고 형식: "✅ 한 일 요약 + 노션 링크". 실패 시 원인 요약 + 대안 제시.
7. **도구 체인 (orch 지시, 이 저장소 한정)**: 파이썬 버전·의존성·가상환경은 **uv**로만
   관리한다 — `notion-manager/pyproject.toml` + `uv.lock` + `.python-version`(3.12 고정),
   실행·테스트는 `uv run` 기준 (`uv run pytest`, `uv run ruff check .`).
   requirements.txt 만들지 말 것. 의존성 변경은 `uv add`/`uv remove`.
8. **OpenAI 실 API 호출 금지 (현 시점)**: OpenAI 키 재발급 전이므로, 실 OpenAI 호출이
   필요한 스모크/통합 테스트 전에 orch 보고가 선행되어야 한다. 단위 테스트는 전부 mock.

## 열린 설계 결정 + CTO 성향(lean)

| # | 결정 | 내 성향 | 근거 |
|---|------|---------|------|
| D1 | 구현 언어/프레임워크 | **Python 3.11+ / discord.py** | 스터디 커리큘럼이 Python 중심(팀이 코드를 읽을 수 있어야 함), 단일 언어로 봇+에이전트 구현 가능 |
| D2 | 에이전트 실행 방식 | **직접 tool-use 루프** (openai + anthropic SDK 어댑터, 자체 Notion 툴 정의) | 프로바이더 전환(gpt-5.5 ↔ claude) 요구가 Claude Agent SDK(Anthropic 전용)를 배제. 자체 루프면 안전장치(삭제/대량 변경 게이트)를 툴 디스패치 지점에 정확히 삽입 가능 |
| D3 | Notion 연동 | **공식 REST API + `notion-client`** (MCP 아님) | 런타임은 무인 데몬 — MCP 서버 의존성보다 직접 API가 단순·안정. data_source_id 기반 최신 버전 사용 |
| D4 | 스레드↔세션 매핑 저장 | **SQLite** (파일 1개, 표준 lib) | 5인 규모에 충분, 재시작 후에도 세션 유지, 외부 인프라 0 |
| D5 | 트리거 | 봇 멘션 + 지정 채널 전체 메시지 **둘 다** | 문서 권장사항 그대로 |
| D6 | 폴백 조건 | OpenAI 호출 실패(rate limit/토큰/5xx) 시 Anthropic으로 1회 폴백, 응답에 사용 모델 표기 | "토큰이 모자라거나 할 때" 지시의 구체화 — 리뷰에서 검증 필요 |

## 마일스톤 (사용자 지시 기반 3단계)

- **M1 (MVP)**: 봇 접속 → 지정 채널/멘션 수신 → 에이전트(gpt-5.5, 폴백 claude) 호출 →
  일정 DB·학습 트래커 항목 생성/수정 → 스레드에 "✅ 요약 + 링크" 응답.
  스레드↔세션 매핑 포함. 삭제/대량 변경은 "미지원" 응답.
  완료 후: README(실행법), 봇 초대 URL 생성법, 테스트 시나리오 3개 보고.
- **M2 (안전장치·기능 확장)**: 삭제/대량 변경 ✅ 리액션 확인 흐름, 자료실 등록,
  회의록(일정 페이지 본문) 작성, 멤버 페이지 업데이트(구조 보존), 초기 백로그 처리
  (박다영→김다영 rename 등).
- **M3 (운영 안정화)**: 에러 복구/재시도, 로깅·감사 추적, 세션 만료 정책,
  배포 방법(상시 구동), 테스트 확충.

## 프로세스

orchestrating-feature-development 스킬 적용:
Phase B 스펙(planner) → Phase C 관점 리뷰(백엔드/보안/배포 — 프론트·RDB·KG는 해당 없음,
디스코드 UX 관점은 백엔드 리뷰에 포함) → Phase D CTO 게이트 → Phase E 플랜 →
Phase F SDD 구현 → Phase G 마무리. **사용자 승인 후 Phase B부터 진행.**
