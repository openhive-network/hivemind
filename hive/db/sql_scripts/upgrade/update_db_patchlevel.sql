START TRANSACTION;

insert into hivemind_app.hive_db_patch_level
(level, patch_date, patched_to_revision)
select ds.level, ds.patch_date, ds.patch_revision
from
(
values
-- Continuous work related to HAF hivemind version deployement.
(33, now(), '6473f98c9157af484dacee1656977d2d11779c60') -- https://gitlab.syncad.com/hive/hivemind/-/merge_requests/558
) ds (level, patch_date, patch_revision)
where not exists (select null from hivemind_app.hive_db_patch_level hpl where hpl.patched_to_revision = ds.patch_revision);

COMMIT;
