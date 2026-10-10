#!/usr/bin/env bash
# The `seeder` service of the shared hivemind (.aidev/shared-hivemind.compose.yml):
# keeps one template per requested schema revision, seeding them one at a time
# with seed.sh. Runs in hivemind's AIDEV runtime image, in the `hivemind`
# container's network namespace (PostgreSQL on 127.0.0.1).
#
# Requests come from consumers (hivemind_shared.request_seed, called by the
# `tavern` step on a revision miss) and, every HIVEMIND_SHARED_REFS_INTERVAL
# seconds, from the tips of HIVEMIND_SHARED_SEED_REFS, so the branches tests run
# against are seeded before anyone asks. A request whose seed fails is marked
# failed with its log tail (visible in hivemind_shared.seed_requests) and is
# retried only for another commit.
#
# Environment: HIVEMIND_SHARED_REMOTE, HAF_FIXTURE_COMMIT (for seed.sh),
# HIVEMIND_SHARED_SEED_REFS (default "develop"), HIVEMIND_SHARED_REFS_INTERVAL
# (default 1800), HIVEMIND_SHARED_SEED_POLL (default 60).
set -uo pipefail

remote="${HIVEMIND_SHARED_REMOTE:?HIVEMIND_SHARED_REMOTE must name the hivemind repository to fetch}"
refs="${HIVEMIND_SHARED_SEED_REFS:-develop}"
refs_interval="${HIVEMIND_SHARED_REFS_INTERVAL:-1800}"
poll="${HIVEMIND_SHARED_SEED_POLL:-60}"
here="$(cd "$(dirname "$0")" && pwd -P)"
patchlevel="hive/db/sql_scripts/upgrade/update_db_patchlevel.sql"
refs_git="$(mktemp -d)"

q() {
    psql -X -q -At -v ON_ERROR_STOP=1 -d postgresql://postgres@127.0.0.1:5432/hivemind_shared "$@"
}

until q -c 'select 1 from hivemind_shared.health() limit 0' >/dev/null 2>&1; do
    echo "waiting for the clone API"
    sleep 10
done
git init -q --bare "$refs_git"

# A seed interrupted by a restart starts over.
q -c "update hivemind_shared.seed_requests set state = 'pending', updated_at = now() where state = 'seeding'"

request_refs() {
    local ref commit rev
    for ref in $refs; do
        commit="$(git ls-remote "$remote" "refs/heads/$ref" | cut -f1)"
        if [ -z "$commit" ]; then
            echo "no branch $ref in $remote"
            continue
        fi
        if ! git --git-dir="$refs_git" fetch -q --depth 1 "$remote" "$commit" \
            || ! rev="$(git --git-dir="$refs_git" show "$commit:$patchlevel" | python3 "$here/shared_fixture.py" revision -)"; then
            echo "$ref ($commit): no schema revision; not requesting a seed"
            continue
        fi
        echo "$ref ($commit): revision $rev: $(q -v rev="$rev" -v commit="$commit" <<< "select hivemind_shared.request_seed(:'rev', :'commit')")"
    done
}

claim() {
    q <<'SQL'
update hivemind_shared.seed_requests set state = 'seeding', updated_at = now()
where revision = (select revision from hivemind_shared.seed_requests where state = 'pending'
                  order by requested_at limit 1 for update skip locked)
returning revision || ' ' || hivemind_commit;
SQL
}

finish() {
    q -v rev="$1" -v state="$2" -v detail="$3" <<'SQL'
update hivemind_shared.seed_requests set state = :'state', detail = nullif(:'detail', ''), updated_at = now()
where revision = :'rev';
SQL
}

next_refs=0
while true; do
    if [ "$SECONDS" -ge "$next_refs" ]; then
        request_refs
        next_refs=$((SECONDS + refs_interval))
    fi
    claimed="$(claim)"
    if [ -z "$claimed" ]; then
        sleep "$poll"
        continue
    fi
    read -r rev commit <<< "$claimed"
    log="$(mktemp)"
    echo "seeding revision $rev from $commit"
    if "$here/seed.sh" "$rev" "$commit" 2>&1 | tee "$log"; then
        finish "$rev" done ""
    else
        echo "seeding revision $rev from $commit failed"
        finish "$rev" failed "$(tail -c 2000 "$log")"
    fi
    rm -f "$log"
done
