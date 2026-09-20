from __future__ import annotations

import argparse
import asyncio
import hashlib
import html
import json
import math
import mimetypes
import random
import re
import sqlite3
import sys
import time
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from html.parser import HTMLParser
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

import aiohttp


API_BASE = "https://apiv4buffer.saikr.com"
SITE_BASE = "https://www.saikr.com"
LIST_ENDPOINT = f"{API_BASE}/api/pc/contest/lists"
DETAIL_ENDPOINT = f"{API_BASE}/api/pc/contest/info"
CHINA_TZ = timezone(timedelta(hours=8), name="Asia/Shanghai")

DEFAULT_HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140 Safari/537.36"
    ),
    "Accept": "application/json, text/plain, */*",
    "Origin": SITE_BASE,
    "Referer": f"{SITE_BASE}/contests",
}


class TextExtractor(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.parts: list[str] = []

    def handle_data(self, data: str) -> None:
        text = data.strip()
        if text:
            self.parts.append(text)

    def get_text(self) -> str:
        return re.sub(r"\s+", " ", " ".join(self.parts)).strip()


def html_to_text(value: str | None) -> str:
    if not value:
        return ""
    parser = TextExtractor()
    parser.feed(value)
    return html.unescape(parser.get_text())


def now_ts() -> int:
    return int(time.time())


def nullable_int(value: Any) -> int | None:
    if value in (None, ""):
        return None
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def parse_local_time(value: Any) -> int | None:
    if value in (None, "", 0, "0"):
        return None
    if isinstance(value, (int, float)):
        return int(value)
    raw = str(value).strip()
    for fmt in (
        "%Y/%m/%d %H:%M:%S",
        "%Y.%m.%d %H:%M:%S",
        "%Y-%m-%d %H:%M:%S",
        "%Y/%m/%d",
        "%Y.%m.%d",
        "%Y-%m-%d",
    ):
        try:
            return int(datetime.strptime(raw, fmt).replace(tzinfo=CHINA_TZ).timestamp())
        except ValueError:
            pass
    return None


def source_url(contest_url: str) -> str:
    return f"{SITE_BASE}/{contest_url.lstrip('/')}"


def json_text(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"))


def detail_content_hash(content: str) -> str:
    return hashlib.sha256(content.encode("utf-8")).hexdigest()


def connect_db(db_path: Path, schema_path: Path) -> sqlite3.Connection:
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    conn.executescript(schema_path.read_text(encoding="utf-8"))
    return conn


@dataclass
class PageResult:
    page: int
    seen: int
    inserted: int
    updated: int
    details: int
    errors: int


class SaikrCrawler:
    def __init__(
        self,
        conn: sqlite3.Connection,
        *,
        page_size: int,
        page_delay: float,
        detail_concurrency: int,
        request_timeout: float,
        retries: int,
        sort: int,
    ) -> None:
        self.conn = conn
        self.page_size = page_size
        self.page_delay = page_delay
        self.detail_concurrency = detail_concurrency
        self.request_timeout = request_timeout
        self.retries = retries
        self.sort = sort
        self.detail_semaphore = asyncio.Semaphore(detail_concurrency)

    async def fetch_json(
        self,
        session: aiohttp.ClientSession,
        url: str,
        *,
        params: dict[str, Any],
        referer: str,
    ) -> dict[str, Any]:
        headers = {"Referer": referer}
        last_error: Exception | None = None
        for attempt in range(1, self.retries + 1):
            try:
                async with session.get(url, params=params, headers=headers) as response:
                    if response.status == 429 or response.status >= 500:
                        body = (await response.text())[:300]
                        raise RuntimeError(f"HTTP {response.status}: {body}")
                    response.raise_for_status()
                    payload = await response.json(content_type=None)
                    if payload.get("code") != 200:
                        raise RuntimeError(
                            f"API code={payload.get('code')}: {payload.get('msg', '')}"
                        )
                    data = payload.get("data")
                    if not isinstance(data, dict):
                        raise RuntimeError("API data 不是对象")
                    return data
            except (aiohttp.ClientError, asyncio.TimeoutError, RuntimeError) as exc:
                last_error = exc
                if attempt >= self.retries:
                    break
                delay = min(30.0, (2 ** (attempt - 1)) + random.random())
                print(f"  请求失败，第 {attempt} 次重试，等待 {delay:.1f}s：{exc}")
                await asyncio.sleep(delay)
        raise RuntimeError(f"请求最终失败：{last_error}")

    async def fetch_list(
        self, session: aiohttp.ClientSession, page: int
    ) -> dict[str, Any]:
        return await self.fetch_json(
            session,
            LIST_ENDPOINT,
            params={
                "page": page,
                "limit": self.page_size,
                "univs_id": "",
                "class_id": "",
                "level": 0,
                "sort": self.sort,
            },
            referer=f"{SITE_BASE}/contests",
        )

    async def fetch_detail(
        self, session: aiohttp.ClientSession, item: dict[str, Any]
    ) -> tuple[int, dict[str, Any] | None, str | None]:
        contest_id = int(item["contest_id"])
        contest_url = str(item.get("contest_url") or "")
        async with self.detail_semaphore:
            try:
                data = await self.fetch_json(
                    session,
                    DETAIL_ENDPOINT,
                    params={"contest_id": contest_id, "isp": 0},
                    referer=source_url(contest_url),
                )
                return contest_id, data, None
            except Exception as exc:  # 单条失败不阻断整页
                return contest_id, None, str(exc)

    def competition_exists(self, contest_id: int) -> bool:
        row = self.conn.execute(
            "SELECT 1 FROM competitions WHERE contest_id = ?", (contest_id,)
        ).fetchone()
        return row is not None

    def upsert_competition(
        self,
        item: dict[str, Any],
        detail: dict[str, Any] | None,
        fetched_at: int,
    ) -> tuple[bool, bool]:
        contest_id = int(item["contest_id"])
        existed = self.competition_exists(contest_id)
        detail = detail or {}
        content_html = str(detail.get("content") or "")
        config = detail.get("configInfo") or {}

        values = {
            "contest_id": contest_id,
            "contest_url": str(item.get("contest_url") or contest_id),
            "contest_name": str(
                detail.get("contest_name") or item.get("contest_name") or ""
            ),
            "level_code": nullable_int(detail.get("contest_level")),
            "level_name": item.get("level_name"),
            "category_first_id": nullable_int(
                detail.get("contest_class_first", item.get("contest_class_first"))
            ),
            "category_second_id": nullable_int(item.get("contest_class_second_id")),
            "category_second_code": detail.get(
                "contest_class_second", item.get("contest_class_second")
            ),
            "status_code": nullable_int(
                detail.get("is_contest_status", item.get("is_contest_status"))
            ),
            "status_name": item.get("time_name"),
            "is_exam": nullable_int(detail.get("is_exam", item.get("is_exam"))) or 0,
            "can_register": nullable_int(detail.get("can_register")),
            "enter_type": nullable_int(detail.get("enter_type")),
            "team_type": nullable_int(config.get("team_type")),
            "register_start_at": parse_local_time(
                item.get("regist_start_time") or detail.get("regist_start_time")
            ),
            "register_end_at": parse_local_time(
                item.get("regist_end_time") or detail.get("regist_end_time")
            ),
            "contest_start_at": parse_local_time(
                item.get("contest_start_time") or detail.get("contest_start_time")
            ),
            "contest_end_at": parse_local_time(
                item.get("contest_end_time") or detail.get("contest_end_time")
            ),
            "cover_url": item.get("thumb_pic"),
            "banner_url": detail.get("web_pic_big"),
            "source_url": source_url(str(item.get("contest_url") or contest_id)),
            "content_html": content_html or None,
            "content_text": html_to_text(content_html) or None,
            "content_hash": detail_content_hash(content_html) if content_html else None,
            "view_count": nullable_int(detail.get("look_count")),
            "follow_count": nullable_int(detail.get("focus_num")),
            "rank_number": nullable_int(item.get("rank")),
            "is_new": nullable_int(item.get("is_new")) or 0,
            "raw_json": json_text({"list": item, "detail": detail}) if detail else None,
            "fetched_at": fetched_at,
            "detail_fetched_at": fetched_at if detail else None,
        }

        before = self.conn.execute(
            """
            SELECT contest_name, status_code, register_end_at, contest_start_at,
                   content_hash
            FROM competitions WHERE contest_id = ?
            """,
            (contest_id,),
        ).fetchone()

        self.conn.execute(
            """
            INSERT INTO competitions (
                contest_id, contest_url, contest_name, level_code, level_name,
                category_first_id, category_second_id, category_second_code,
                status_code, status_name, is_exam, can_register, enter_type, team_type,
                register_start_at, register_end_at, contest_start_at, contest_end_at,
                cover_url, banner_url, source_url, content_html, content_text,
                content_hash, view_count, follow_count, rank_number, is_new, raw_json,
                first_seen_at, last_seen_at, detail_fetched_at, updated_at, is_active
            ) VALUES (
                :contest_id, :contest_url, :contest_name, :level_code, :level_name,
                :category_first_id, :category_second_id, :category_second_code,
                :status_code, :status_name, :is_exam, :can_register, :enter_type, :team_type,
                :register_start_at, :register_end_at, :contest_start_at, :contest_end_at,
                :cover_url, :banner_url, :source_url, :content_html, :content_text,
                :content_hash, :view_count, :follow_count, :rank_number, :is_new, :raw_json,
                :fetched_at, :fetched_at, :detail_fetched_at, :fetched_at, 1
            )
            ON CONFLICT(contest_id) DO UPDATE SET
                contest_url = excluded.contest_url,
                contest_name = excluded.contest_name,
                level_code = COALESCE(excluded.level_code, competitions.level_code),
                level_name = COALESCE(excluded.level_name, competitions.level_name),
                category_first_id = COALESCE(excluded.category_first_id, competitions.category_first_id),
                category_second_id = COALESCE(excluded.category_second_id, competitions.category_second_id),
                category_second_code = COALESCE(excluded.category_second_code, competitions.category_second_code),
                status_code = COALESCE(excluded.status_code, competitions.status_code),
                status_name = COALESCE(excluded.status_name, competitions.status_name),
                is_exam = excluded.is_exam,
                can_register = COALESCE(excluded.can_register, competitions.can_register),
                enter_type = COALESCE(excluded.enter_type, competitions.enter_type),
                team_type = COALESCE(excluded.team_type, competitions.team_type),
                register_start_at = COALESCE(excluded.register_start_at, competitions.register_start_at),
                register_end_at = COALESCE(excluded.register_end_at, competitions.register_end_at),
                contest_start_at = COALESCE(excluded.contest_start_at, competitions.contest_start_at),
                contest_end_at = COALESCE(excluded.contest_end_at, competitions.contest_end_at),
                cover_url = COALESCE(excluded.cover_url, competitions.cover_url),
                banner_url = COALESCE(excluded.banner_url, competitions.banner_url),
                source_url = excluded.source_url,
                content_html = COALESCE(excluded.content_html, competitions.content_html),
                content_text = COALESCE(excluded.content_text, competitions.content_text),
                content_hash = COALESCE(excluded.content_hash, competitions.content_hash),
                view_count = COALESCE(excluded.view_count, competitions.view_count),
                follow_count = COALESCE(excluded.follow_count, competitions.follow_count),
                rank_number = COALESCE(excluded.rank_number, competitions.rank_number),
                is_new = excluded.is_new,
                raw_json = COALESCE(excluded.raw_json, competitions.raw_json),
                last_seen_at = excluded.last_seen_at,
                detail_fetched_at = COALESCE(excluded.detail_fetched_at, competitions.detail_fetched_at),
                updated_at = excluded.updated_at,
                is_active = 1,
                removed_at = NULL
            """,
            values,
        )

        changed = not existed
        if before is not None:
            new_signature = (
                values["contest_name"],
                values["status_code"],
                values["register_end_at"],
                values["contest_start_at"],
                values["content_hash"] or before["content_hash"],
            )
            old_signature = tuple(before)
            changed = new_signature != old_signature

        if detail:
            self.replace_detail_children(contest_id, detail, fetched_at)
        return not existed, existed and changed

    def replace_detail_children(
        self, contest_id: int, detail: dict[str, Any], fetched_at: int
    ) -> None:
        self.conn.execute(
            "DELETE FROM competition_stages WHERE contest_id = ?", (contest_id,)
        )
        stages = (detail.get("contest_stage") or {}).get("list") or []
        for index, stage in enumerate(stages, start=1):
            self.conn.execute(
                """
                INSERT INTO competition_stages (
                    contest_id, stage_order, stage_name, stage_content, start_at, end_at
                ) VALUES (?, ?, ?, ?, ?, ?)
                """,
                (
                    contest_id,
                    index,
                    stage.get("name"),
                    stage.get("content"),
                    parse_local_time(stage.get("start_time")),
                    parse_local_time(stage.get("end_time")),
                ),
            )

        self.conn.execute(
            "DELETE FROM competition_attachments WHERE contest_id = ?", (contest_id,)
        )
        attachments = detail.get("attachment") or {}
        if isinstance(attachments, dict):
            for name, url in attachments.items():
                if not url:
                    continue
                file_type = mimetypes.guess_type(urlparse(str(url)).path)[0]
                self.conn.execute(
                    """
                    INSERT INTO competition_attachments (
                        contest_id, file_name, file_url, file_type, discovered_at
                    ) VALUES (?, ?, ?, ?, ?)
                    """,
                    (contest_id, str(name), str(url), file_type, fetched_at),
                )

        self.conn.execute(
            "DELETE FROM competition_organizers WHERE contest_id = ?", (contest_id,)
        )
        organizer_rows: list[tuple[str, str, int | None, str | None, str | None]] = []

        for value in detail.get("organiser") or []:
            name = value.get("organizer") if isinstance(value, dict) else value
            if name:
                organizer_rows.append(("main", str(name), None, None, None))

        for value in detail.get("other_organiser") or []:
            name = value.get("organizer") if isinstance(value, dict) else value
            if name:
                organizer_rows.append(("other", str(name), None, None, None))

        for value in detail.get("sup_organizer") or []:
            if not isinstance(value, dict) or not value.get("organizer"):
                continue
            organizer_rows.append(
                (
                    "support",
                    str(value["organizer"]),
                    nullable_int(value.get("id")),
                    value.get("link_url"),
                    None,
                )
            )

        seen: set[tuple[str, str]] = set()
        for order, (role, name, source_id, link_url, avatar_url) in enumerate(
            organizer_rows, start=1
        ):
            key = (role, name)
            if key in seen:
                continue
            seen.add(key)
            self.conn.execute(
                """
                INSERT INTO organizers (
                    source_organizer_id, organizer_name, link_url, avatar_url
                ) VALUES (?, ?, ?, ?)
                ON CONFLICT(organizer_name) DO UPDATE SET
                    source_organizer_id = COALESCE(excluded.source_organizer_id, organizers.source_organizer_id),
                    link_url = COALESCE(excluded.link_url, organizers.link_url),
                    avatar_url = COALESCE(excluded.avatar_url, organizers.avatar_url)
                """,
                (source_id, name, link_url, avatar_url),
            )
            organizer_id = self.conn.execute(
                "SELECT id FROM organizers WHERE organizer_name = ?", (name,)
            ).fetchone()[0]
            self.conn.execute(
                """
                INSERT INTO competition_organizers (
                    contest_id, organizer_id, role, sort_order
                ) VALUES (?, ?, ?, ?)
                """,
                (contest_id, organizer_id, role, order),
            )

    async def process_page(
        self,
        session: aiohttp.ClientSession,
        page: int,
        run_id: int,
    ) -> tuple[PageResult, int]:
        data = await self.fetch_list(session, page)
        items = data.get("list") or []
        total = int(data.get("total") or 0)
        total_pages = math.ceil(total / self.page_size) if total else page
        print(f"第 {page}/{total_pages} 页：列表 {len(items)} 条，总计 {total} 条")

        tasks = [self.fetch_detail(session, item) for item in items]
        detail_results = await asyncio.gather(*tasks)
        detail_map = {contest_id: detail for contest_id, detail, _ in detail_results}
        errors = [
            (contest_id, error)
            for contest_id, _, error in detail_results
            if error is not None
        ]
        for contest_id, error in errors:
            print(f"  详情失败 contest_id={contest_id}: {error}")

        fetched_at = now_ts()
        inserted = updated = details = 0
        with self.conn:
            for item in items:
                contest_id = int(item["contest_id"])
                detail = detail_map.get(contest_id)
                was_inserted, was_updated = self.upsert_competition(
                    item, detail, fetched_at
                )
                inserted += int(was_inserted)
                updated += int(was_updated)
                details += int(detail is not None)

            self.conn.execute(
                """
                UPDATE crawl_runs SET
                    current_page = ?, total_pages = ?, pages_fetched = pages_fetched + 1,
                    items_seen = items_seen + ?, items_inserted = items_inserted + ?,
                    items_updated = items_updated + ?, details_fetched = details_fetched + ?,
                    error_count = error_count + ?
                WHERE id = ?
                """,
                (
                    page,
                    total_pages,
                    len(items),
                    inserted,
                    updated,
                    details,
                    len(errors),
                    run_id,
                ),
            )

        print(
            f"  已落库：新增 {inserted}，更新 {updated}，详情 {details}，失败 {len(errors)}"
        )
        return (
            PageResult(page, len(items), inserted, updated, details, len(errors)),
            total_pages,
        )

    async def run(
        self,
        *,
        start_page: int,
        max_pages: int | None,
    ) -> None:
        run_started = now_ts()
        cursor = self.conn.execute(
            "INSERT INTO crawl_runs (started_at, status, start_page) VALUES (?, 'running', ?)",
            (run_started, start_page),
        )
        self.conn.commit()
        run_id = int(cursor.lastrowid)

        timeout = aiohttp.ClientTimeout(total=self.request_timeout)
        connector = aiohttp.TCPConnector(limit=max(4, self.detail_concurrency + 1))
        page = start_page
        processed = 0
        final_status = "success"
        final_error: str | None = None

        try:
            async with aiohttp.ClientSession(
                timeout=timeout,
                connector=connector,
                headers=DEFAULT_HEADERS,
            ) as session:
                total_pages: int | None = None
                while total_pages is None or page <= total_pages:
                    if max_pages is not None and processed >= max_pages:
                        break
                    result, total_pages = await self.process_page(session, page, run_id)
                    processed += 1
                    if result.seen == 0:
                        break
                    page += 1
                    if page <= total_pages and (
                        max_pages is None or processed < max_pages
                    ):
                        print(f"  等待 {self.page_delay:g} 秒后进入下一页……")
                        await asyncio.sleep(self.page_delay)
        except KeyboardInterrupt:
            final_status = "partial"
            final_error = "用户中断"
            raise
        except Exception as exc:
            final_status = "failed"
            final_error = str(exc)
            raise
        finally:
            with self.conn:
                self.conn.execute(
                    """
                    UPDATE crawl_runs
                    SET finished_at = ?, status = ?, error_message = ?
                    WHERE id = ?
                    """,
                    (now_ts(), final_status, final_error, run_id),
                )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="抓取赛氪比赛广场列表及比赛详情并保存到 SQLite。"
    )
    parser.add_argument("--db", default="saikr_competitions.db", help="SQLite 文件路径")
    parser.add_argument("--start-page", type=int, default=1, help="开始页码")
    parser.add_argument("--max-pages", type=int, help="最多抓多少页；默认抓到最后")
    parser.add_argument("--page-size", type=int, default=10, help="每页条数")
    parser.add_argument("--page-delay", type=float, default=10, help="翻页等待秒数")
    parser.add_argument(
        "--detail-concurrency", type=int, default=3, help="详情请求并发数"
    )
    parser.add_argument("--timeout", type=float, default=30, help="单次请求超时秒数")
    parser.add_argument("--retries", type=int, default=3, help="请求最大尝试次数")
    parser.add_argument(
        "--sort",
        type=int,
        choices=(0, 1, 2, 3),
        default=0,
        help="排序：0报名时间，1开赛时间，2最近更新，3最多浏览",
    )
    parser.add_argument(
        "--init-only", action="store_true", help="只创建数据库表，不开始抓取"
    )
    return parser


def validate_args(args: argparse.Namespace) -> None:
    if args.start_page < 1:
        raise SystemExit("--start-page 必须大于等于 1")
    if args.max_pages is not None and args.max_pages < 1:
        raise SystemExit("--max-pages 必须大于等于 1")
    if args.page_size < 1 or args.page_size > 100:
        raise SystemExit("--page-size 必须在 1 到 100 之间")
    if args.page_delay < 10:
        raise SystemExit("为控制访问频率，--page-delay 不能小于 10 秒")
    if args.detail_concurrency < 1 or args.detail_concurrency > 5:
        raise SystemExit("--detail-concurrency 必须在 1 到 5 之间")


def main() -> int:
    args = build_parser().parse_args()
    validate_args(args)
    root = Path(__file__).resolve().parent
    db_path = Path(args.db).resolve()
    schema_path = root / "schema.sql"
    conn = connect_db(db_path, schema_path)
    print(f"数据库已就绪：{db_path}")

    if args.init_only:
        conn.close()
        return 0

    crawler = SaikrCrawler(
        conn,
        page_size=args.page_size,
        page_delay=args.page_delay,
        detail_concurrency=args.detail_concurrency,
        request_timeout=args.timeout,
        retries=args.retries,
        sort=args.sort,
    )
    try:
        asyncio.run(
            crawler.run(start_page=args.start_page, max_pages=args.max_pages)
        )
    except KeyboardInterrupt:
        print("\n任务已中断，已抓取的数据仍然保留。", file=sys.stderr)
        return 130
    except Exception as exc:
        print(f"任务失败：{exc}", file=sys.stderr)
        return 1
    finally:
        conn.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
