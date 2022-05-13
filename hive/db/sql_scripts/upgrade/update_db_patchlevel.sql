START TRANSACTION;

insert into hivemind_app.hive_db_patch_level
(patch_date, patched_to_revision)
select ds.patch_date, ds.patch_revision
from
(
values
(now(), '7b8def051be224a5ebc360465f7a1522090c7125'),
(now(), 'e17bfcb08303cbf07b3ce7d1c435d59a368b4a9e'),
(now(), '0be8e6e8b2121a8f768113e35e47725856c5da7c'), -- update_hot_and_trending_for_blocks fix, https://gitlab.syncad.com/hive/hivemind/-/merge_requests/247
(now(), '26c2f1862770178d4575ec09e9f9c225dcf3d206'), -- https://gitlab.syncad.com/hive/hivemind/-/merge_requests/252
(now(), 'e8b65adf22654203f5a79937ff2a95c5c47e10c5'), -- https://gitlab.syncad.com/hive/hivemind/-/merge_requests/251
(now(), '8d0b673e7c40c05d2b8ae74ccf32adcb6b11f906'), -- https://gitlab.syncad.com/hive/hivemind/-/merge_requests/265
-- https://gitlab.syncad.com/hive/hivemind/-/merge_requests/281
-- https://gitlab.syncad.com/hive/hivemind/-/merge_requests/282
-- https://gitlab.syncad.com/hive/hivemind/-/merge_requests/257
-- https://gitlab.syncad.com/hive/hivemind/-/merge_requests/251
-- https://gitlab.syncad.com/hive/hivemind/-/merge_requests/265
--
(now(), '45c2883131472cc14a03fe4e355ba1435020d720'),
(now(), '7cfc2b90a01b32688075b22a6ab173f210fc770f'), -- https://gitlab.syncad.com/hive/hivemind/-/merge_requests/286
(now(), 'f2e5f656a421eb1dd71328a94a421934eda27a87')  -- https://gitlab.syncad.com/hive/hivemind/-/merge_requests/275
,(now(), '4cdf5d19f6cfcb73d3fa504cac9467c4df31c02e') -- https://gitlab.syncad.com/hive/hivemind/-/merge_requests/295
--- https://gitlab.syncad.com/hive/hivemind/-/merge_requests/294
--- https://gitlab.syncad.com/hive/hivemind/-/merge_requests/298
--- https://gitlab.syncad.com/hive/hivemind/-/merge_requests/301
--- https://gitlab.syncad.com/hive/hivemind/-/merge_requests/297
--- https://gitlab.syncad.com/hive/hivemind/-/merge_requests/302
,(now(), '166327bfa87beda588b20bfcfa574389f4100389')
,(now(), '88e62bdf1fcc47809fec84424cf98c71ce87ca89') -- https://gitlab.syncad.com/hive/hivemind/-/merge_requests/310
,(now(), 'f8ecf376da5e0efef64b79f91e9803eac8b163a4') -- https://gitlab.syncad.com/hive/hivemind/-/merge_requests/289
,(now(), '0e3c8700659d98b45f1f7146dc46a195f905fc2d') -- https://gitlab.syncad.com/hive/hivemind/-/merge_requests/306 update posts children count fix
,(now(), '9e126e9d762755f2b9a0fd68f076c9af6bb73b76') -- https://gitlab.syncad.com/hive/hivemind/-/merge_requests/314 mentions fix
,(now(), '033619277eccea70118a5b8dc0c73b913da0025f') -- https://gitlab.syncad.com/hive/hivemind/-/merge_requests/326 https://gitlab.syncad.com/hive/hivemind/-/merge_requests/322 posts rshares recalc
,(now(), '1847c75702384c7e34c624fc91f24d2ef20df91d') -- latest version of develop containing included changes.
,(now(), '1f23e1326f3010bc84353aba82d4aa7ff2f999e4') -- hivemind_app.hive_posts_author_id_created_at_idx index def. to speedup hivemind_app.hive_accounts_info_view.
,(now(), '2a274e586454968a4f298a855a7e60394ed90bde') -- get_number_of_unread_notifications speedup https://gitlab.syncad.com/hive/hivemind/-/merge_requests/348/diffs
,(now(), '431fdaead7dcd69e4d2a45e7ce8a3186b8075515') -- https://gitlab.syncad.com/hive/hivemind/-/merge_requests/367
,(now(), 'cc7bb174d40fe1a0e2221d5d7e1c332c344dca34') -- https://gitlab.syncad.com/hive/hivemind/-/merge_requests/372
,(now(), 'cce7fe54a2242b7a80354ee7e50e5b3275a2b039') -- reputation calc at LIVE sync.
,(now(), '3cb920ec2a3a83911d31d8dd2ec647e2258a19e0') -- Reputation data cleanup https://gitlab.syncad.com/hive/hivemind/-/merge_requests/425
,(now(), '33dd5e52673335284c6aa28ee89a069f83bd2dc6') -- Post initial sync fixes https://gitlab.syncad.com/hive/hivemind/-/merge_requests/439
,(now(), 'a80c7642a1f3b08997af7e8a9915c13d34b7f0e0') -- Notification IDs https://gitlab.syncad.com/hive/hivemind/-/merge_requests/445
,(now(), 'b100db27f37dda3c869c2756d99ab2856f7da9f9') -- hivemind_app.hive_notification_cache table supplement https://gitlab.syncad.com/hive/hivemind/-/merge_requests/447
,(now(), 'bd83414409b7624e2413b97a62fa7d97d83edd86') -- follow notification time is taken from block affecting it  https://gitlab.syncad.com/hive/hivemind/-/merge_requests/449
,(now(), '1cc9981679157e4e54e5e4a74cca1feb5d49296d') -- https://gitlab.syncad.com/hive/hivemind/-/merge_requests/452
,(now(), 'c21f03b2d8cfa6af2386a222c7501580d1d1ce05') -- Prerequisites to sync from SQL: https://gitlab.syncad.com/hive/hivemind/-/commit/c21f03b2d8cfa6af2386a222c7501580d1d1ce05
,(now(), 'd243747e7ff37a6f0bdef88ce5fc3c471b39b238') -- https://gitlab.syncad.com/hive/hivemind/-/commit/d243747e7ff37a6f0bdef88ce5fc3c471b39b238
,(now(), 'a0dc234dc00d1d3ef821f309ebdf4a1d6a58a4bf') -- Verification of block consistency: https://gitlab.syncad.com/hive/hivemind/-/commit/a0dc234dc00d1d3ef821f309ebdf4a1d6a58a4bf
,(now(), '02c3c807c1a65635b98b6657196c10af44ec9d92') -- https://gitlab.syncad.com/hive/hivemind/-/merge_requests/507 https://gitlab.syncad.com/hive/hivemind/-/commit/02c3c807c1a65635b98b6657196c10af44ec9d92
) ds (patch_date, patch_revision)
where not exists (select null from hivemind_app.hive_db_patch_level hpl where hpl.patched_to_revision = ds.patch_revision);

COMMIT;
