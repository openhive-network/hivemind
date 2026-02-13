"""Core posts manager — most processing now handled by SQL (process_posts_from_staging).

Only _merge_post_body remains in Python for diff-patch body merging.
"""

import logging

from diff_match_patch import diff_match_patch

from hive.indexer.db_adapter_holder import DbAdapterHolder
from hive.indexer.post_data_cache import PostDataCache

log = logging.getLogger(__name__)


class Posts(DbAdapterHolder):
    """Handles post operations. Only body merging (diff patches) remains in Python."""

    @classmethod
    def _merge_post_body(cls, id, new_body_def):
        new_body = ''
        old_body = ''

        try:
            dmp = diff_match_patch()
            patch = dmp.patch_fromText(new_body_def)
            if patch is not None and len(patch):
                old_body = PostDataCache.get_post_body(id)
                new_body, _ = dmp.patch_apply(patch, old_body)
            else:
                new_body = new_body_def
        except ValueError:
            new_body = new_body_def
        except Exception as ex:
            log.info(f"Merging a body post id: {id} caused an unknown exception {ex}")
            log.info(f"New body definition: {new_body_def}")
            log.info(f"Old body definition: {old_body}")
            new_body = new_body_def

        return new_body
