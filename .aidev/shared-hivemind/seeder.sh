#!/usr/bin/env bash
# The `seeder` service of the shared hivemind (.aidev/shared-hivemind.compose.yml):
# keeps a template per requested (schema revision, sync recipe), seeding them one
# at a time with seed.sh. Runs in hivemind's AIDEV runtime image, in the `hivemind`
# container's network namespace (PostgreSQL on 127.0.0.1).
#
# Requests come from consumers (hivemind_shared.request_seed, called by the
# `tavern` step when no template has its tree's recipe) and, every
# HIVEMIND_SHARED_REFS_INTERVAL seconds, from the tips of
# HIVEMIND_SHARED_SEED_REFS, so the branches tests run against are seeded before
# anyone asks, also when only their recipe moved. A request whose seed fails is
# marked failed with its log tail (visible in hivemind_shared.seed_requests) and
# is retried only for another commit.
#
# Whenever it is idle it retires every template past the newest
# HIVEMIND_SHARED_KEEP_TEMPLATES of its revision that no run was cloned from
# (shared_fixture.py retire, hivemind_shared.drop_template).
#
# Environment: HIVEMIND_SHARED_REMOTE, HAF_FIXTURE_COMMIT (the recipe's, and
# seed.sh's), HIVEMIND_SHARED_SEED_REFS (default "develop"),
# HIVEMIND_SHARED_REFS_INTERVAL (default 1800), HIVEMIND_SHARED_SEED_POLL
# (default 60), HIVEMIND_SHARED_KEEP_TEMPLATES (default 3).
set -uo pipefail

remote="${HIVEMIND_SHARED_REMOTE:?HIVEMIND_SHARED_REMOTE must name the hivemind repository to fetch}"
refs="${HIVEMIND_SHARED_SEED_REFS:-develop}"
refs_interval="${HIVEMIND_SHARED_REFS_INTERVAL:-1800}"
poll="${HIVEMIND_SHARED_SEED_POLL:-60}"
keep="${HIVEMIND_SHARED_KEEP_TEMPLATES:-3}"
haf_commit="${HAF_FIXTURE_COMMIT:?HAF_FIXTURE_COMMIT must name the HAF commit templates are seeded on}"
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
    local ref commit rev recipe
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
        if ! recipe="$(python3 "$here/shared_fixture.py" recipe commit "$refs_git" "$commit" "$haf_commit")"; then
            echo "$ref ($commit): no sync recipe; not requesting a seed"
            continue
        fi
        echo "$ref ($commit): revision $rev, recipe $recipe: $(q -v rev="$rev" -v recipe="$recipe" -v commit="$commit" \
            <<< "select hivemind_shared.request_seed(:'rev', :'recipe', :'commit')")"
    done
}

retire_templates() {
    local db
    q -c "select revision || ' ' || recipe || ' ' || template || ' ' || run_databases from hivemind_shared.health()" \
        | python3 "$here/shared_fixture.py" retire "$keep" \
        | while read -r db; do
            echo "retiring $db: $(q -v db="$db" <<< "select hivemind_shared.drop_template(:'db')")"
        done
}

claim() {
    q <<'SQL'
update hivemind_shared.seed_requests set state = 'seeding', updated_at = now()
where (revision, recipe) = (select revision, recipe from hivemind_shared.seed_requests where state = 'pending'
                            order by requested_at limit 1 for update skip locked)
returning revision || ' ' || recipe || ' ' || hivemind_commit;
SQL
}

finish() {
    q -v rev="$1" -v recipe="$2" -v state="$3" -v detail="$4" <<'SQL'
update hivemind_shared.seed_requests set state = :'state', detail = nullif(:'detail', ''), updated_at = now()
where revision = :'rev' and recipe = :'recipe';
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
        retire_templates || echo "retiring templates failed; retrying in ${poll}s"
        sleep "$poll"
        continue
    fi
    read -r rev recipe commit <<< "$claimed"
    log="$(mktemp)"
    echo "seeding revision $rev, recipe $recipe from $commit"
    if "$here/seed.sh" "$rev" "$recipe" "$commit" 2>&1 | tee "$log"; then
        finish "$rev" "$recipe" done ""
    else
        echo "seeding revision $rev, recipe $recipe from $commit failed"
        finish "$rev" "$recipe" failed "$(tail -c 2000 "$log")"
    fi
    rm -f "$log"
done
