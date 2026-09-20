import asyncio
from pathlib import Path

from saikr_crawler import PageResult, SaikrCrawler, connect_db


SCHEMA = Path(__file__).resolve().parents[2] / "schema.sql"


class FakeCrawler(SaikrCrawler):
    def __init__(self, connection, pages):
        super().__init__(
            connection,
            page_size=10,
            page_delay=0,
            detail_concurrency=1,
            request_timeout=1,
            retries=1,
            sort=2,
        )
        self.pages = pages

    async def process_page(self, session, page, run_id):
        result, total = self.pages[page - 1]
        return result, total


def page(number, *, inserted=0, updated=0, seen=10, total=100):
    changed = list(range(number * 100, number * 100 + inserted + updated))
    return PageResult(number, seen, inserted, updated, seen, 0, changed), total


def insert_old_competition(connection, contest_id):
    connection.execute(
        """
        INSERT INTO competitions (
            contest_id, contest_url, contest_name, source_url,
            first_seen_at, last_seen_at, updated_at, is_active
        ) VALUES (?, ?, ?, ?, 1, 1, 1, 1)
        """,
        (contest_id, str(contest_id), f"旧赛事 {contest_id}", f"https://example.com/{contest_id}"),
    )
    connection.commit()


def test_incremental_stops_after_three_unchanged_pages(tmp_path):
    connection = connect_db(tmp_path / "incremental.db", SCHEMA)
    crawler = FakeCrawler(
        connection,
        [
            page(1, inserted=1),
            page(2),
            page(3),
            page(4),
            page(5, inserted=1),
        ],
    )
    summary = asyncio.run(
        crawler.run(start_page=1, max_pages=50, stop_after_unchanged_pages=3)
    )
    connection.close()
    assert summary.pages_fetched == 4
    assert summary.items_inserted == 1
    assert summary.stopped_reason == "unchanged_pages"


def test_only_complete_full_crawl_marks_missing_rows_inactive(tmp_path):
    full_connection = connect_db(tmp_path / "full.db", SCHEMA)
    insert_old_competition(full_connection, 1)
    full = FakeCrawler(full_connection, [page(1, seen=10, total=1)])
    summary = asyncio.run(full.run(start_page=1, max_pages=None))
    active = full_connection.execute(
        "SELECT is_active, removed_at FROM competitions WHERE contest_id=1"
    ).fetchone()
    full_connection.close()
    assert summary.inactivated == 1
    assert active[0] == 0 and active[1] is not None

    partial_connection = connect_db(tmp_path / "partial.db", SCHEMA)
    insert_old_competition(partial_connection, 2)
    partial = FakeCrawler(partial_connection, [page(1, seen=10, total=2)])
    summary = asyncio.run(partial.run(start_page=1, max_pages=1))
    active = partial_connection.execute(
        "SELECT is_active, removed_at FROM competitions WHERE contest_id=2"
    ).fetchone()
    partial_connection.close()
    assert summary.inactivated == 0
    assert active[0] == 1 and active[1] is None


def test_missing_optional_fields_do_not_create_false_update(tmp_path):
    connection = connect_db(tmp_path / "coalesce.db", SCHEMA)
    crawler = SaikrCrawler(
        connection,
        page_size=10,
        page_delay=0,
        detail_concurrency=1,
        request_timeout=1,
        retries=1,
        sort=2,
    )
    original = {
        "contest_id": 42,
        "contest_url": "test-42",
        "contest_name": "测试赛事",
        "is_contest_status": 1,
        "regist_end_time": "2026-12-01 12:00:00",
        "contest_start_time": "2026-12-10 09:00:00",
    }
    detail = {"can_register": 1, "content": "<p>赛事介绍</p>"}
    assert crawler.upsert_competition(original, detail, 100) == (True, False)
    connection.commit()

    sparse = {
        "contest_id": 42,
        "contest_url": "test-42",
        "contest_name": "测试赛事",
    }
    assert crawler.upsert_competition(sparse, None, 200) == (False, False)
    connection.close()
