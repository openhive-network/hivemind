SET ROLE hivemind;

START TRANSACTION;

insert into hivemind_app.hive_db_patch_level
(patch_date, patched_to_revision)
select ds.patch_date, ds.patch_revision
from
(
values
 (now(), '2a6576357f9a0a55fafd7e6169f32ed65663cb50'), -- https://gitlab.syncad.com/hive/hivemind/-/merge_requests/677
 (now(), 'ea5ff41e167830193b64bf9d20aab65f18937df6'), -- hivemind_app.follows.follower_name and follows_following_follower_name_idx
 (now(), '56006632edbca3207b5fd780f85f49eb3398e337'), -- hivemind_app.hive_accounts.post_count
 (now(), 'e2635288661e050c5c7a666b5e2d2fd9eb6f2fd5'), -- hivemind_app.hive_replies and hive_posts_author_id_payout_plus_pending_payout_id_idx
 (now(), '8a0c0aa8b81e00cc0dac6377a6d0362677838a6b') -- hivemind_app.hive_accounts.id is HAF's account id, without haf_id
) ds (patch_date, patch_revision)
where not exists (select null from hivemind_app.hive_db_patch_level hpl where hpl.patched_to_revision = ds.patch_revision);

COMMIT;

RESET ROLE;
