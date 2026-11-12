SET ROLE hivemind;

START TRANSACTION;

insert into hivemind_app.hive_db_patch_level
(patch_date, patched_to_revision)
select ds.patch_date, ds.patch_revision
from
(
values
 (now(), '2a6576357f9a0a55fafd7e6169f32ed65663cb50'), -- https://gitlab.syncad.com/hive/hivemind/-/merge_requests/677
 (now(), 'ea5ff41e167830193b64bf9d20aab65f18937df6') -- hivemind_app.follows.follower_name and follows_following_follower_name_idx
) ds (patch_date, patch_revision)
where not exists (select null from hivemind_app.hive_db_patch_level hpl where hpl.patched_to_revision = ds.patch_revision);

COMMIT;

RESET ROLE;
