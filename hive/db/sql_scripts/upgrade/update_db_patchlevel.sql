START TRANSACTION;

insert into hive_db_patch_level
(level, patch_date, patched_to_revision)
select ds.level, ds.patch_date, ds.patch_revision
from
(
values
 (33, now(), 'f5ee382637a1164192bf82b68a3412ee1d5b0e60') -- https://gitlab.syncad.com/hive/hivemind/-/merge_requests/574
,(34, now(), '9d2cc15bea71a39139abdf49569e0eac6dd0b970') -- https://gitlab.syncad.com/hive/hivemind/-/merge_requests/575

) ds (level, patch_date, patch_revision)
where not exists (select null from hive_db_patch_level hpl where hpl.patched_to_revision = ds.patch_revision);

COMMIT;
