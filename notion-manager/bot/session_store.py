"""스레드↔세션 매핑 + 프로바이더 중립 히스토리 저장 (스펙 §2.2).

- 증분 커밋(BE-C1): append_message가 곧 커밋 단위. 호출 즉시 디스크에 반영된다.
- 교환 단위 절단(BE-C2): load_history는 trim_to_exchanges를 거쳐
  항상 plain user 메시지로 시작하는 히스토리를 반환한다.
"""
from __future__ import annotations

import json
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path

import aiosqlite

_DDL = """
CREATE TABLE IF NOT EXISTS sessions (
    thread_id   INTEGER PRIMARY KEY,
    channel_id  INTEGER NOT NULL,
    guild_id    INTEGER NOT NULL,
    created_by  INTEGER NOT NULL,
    provider    TEXT    NOT NULL DEFAULT 'openai',
    model       TEXT    NOT NULL,
    status      TEXT    NOT NULL DEFAULT 'active',
    created_at  TEXT    NOT NULL,
    updated_at  TEXT    NOT NULL
);
CREATE TABLE IF NOT EXISTS messages (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    thread_id   INTEGER NOT NULL REFERENCES sessions(thread_id) ON DELETE CASCADE,
    role        TEXT    NOT NULL,
    content     TEXT    NOT NULL,
    author_id   INTEGER,
    created_at  TEXT    NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_messages_thread ON messages(thread_id, id);
"""

_RAW_FETCH_LIMIT = 200  # 절단 전 원본 조회 상한 (40개 교환 경계 탐색에 충분)


def _now() -> str:
    return datetime.now(UTC).isoformat()


@dataclass
class Session:
    thread_id: int
    channel_id: int
    guild_id: int
    created_by: int
    provider: str
    model: str
    status: str
    created_at: str
    updated_at: str


def trim_to_exchanges(msgs: list[dict], max_messages: int = 40) -> list[dict]:
    """가장 오래된 '교환'(plain user로 시작하는 블록)부터 통째로 제거 (BE-C2).

    불변식: 반환 리스트의 첫 메시지는 항상 role=='user'.
    마지막 교환 하나가 max_messages를 넘더라도 교환을 쪼개지 않는다(불변식 우선).
    """
    if len(msgs) <= max_messages:
        return msgs
    starts = [i for i, m in enumerate(msgs) if m.get("role") == "user"]
    if not starts:
        return msgs[-max_messages:]
    for start in starts:
        if len(msgs) - start <= max_messages:
            return msgs[start:]
    return msgs[starts[-1]:]


class SessionStore:
    def __init__(self, db: aiosqlite.Connection):
        self._db = db

    @classmethod
    async def open(cls, db_path: Path) -> SessionStore:
        db_path.parent.mkdir(parents=True, exist_ok=True)
        db = await aiosqlite.connect(db_path)
        db.row_factory = aiosqlite.Row
        await db.execute("PRAGMA journal_mode=WAL")
        await db.execute("PRAGMA user_version=1")
        await db.executescript(_DDL)
        await db.commit()
        return cls(db)

    async def close(self) -> None:
        await self._db.close()

    async def get_session(self, thread_id: int) -> Session | None:
        cursor = await self._db.execute(
            "SELECT * FROM sessions WHERE thread_id = ?", (thread_id,))
        row = await cursor.fetchone()
        return Session(**dict(row)) if row else None

    async def create_session(self, thread_id: int, channel_id: int, guild_id: int,
                             created_by: int, *, provider: str, model: str) -> Session:
        now = _now()
        await self._db.execute(
            "INSERT INTO sessions (thread_id, channel_id, guild_id, created_by,"
            " provider, model, status, created_at, updated_at)"
            " VALUES (?, ?, ?, ?, ?, ?, 'active', ?, ?)",
            (thread_id, channel_id, guild_id, created_by, provider, model, now, now))
        await self._db.commit()
        session = await self.get_session(thread_id)
        assert session is not None
        return session

    async def update_session(self, thread_id: int, *, provider: str | None = None,
                             model: str | None = None,
                             status: str | None = None) -> None:
        fields, values = ["updated_at = ?"], [_now()]
        if provider is not None:
            fields.append("provider = ?")
            values.append(provider)
        if model is not None:
            fields.append("model = ?")
            values.append(model)
        if status is not None:
            fields.append("status = ?")
            values.append(status)
        values.append(thread_id)
        await self._db.execute(
            f"UPDATE sessions SET {', '.join(fields)} WHERE thread_id = ?",
            values)
        await self._db.commit()

    async def append_message(self, thread_id: int, msg: dict,
                             author_id: int | None = None) -> None:
        """중립 메시지 1건을 즉시 커밋한다 (BE-C1 증분 커밋 단위)."""
        await self._db.execute(
            "INSERT INTO messages (thread_id, role, content, author_id, created_at)"
            " VALUES (?, ?, ?, ?, ?)",
            (thread_id, msg["role"], json.dumps(msg, ensure_ascii=False),
             author_id, _now()))
        await self._db.commit()

    async def load_history(self, thread_id: int,
                           max_messages: int = 40) -> list[dict]:
        cursor = await self._db.execute(
            "SELECT content FROM messages WHERE thread_id = ?"
            " ORDER BY id DESC LIMIT ?",
            (thread_id, _RAW_FETCH_LIMIT))
        rows = await cursor.fetchall()
        msgs = [json.loads(row["content"]) for row in reversed(rows)]
        return trim_to_exchanges(msgs, max_messages=max_messages)
