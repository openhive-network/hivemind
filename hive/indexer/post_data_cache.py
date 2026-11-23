import logging
from typing import Any

from hive.conf import SCHEMA_NAME
from hive.db.adapter import Db
from hive.indexer.db_adapter_holder import DbAdapterHolder

log = logging.getLogger(__name__)


def _sanitize_nul(val: str | None) -> str | None:
    """Replace NUL chars with spaces — PostgreSQL text columns cannot store \\x00."""
    if val is None:
        return None
    return val.replace('\x00', ' ') if '\x00' in val else val


class PostDataCache(DbAdapterHolder):
    """Provides cache for DB operations on post data table in order to speed up massive sync"""

    _data: dict[int, dict] = {}
    # The blocks each cached post had ops in, ascending, and its body at the end of each
    # of them but the last: mentions are processed block by block (process_hive_post_mentions).
    _blocks: dict[int, list[int]] = {}
    _block_bodies: dict[tuple[int, int], str] = {}

    @classmethod
    def is_cached(cls, pid: int) -> bool:
        """Check if data is cached"""
        return pid in cls._data

    @classmethod
    def add_data(cls, pid: int, post_data: dict[str, Any], is_new_post: bool, block_num: int) -> None:
        """Add the data of the post's op in block block_num to the cache; ops come in chain order."""
        if not cls.is_cached(pid):
            cls._data[pid] = post_data
            cls._data[pid]['is_new_post'] = is_new_post
            cls._blocks[pid] = [block_num]
        else:
            assert not is_new_post
            blocks = cls._blocks[pid]
            if block_num != blocks[-1]:
                cls._block_bodies[(pid, blocks[-1])] = cls._current_body(pid)
                blocks.append(block_num)
            for k, data in post_data.items():
                if data is not None:
                    cls._data[pid][k] = data

    @classmethod
    def _current_body(cls, pid: int) -> str:
        """The cached post's body as its ops so far leave it: the stored body while none has set it."""
        body: str | None = cls._data[pid]['body']
        if body is None:
            sql = f"SELECT hpd.body FROM {SCHEMA_NAME}.hive_post_data hpd WHERE hpd.id = :post_id"
            rows = cls._own_db().query_all(sql, post_id=pid)
            body = rows[0]._mapping['body'] if rows else ''
        return body or ''

    @classmethod
    def _own_db(cls) -> Db:
        if cls.db is None:
            raise RuntimeError("PostDataCache has no database connection (setup_own_db_access was not called)")
        return cls.db

    @classmethod
    def get_post_body(cls, pid):
        """Returns body of given post from collected cache or from underlying DB storage."""
        try:
            post_data = cls._data[pid]
        except KeyError:
            sql = f"""
                  SELECT hpd.body FROM {SCHEMA_NAME}.hive_post_data hpd WHERE hpd.id = :post_id;
                  """
            row = cls.db.query_row(sql, post_id=pid)
            post_data = dict(row._mapping)
        return post_data['body']

    @classmethod
    def flush(
        cls, print_query: bool = False, mentions_after_block: int = 0, batch_first_block: int | None = None
    ) -> int:
        """Flush data from cache to db, and process the mentions of the blocks after mentions_after_block.

        Commits the post data of the in-flight massive batch starting at batch_first_block with
        its marker (_batch_queue.post_data_applied), so that a replay of the batch does not apply
        it again.
        """
        if not cls._data:
            return 0

        insert_items = []
        update_items = []
        for k, data in cls._data.items():
            item = (
                k,
                data['is_root'],
                _sanitize_nul(data['title']),
                _sanitize_nul(data['body']),
                _sanitize_nul(data['json']),
            )
            if data['is_new_post']:
                insert_items.append(item)
            else:
                update_items.append(item)

        cls.beginTx()

        insert_ph = (
            ','.join(['(%s, %s, %s, %s, %s)'] * len(insert_items))
            if insert_items
            else '(NULL::int,NULL::bool,NULL::text,NULL::text,NULL::text)'
        )
        update_ph = (
            ','.join(['(%s, %s, %s, %s, %s)'] * len(update_items))
            if update_items
            else '(NULL::int,NULL::bool,NULL::text,NULL::text,NULL::text)'
        )

        # Mentions parsing re-reads the just-written bodies; callers skip the blocks
        # outside the 90-day notification window (hive_mentions is windowed data whose
        # only consumer is notification rendering). A post's last block reads its
        # just-written body (NULL here), its earlier blocks the body they ended with.
        # It runs as a statement of its own: a function called from the statement that
        # writes the bodies does not see the rows that statement inserts.
        mention_post_ids: list[int] = []
        mention_blocks: list[int] = []
        mention_bodies: list[str | None] = []
        for pid, blocks in cls._blocks.items():
            for block_num in blocks:
                if block_num > mentions_after_block:
                    mention_post_ids.append(pid)
                    mention_blocks.append(block_num)
                    mention_bodies.append(
                        None if block_num == blocks[-1] else _sanitize_nul(cls._block_bodies[(pid, block_num)])
                    )

        sql = f"""
            WITH insert_values(id, is_root, title, body, json) AS (
                SELECT * FROM (VALUES {insert_ph}) AS v(id, is_root, title, body, json)
                WHERE v.id IS NOT NULL
            ),
            update_values(id, is_root, title, body, json) AS (
                SELECT * FROM (VALUES {update_ph}) AS v(id, is_root, title, body, json)
            ),
            insert_post_data AS (
                INSERT INTO {SCHEMA_NAME}.hive_post_data
                SELECT id, title, body, json FROM insert_values
                RETURNING id
            ),
            update_post_data AS (
                UPDATE {SCHEMA_NAME}.hive_post_data AS hpd
                SET title = COALESCE( i.title, hpd.title ),
                    body = COALESCE( i.body, hpd.body ),
                    json = COALESCE( i.json, hpd.json )
                FROM update_values i
                WHERE hpd.id = i.id AND i.id IS NOT NULL
                RETURNING hpd.id
            ),
            combined AS (
                SELECT id FROM insert_post_data
                UNION ALL
                SELECT id FROM update_post_data
            )
            SELECT count(id) FROM combined
        """

        params: list[Any] = []
        for item in insert_items:
            params.extend(item)
        for item in update_items:
            params.extend(item)

        if print_query:
            log.info(f"Executing query:\n{sql}")

        if params:
            cls._own_db().query_all_raw(sql, tuple(params))
        else:
            cls._own_db().query_all_raw(sql)
        if mention_post_ids:
            cls._own_db().query_all_raw(
                f"SELECT {SCHEMA_NAME}.process_hive_post_mentions(%s::INT[], %s::INT[], %s::TEXT[])",
                (mention_post_ids, mention_blocks, mention_bodies),
            )
        if batch_first_block is not None:
            cls._own_db().query_no_return(
                f"UPDATE {SCHEMA_NAME}._batch_queue SET post_data_applied = TRUE WHERE first_block = {batch_first_block:d}"
            )

        cls.commitTx()

        n = len(cls._data)
        cls._data.clear()
        cls._blocks.clear()
        cls._block_bodies.clear()
        return n
