from __future__ import annotations

import re
import sqlite3
import time
from pathlib import Path
from typing import Iterable

from .config import get_settings


BAD_TEXT = re.compile(r"\ufffd+")


def clean_text(value: str | None) -> str:
    return re.sub(r"\s+", " ", BAD_TEXT.sub(" ", value or "")).strip()


class CompetitionRepository:
    def __init__(self, path: Path | None = None) -> None:
        self.path = Path(path or get_settings().competition_db_path)

    def _connect(self) -> sqlite3.Connection:
        con = sqlite3.connect(f"file:{self.path.as_posix()}?mode=ro", uri=True)
        con.row_factory = sqlite3.Row
        return con

    @staticmethod
    def _eligible_where() -> tuple[str, tuple[int, int]]:
        now = int(time.time())
        return (
            "is_active=1 AND ((can_register=1 AND (register_end_at IS NULL OR register_end_at>=?)) "
            "OR contest_start_at>=?)",
            (now, now),
        )

    def eligible_ids(self) -> set[int]:
        where, params = self._eligible_where()
        with self._connect() as con:
            return {row[0] for row in con.execute(f"SELECT contest_id FROM competitions WHERE {where}", params)}

    def list_for_index(self) -> list[dict]:
        where, params = self._eligible_where()
        with self._connect() as con:
            rows = con.execute(
                f"""
                SELECT contest_id, contest_name, level_name, category_second_code,
                       register_end_at, contest_start_at, source_url, content_text
                FROM competitions WHERE {where}
                """,
                params,
            ).fetchall()
        return [self._index_row(row) for row in rows]

    def get_many(self, ids: Iterable[int]) -> list[dict]:
        wanted = list(dict.fromkeys(int(item) for item in ids))
        if not wanted:
            return []
        marks = ",".join("?" for _ in wanted)
        with self._connect() as con:
            rows = con.execute(
                f"""
                SELECT contest_id, contest_name, level_name, status_name,
                       category_second_code AS category, register_end_at,
                       contest_start_at, contest_end_at, source_url, content_text
                FROM competitions WHERE contest_id IN ({marks})
                """,
                wanted,
            ).fetchall()
        by_id = {row["contest_id"]: self._public_row(row) for row in rows}
        return [by_id[item] for item in wanted if item in by_id]

    def keyword_candidates(self, query: str, limit: int = 20) -> list[int]:
        terms = [term for term in re.findall(r"[\w\u4e00-\u9fff]+", query.lower()) if len(term) >= 2][:12]
        rows = self.list_for_index()
        scored: list[tuple[int, int]] = []
        for row in rows:
            haystack = row["embedding_text"].lower()
            score = sum((3 if term in row["contest_name"].lower() else 1) for term in terms if term in haystack)
            if score:
                scored.append((score, row["contest_id"]))
        scored.sort(reverse=True)
        selected = [contest_id for _, contest_id in scored[:limit]]
        if len(selected) < limit:
            selected.extend(row["contest_id"] for row in rows if row["contest_id"] not in selected)
        return selected[:limit]

    @staticmethod
    def _index_row(row: sqlite3.Row) -> dict:
        title = clean_text(row["contest_name"])
        content = clean_text(row["content_text"])[:2600]
        parts = [title, clean_text(row["level_name"]), clean_text(row["category_second_code"]), content]
        return {
            "contest_id": row["contest_id"],
            "contest_name": title,
            "register_end_at": row["register_end_at"],
            "contest_start_at": row["contest_start_at"],
            "source_url": row["source_url"],
            "embedding_text": "\n".join(part for part in parts if part),
        }

    @staticmethod
    def _public_row(row: sqlite3.Row) -> dict:
        content = clean_text(row["content_text"])
        return {
            "contest_id": row["contest_id"],
            "contest_name": clean_text(row["contest_name"]),
            "level_name": clean_text(row["level_name"]) or None,
            "status_name": clean_text(row["status_name"]) or None,
            "category": clean_text(row["category"]) or None,
            "register_end_at": row["register_end_at"],
            "contest_start_at": row["contest_start_at"],
            "contest_end_at": row["contest_end_at"],
            "source_url": row["source_url"],
            "content_excerpt": content[:1800],
        }

