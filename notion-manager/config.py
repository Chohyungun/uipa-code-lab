"""환경설정 로딩·검증, 경로 앵커링(DEP-C3), 로깅+시크릿 마스킹(SEC-C1) 설정."""
from __future__ import annotations

import logging
import logging.handlers
import os
import sys
from collections.abc import Iterable, Mapping
from dataclasses import dataclass
from pathlib import Path

from dotenv import load_dotenv

BASE_DIR = Path(__file__).resolve().parent

REQUIRED_KEYS = (
    "DISCORD_BOT_TOKEN",
    "DISCORD_GUILD_ID",
    "DISCORD_WATCH_CHANNEL_ID",
    "NOTION_TOKEN",
    "NOTION_DS_SCHEDULE",
    "NOTION_DS_TRACKER",
    "OPENAI_API_KEY",
    "ANTHROPIC_API_KEY",
)


class ConfigError(ValueError):
    """설정 오류 — 메시지에 키 '이름'만 담고 값은 절대 담지 않는다."""


def parse_member_ids(raw: str) -> dict[int, str]:
    """'유저ID:멤버명,유저ID:멤버명' 형식 파싱 (SEC-I1). 빈 문자열이면 {}."""
    result: dict[int, str] = {}
    if not raw.strip():
        return result
    for part in raw.split(","):
        part = part.strip()
        if not part:
            continue
        user_id, sep, name = part.partition(":")
        if not sep or not user_id.strip().isdigit() or not name.strip():
            raise ConfigError(
                "DISCORD_MEMBER_IDS 형식 오류: '유저ID:멤버명,...' 형식이어야 합니다"
            )
        result[int(user_id.strip())] = name.strip()
    return result


@dataclass(frozen=True)
class Settings:
    discord_bot_token: str
    guild_id: int
    watch_channel_id: int
    notion_token: str
    ds_schedule: str
    ds_tracker: str
    llm_provider: str
    llm_model: str
    openai_api_key: str
    openai_base_url: str
    anthropic_api_key: str
    claude_model: str
    member_ids: dict[int, str]
    db_path: Path
    log_dir: Path
    workspace_map_path: Path

    @property
    def secret_values(self) -> tuple[str, ...]:
        """로그 마스킹 대상 시크릿 4종 (SEC-I7: CLIENT_SECRET 제외)."""
        return tuple(v for v in (self.discord_bot_token, self.notion_token,
                                 self.openai_api_key, self.anthropic_api_key) if v)


def _find_env_path() -> Path | None:
    for candidate in (BASE_DIR / ".env", BASE_DIR.parent / ".env"):
        if candidate.exists():
            return candidate
    return None


def load_settings(env_path: Path | None = None,
                  env: Mapping[str, str] | None = None) -> Settings:
    """env가 None이면 .env 파일(notion-manager/.env → 저장소 루트 .env 순)을 로드한다."""
    if env is None:
        path = env_path or _find_env_path()
        if path is None:
            raise ConfigError(
                "'.env' 파일을 찾을 수 없습니다 (notion-manager/.env 또는 저장소 루트 .env)"
            )
        load_dotenv(path, encoding="utf-8")
        env = os.environ
    missing = [key for key in REQUIRED_KEYS if not env.get(key)]
    if missing:
        raise ConfigError("필수 환경변수가 없습니다: " + ", ".join(missing))
    return Settings(
        discord_bot_token=env["DISCORD_BOT_TOKEN"],
        guild_id=int(env["DISCORD_GUILD_ID"]),
        watch_channel_id=int(env["DISCORD_WATCH_CHANNEL_ID"]),
        notion_token=env["NOTION_TOKEN"],
        ds_schedule=env["NOTION_DS_SCHEDULE"],
        ds_tracker=env["NOTION_DS_TRACKER"],
        llm_provider=env.get("LLM_PROVIDER", "openai"),
        llm_model=env.get("LLM_MODEL") or "gpt-5.5",
        openai_api_key=env["OPENAI_API_KEY"],
        openai_base_url=env.get("OPENAI_BASE_URL") or "https://api.openai.com/v1",
        anthropic_api_key=env["ANTHROPIC_API_KEY"],
        claude_model=env.get("CLAUDE_MODEL") or "claude-opus-4-8",
        member_ids=parse_member_ids(env.get("DISCORD_MEMBER_IDS", "")),
        db_path=BASE_DIR / "data" / "sessions.db",
        log_dir=BASE_DIR / "logs",
        workspace_map_path=BASE_DIR / "agent" / "workspace_map.json",
    )


class SecretMaskingFilter(logging.Filter):
    """레코드 메시지의 시크릿 문자열을 '***'로 치환. root 로거의 Handler에 부착할 것.

    로거(Logger)에 부착하면 하위 named logger(discord.http 등)에서 전파되는
    레코드를 거르지 못한다 — 반드시 Handler에 부착한다 (SEC-C1).

    메시지·인자뿐 아니라 예외 트레이스백(exc_info/exc_text)과 stack_info에
    실린 시크릿도 마스킹한다. Formatter.format()은 필터 실행 '이후'에
    formatException()/formatStack() 결과를 로그 라인에 덧붙이므로, 이 경로를
    막지 않으면 logger.exception(...) / logger.error(..., exc_info=True) 로
    시크릿이 콘솔·로그 파일에 그대로 노출된다 (SEC-C1 백스톱).
    """

    def __init__(self, secrets: Iterable[str]):
        super().__init__()
        self._secrets = [s for s in secrets if s]

    def _mask(self, text: str) -> str:
        for secret in self._secrets:
            if secret in text:
                text = text.replace(secret, "***")
        return text

    def filter(self, record: logging.LogRecord) -> bool:
        record.msg = self._mask(record.getMessage())
        record.args = None

        if record.exc_info:
            # 마스킹된 텍스트를 exc_text에 캐시하고 exc_info는 비운다 — 이후
            # Formatter.format()이 원본(비마스킹) exc_info로 재포맷하지 못하게
            # 막는다. 동일 레코드가 여러 Handler를 거쳐도(각 Handler의 필터가
            # 재호출돼도) 이미 마스킹된 exc_text만 남으므로 멱등하다.
            record.exc_text = self._mask(logging.Formatter().formatException(record.exc_info))
            record.exc_info = None
        elif record.exc_text:
            record.exc_text = self._mask(record.exc_text)

        if record.stack_info:
            record.stack_info = self._mask(record.stack_info)

        return True


def setup_logging(settings: Settings) -> None:
    """콘솔 + 로테이션 파일(5MB×3, utf-8) 핸들러 구성, 둘 다 마스킹 필터 부착 (DEP-I4)."""
    settings.log_dir.mkdir(parents=True, exist_ok=True)
    root = logging.getLogger()
    for handler in list(root.handlers):
        root.removeHandler(handler)
    masking = SecretMaskingFilter(settings.secret_values)
    console = logging.StreamHandler(sys.stdout)
    file_handler = logging.handlers.RotatingFileHandler(
        settings.log_dir / "notion_manager.log",
        maxBytes=5 * 1024 * 1024,
        backupCount=3,
        encoding="utf-8",
    )
    formatter = logging.Formatter("%(asctime)s %(levelname)s %(name)s %(message)s")
    for handler in (console, file_handler):
        handler.setFormatter(formatter)
        handler.addFilter(masking)
        root.addHandler(handler)
    root.setLevel(logging.INFO)
