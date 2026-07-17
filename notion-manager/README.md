# notion_manager

스터디그룹 Notion 워크스페이스를 디스코드에서 자연어로 관리하는 봇.

디스코드 사용자가 봇을 멘션하거나 지정 채널(`#노션-관리`)에 요청을 올리면,
LLM 자율 에이전트가 Notion API로 처리하고 결과를 "✅ 요약 + 노션 링크" 형태로
스레드에 보고한다. 같은 스레드의 후속 메시지는 같은 세션 컨텍스트로 이어서 처리된다.

> 전체 명세: [docs/NOTION_AGENT_HANDOVER.md](docs/NOTION_AGENT_HANDOVER.md)

## 상태

🚧 스캐폴딩 단계 — 구현 계획 승인 대기 중.

## 구조

```
notion-manager/
├── .env.example           # 환경변수 명세 (실제 값은 루트 .env에만, 커밋 금지)
├── bot/                   # 디스코드 봇 (이벤트 수신, 스레드/세션 매핑)
├── agent/                 # 에이전트 실행 래퍼, 시스템 프롬프트
│   └── workspace_map.json # Notion 워크스페이스 ID/스키마 맵 (핸드오버 문서 5장)
└── docs/
    └── NOTION_AGENT_HANDOVER.md
```

## 개발 환경 (uv)

파이썬 버전·의존성·가상환경은 전부 [uv](https://docs.astral.sh/uv/)로 관리한다
(Python 3.12 고정 — `.python-version`, 잠금 — `uv.lock`).

```bash
cd notion-manager
uv sync              # .venv 생성 + uv.lock 기준 의존성 설치
uv run pytest        # 테스트
uv run ruff check .  # 린트
# 봇 실행 (MVP 구현 후): uv run python -m bot
```

의존성 추가/변경도 uv로만: `uv add <pkg>`, `uv remove <pkg>`.

## 보안

- 실제 토큰/API 키는 저장소 루트 `.env`에만 둔다 (`.gitignore` 대상).
- 삭제/대량 변경 요청은 디스코드 ✅ 리액션 확인 후에만 실행한다 (MVP에서는 미지원 응답).
