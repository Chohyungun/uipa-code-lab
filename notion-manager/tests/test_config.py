from __future__ import annotations

import dataclasses
import logging
import sys

import pytest

from config import (
    BASE_DIR,
    ConfigError,
    SecretMaskingFilter,
    Settings,
    load_settings,
    parse_member_ids,
    setup_logging,
)

FULL_ENV = {
    "DISCORD_BOT_TOKEN": "test-bot-token",
    "DISCORD_GUILD_ID": "999",
    "DISCORD_WATCH_CHANNEL_ID": "777",
    "NOTION_TOKEN": "test-notion-token",
    "NOTION_DS_SCHEDULE": "ds-schedule-test",
    "NOTION_DS_TRACKER": "ds-tracker-test",
    "OPENAI_API_KEY": "test-openai-key",
    "ANTHROPIC_API_KEY": "test-anthropic-key",
}


def test_load_settings_ok():
    s = load_settings(env=FULL_ENV)
    assert s.guild_id == 999
    assert s.watch_channel_id == 777
    assert s.llm_provider == "openai"
    assert s.llm_model == "gpt-5.5"
    assert s.claude_model == "claude-opus-4-8"
    assert s.member_ids == {}


def test_missing_keys_lists_names_only():
    env = {k: v for k, v in FULL_ENV.items()
           if k not in ("NOTION_TOKEN", "OPENAI_API_KEY")}
    with pytest.raises(ConfigError) as exc_info:
        load_settings(env=env)
    msg = str(exc_info.value)
    assert "NOTION_TOKEN" in msg
    assert "OPENAI_API_KEY" in msg
    assert "test-" not in msg  # 값은 절대 노출하지 않는다


def test_client_secret_not_in_settings():
    names = {f.name for f in dataclasses.fields(Settings)}
    assert "discord_client_secret" not in names  # SEC-I7


def test_parse_member_ids():
    assert parse_member_ids("") == {}
    assert parse_member_ids("123:조현건, 456:김다영") == {123: "조현건", 456: "김다영"}
    with pytest.raises(ConfigError):
        parse_member_ids("abc:조현건")
    with pytest.raises(ConfigError):
        parse_member_ids("123")


def test_paths_anchored_not_cwd():
    s = load_settings(env=FULL_ENV)
    assert s.db_path == BASE_DIR / "data" / "sessions.db"
    assert s.log_dir == BASE_DIR / "logs"
    assert s.workspace_map_path == BASE_DIR / "agent" / "workspace_map.json"
    assert s.db_path.is_absolute()


def test_secret_values_four_kinds():
    s = load_settings(env=FULL_ENV)
    assert set(s.secret_values) == {
        "test-bot-token", "test-notion-token", "test-openai-key", "test-anthropic-key",
    }


def test_masking_filter_masks_message_and_args():
    f = SecretMaskingFilter(["test-bot-token"])
    record = logging.LogRecord("discord.http", logging.INFO, __file__, 1,
                               "Authorization: %s", ("test-bot-token",), None)
    assert f.filter(record) is True
    assert "test-bot-token" not in record.getMessage()
    assert "***" in record.getMessage()


def test_masking_filter_masks_exception_text():
    """SEC-C1 백스톱: exc_info 트레이스백 텍스트에 실린 시크릿도 마스킹해야 한다."""
    f = SecretMaskingFilter(["test-bot-token"])
    try:
        raise RuntimeError("token=test-bot-token")
    except RuntimeError:
        record = logging.LogRecord("discord.http", logging.ERROR, __file__, 1,
                                   "request failed", None, sys.exc_info())
    assert f.filter(record) is True
    assert record.exc_info is None  # 포매터가 원본 exc_info로 재계산하지 못하도록 무력화
    formatted = logging.Formatter().format(record)
    assert "test-bot-token" not in formatted
    assert "***" in formatted


def test_masking_filter_masks_stack_info():
    """SEC-C1 백스톱: stack_info에 실린 시크릿도 마스킹해야 한다."""
    f = SecretMaskingFilter(["test-bot-token"])
    record = logging.LogRecord("discord.http", logging.INFO, __file__, 1,
                               "state snapshot", None, None)
    record.stack_info = "Stack (most recent call last):\n  token=test-bot-token"
    assert f.filter(record) is True
    assert "test-bot-token" not in record.stack_info
    assert "***" in record.stack_info


@pytest.fixture
def clean_root_logger():
    root = logging.getLogger()
    saved_handlers = list(root.handlers)
    saved_level = root.level
    yield
    for h in list(root.handlers):
        h.close()
        root.removeHandler(h)
    for h in saved_handlers:
        root.addHandler(h)
    root.setLevel(saved_level)


def test_setup_logging_masks_named_logger(fake_settings, clean_root_logger):
    """SEC-C1: 필터는 Handler에 부착 — 하위 named logger 경유 레코드도 마스킹."""
    setup_logging(fake_settings)
    root = logging.getLogger()
    assert any(isinstance(f, SecretMaskingFilter)
               for h in root.handlers for f in h.filters)
    logging.getLogger("discord.http").warning("token=%s", "test-bot-token")
    for h in root.handlers:
        h.flush()
    log_file = fake_settings.log_dir / "notion_manager.log"
    content = log_file.read_text(encoding="utf-8")
    assert "test-bot-token" not in content
    assert "***" in content


def test_setup_logging_masks_exception_traceback(fake_settings, clean_root_logger):
    """SEC-C1 백스톱: logger.exception()이 남기는 트레이스백의 시크릿이 로그 파일에 새지 않는다."""
    setup_logging(fake_settings)
    try:
        raise RuntimeError("unauthorized: test-bot-token")
    except RuntimeError:
        logging.getLogger("discord.http").exception("request failed")
    for h in logging.getLogger().handlers:
        h.flush()
    log_file = fake_settings.log_dir / "notion_manager.log"
    content = log_file.read_text(encoding="utf-8")
    assert "test-bot-token" not in content
    assert "***" in content
