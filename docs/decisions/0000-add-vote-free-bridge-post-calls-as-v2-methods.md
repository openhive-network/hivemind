---
date: 2026-10-09
status: accepted
decision-makers: []
consulted: []
informed: []

id: DR-PENDING
proposed_by: claude
area: server/bridge_api
related_issues: [348]
related_decisions: []
---

# Change the bridge post shape only through new `*_v2` methods, keeping the existing calls byte-identical

## Context and Problem Statement

Bridge post objects embed up to 1000 `active_votes`, which dominate response size and
are wrong for the one thing front ends use them for (the observer's own vote on posts
with more than 1000 votes). Every front end, bot, library and mobile app depends on
the current shape of `bridge.get_ranked_posts`, `get_account_posts`, `get_post` and
`get_discussion`, which has blocked changing them for years.

## Considered Options

* Change the existing calls' post objects (drop or trim `active_votes`)
* Add `bridge.*_v2` methods with a vote-free post object, leave the existing calls unchanged
* Add vote-free variants to condenser_api as well

## Decision Outcome

Chosen option: **"Add `bridge.*_v2` methods, leave the existing calls unchanged"**,
because consumers of the existing shape can't be migrated in step, and new methods let
each site switch when ready (falling back to the old method on nodes that answer
"unknown method"). condenser_api gets no variants: it is semi-deprecated.

Both shapes come from one builder, `hivemind_postgrest_utilities.create_bridge_post_object`,
selected by `_votes_mode` (0 = embedded `active_votes`, 1 = `observer_vote` plus optional
`top_votes`). The shared ranked-post and account-post utilities and the four bridge
endpoint functions carry `_votes_mode` / `_top_votes` as trailing parameters whose
defaults reproduce the existing output. The `*_v2` methods are dispatch entries in
`get_bridge_method` that call the same endpoint functions with `_votes_mode = 1`.

### Consequences

* Good, because existing clients see no change (the defaulted mode-0 path rebuilds the same object; checked byte-for-byte only in a local comparison on seeded data, as the existing tavern pattern suites need the replayed 5M HAF and were not run for this change), and the new calls skip the embedded 1000-vote list, replacing it with one (post_id, voter_id) probe for observer_vote and, only when top_votes > 0, a top-N vote query.
* Good, because one builder serves both shapes, so a field added to bridge posts reaches
  both without duplication.
* Bad, because every change to the bridge post builders must keep both modes working, and
  new builders that feed these four methods must thread `_votes_mode` / `_top_votes`.
* Bad, because the old shape stays until a deprecation is decided from adoption; no
  schedule exists.
