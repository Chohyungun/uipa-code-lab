"""공용 테스트 픽스처 — 실 Discord/Notion/OpenAI/Anthropic 객체를 절대 만들지 않는다.

fake_settings / session_store 픽스처는 지연 임포트를 쓴다: config·bot.session_store
모듈은 후속 태스크에서 생성되므로 top-level import 시 수집이 깨진다. 바꾸지 말 것.
"""
from __future__ import annotations

from pathlib import Path

import pytest

PROJECT_ROOT = Path(__file__).resolve().parents[1]


class FakeUser:
    def __init__(self, user_id: int = 111, display_name: str = "테스터", bot: bool = False):
        self.id = user_id
        self.display_name = display_name
        self.bot = bot


class FakeGuild:
    def __init__(self, guild_id: int = 999):
        self.id = guild_id


class _Typing:
    async def __aenter__(self):
        return self

    async def __aexit__(self, *exc):
        return False


class FakeThread:
    """discord.Thread 경량 스텁 — parent_id 속성이 있으면 스레드로 판정된다."""

    def __init__(self, thread_id: int = 555, parent_id: int = 777):
        self.id = thread_id
        self.parent_id = parent_id
        self.name = ""
        self.sent: list[dict] = []

    def typing(self):
        return _Typing()

    async def send(self, content, **kwargs):
        self.sent.append({"content": content, **kwargs})


class FakeChannel:
    """discord.TextChannel 경량 스텁 — parent_id 속성 없음."""

    def __init__(self, channel_id: int = 777):
        self.id = channel_id


class FakeMessage:
    def __init__(self, content: str = "", *, author=None, guild=..., channel=None,
                 mentions=(), webhook_id=None, message_id: int = 1):
        self.id = message_id
        self.content = content
        self.author = author or FakeUser()
        self.guild = FakeGuild() if guild is ... else guild
        self.channel = channel or FakeChannel()
        self.mentions = list(mentions)
        self.webhook_id = webhook_id
        self.reactions_added: list[str] = []
        self.replies: list[str] = []
        self.created_thread: FakeThread | None = None
        self.fail_create_thread: Exception | None = None

    async def add_reaction(self, emoji):
        self.reactions_added.append(emoji)

    async def reply(self, content, **kwargs):
        self.replies.append(content)

    async def create_thread(self, *, name, auto_archive_duration=None):
        if self.fail_create_thread is not None:
            raise self.fail_create_thread
        self.created_thread = FakeThread(thread_id=self.id + 1000,
                                         parent_id=self.channel.id)
        self.created_thread.name = name
        return self.created_thread


class FakeGateway:
    """agent.notion_api.NotionGateway 대역 — 호출 기록 + 준비된 응답 반환."""

    def __init__(self, ds_schedule: str = "ds-schedule-test",
                 ds_tracker: str = "ds-tracker-test"):
        self.ds_schedule = ds_schedule
        self.ds_tracker = ds_tracker
        self.calls: list[tuple] = []
        self.query_result: list[dict] = []
        self.page_result: dict = {"id": "page-1", "url": "https://www.notion.so/page-1"}
        self.retrieve_parent: str = ds_schedule
        self.raise_on: str | None = None
        self.error: Exception | None = None

    def _maybe_raise(self, op: str):
        if self.raise_on == op and self.error is not None:
            raise self.error

    async def query(self, ds_id, *, filter_=None, sorts=None, page_size=10, schema=None):
        self.calls.append(("query", ds_id, filter_, page_size))
        self._maybe_raise("query")
        return list(self.query_result)

    async def retrieve_page(self, page_id):
        self.calls.append(("retrieve", page_id))
        self._maybe_raise("retrieve")
        return {"id": page_id, "url": f"https://www.notion.so/{page_id}",
                "parent": {"type": "data_source_id",
                           "data_source_id": self.retrieve_parent}}

    async def create_page(self, ds_id, properties):
        self.calls.append(("create", ds_id, properties))
        self._maybe_raise("create")
        return dict(self.page_result)

    async def update_page(self, page_id, properties):
        self.calls.append(("update", page_id, properties))
        self._maybe_raise("update")
        return {"id": page_id, "url": f"https://www.notion.so/{page_id}"}


class FakeProvider:
    """agent.providers.LLMProvider 대역 — script 항목을 차례로 반환(예외면 raise)."""

    def __init__(self, name: str = "openai", model: str = "gpt-5.5", script=None):
        self.name = name
        self.model = model
        self.script = list(script or [])
        self.calls: list[dict] = []

    async def complete(self, *, system, messages, tools):
        self.calls.append({"system": system, "messages": list(messages), "tools": tools})
        item = self.script.pop(0)
        if isinstance(item, Exception):
            raise item
        return item


@pytest.fixture
def fake_settings(tmp_path):
    from config import Settings  # 지연 임포트 (Task 2 산출물)
    return Settings(
        discord_bot_token="test-bot-token",
        guild_id=999,
        watch_channel_id=777,
        notion_token="test-notion-token",
        ds_schedule="ds-schedule-test",
        ds_tracker="ds-tracker-test",
        llm_provider="openai",
        llm_model="gpt-5.5",
        openai_api_key="test-openai-key",
        openai_base_url="https://api.openai.com/v1",
        anthropic_api_key="test-anthropic-key",
        claude_model="claude-opus-4-8",
        member_ids={},
        db_path=tmp_path / "sessions.db",
        log_dir=tmp_path / "logs",
        workspace_map_path=PROJECT_ROOT / "agent" / "workspace_map.json",
    )


@pytest.fixture
async def session_store(tmp_path):
    from bot.session_store import SessionStore  # 지연 임포트 (Task 3 산출물)
    store = await SessionStore.open(tmp_path / "sessions.db")
    yield store
    await store.close()


@pytest.fixture
def fake_gateway():
    return FakeGateway()
