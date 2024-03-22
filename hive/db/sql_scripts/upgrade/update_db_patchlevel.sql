START TRANSACTION;

insert into hivemind_app.hive_db_patch_level
(patch_date, patched_to_revision)
select ds.patch_date, ds.patch_revision
from
(
values
 (now(), '2a6576357f9a0a55fafd7e6169f32ed65663cb50') -- https://gitlab.syncad.com/hive/hivemind/-/merge_requests/677
) ds (patch_date, patch_revision)
where not exists (select null from hivemind_app.hive_db_patch_level hpl where hpl.patched_to_revision = ds.patch_revision);

COMMIT;
