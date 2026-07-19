from __future__ import annotations

from bot.session_store import SessionStore, trim_to_exchanges


def _exchange(i: int) -> list[dict]:
    return [
        {"role": "user", "content": f"u{i}"},
        {"role": "assistant", "content": "",
         "tool_calls": [{"id": f"t{i}", "name": "query_schedule", "arguments": {}}]},
        {"role": "tool", "tool_call_id": f"t{i}", "name": "query_schedule",
         "content": "{}"},
    ]


def test_trim_noop_when_under_limit():
    msgs = _exchange(0) + _exchange(1)
    assert trim_to_exchanges(msgs, max_messages=40) == msgs


def test_trim_drops_oldest_whole_exchanges():
    msgs: list[dict] = []
    for i in range(15):  # 15교환 × 3 = 45 메시지
        msgs.extend(_exchange(i))
    out = trim_to_exchanges(msgs, max_messages=40)
    assert len(out) == 39  # 교환 2개(6개 메시지) 통째 제거
    assert out[0] == {"role": "user", "content": "u2"}  # BE-C2 불변식
    roles = [m["role"] for m in out]
    assert roles[0] == "user"
    assert "tool" not in roles[:1]  # tool 쌍이 잘리지 않음


def test_trim_keeps_oversized_last_exchange_intact():
    msgs = [{"role": "user", "content": "u0"}]
    for i in range(50):
        msgs.append({"role": "tool", "tool_call_id": f"t{i}",
                     "name": "query_schedule", "content": "{}"})
    out = trim_to_exchanges(msgs, max_messages=40)
    assert out[0]["role"] == "user"  # 개수보다 불변식 우선
    assert len(out) == 51


async def test_open_is_idempotent(tmp_path):
    store = await SessionStore.open(tmp_path / "s.db")
    await store.close()
    store2 = await SessionStore.open(tmp_path / "s.db")  # DDL 재실행에도 안전
    await store2.close()


async def test_create_and_get_roundtrip(session_store):
    created = await session_store.create_session(
        1, 10, 999, 111, provider="openai", model="gpt-5.5")
    assert created.thread_id == 1
    got = await session_store.get_session(1)
    assert got is not None
    assert (got.channel_id, got.guild_id, got.created_by) == (10, 999, 111)
    assert got.status == "active"


async def test_get_missing_returns_none(session_store):
    assert await session_store.get_session(42424242) is None


async def test_update_session_partial(session_store):
    await session_store.create_session(1, 10, 999, 111,
                                       provider="openai", model="gpt-5.5")
    await session_store.update_session(1, provider="anthropic",
                                       model="claude-opus-4-8")
    got = await session_store.get_session(1)
    assert got.provider == "anthropic"
    assert got.model == "claude-opus-4-8"
    assert got.status == "active"  # 미지정 필드 유지
    await session_store.update_session(1, status="error")
    assert (await session_store.get_session(1)).status == "error"


async def test_append_and_load_order_and_author(session_store):
    await session_store.create_session(1, 10, 999, 111,
                                       provider="openai", model="gpt-5.5")
    await session_store.append_message(1, {"role": "user", "content": "안녕"},
                                       author_id=111)  # DEP-I3
    await session_store.append_message(1, {"role": "assistant", "content": "✅ 완료"})
    history = await session_store.load_history(1)
    assert [m["role"] for m in history] == ["user", "assistant"]
    assert history[0]["content"] == "안녕"


async def test_load_history_applies_exchange_trim(session_store):
    await session_store.create_session(1, 10, 999, 111,
                                       provider="openai", model="gpt-5.5")
    for i in range(15):
        for msg in _exchange(i):
            await session_store.append_message(
                1, msg, author_id=111 if msg["role"] == "user" else None)
    history = await session_store.load_history(1, max_messages=40)
    assert len(history) == 39
    assert history[0]["role"] == "user"
