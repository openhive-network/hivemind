
    ./scripts/ci/start-api-smoketest.sh \
        localhost \
        $RUNNER_HIVEMIND_SERVER_HTTP_PORT \
        bridge_api_patterns/ \
        api_smoketest_bridge.xml \
        $RUNNER_PYTEST_WORKERS  || true



    ./scripts/ci/start-api-smoketest.sh \
        localhost \
        $RUNNER_HIVEMIND_SERVER_HTTP_PORT \
        bridge_api_negative/ \
        api_smoketest_bridge_negative.xml \
        $RUNNER_PYTEST_WORKERS  || true



    ./scripts/ci/start-api-smoketest.sh \
        localhost \
        $RUNNER_HIVEMIND_SERVER_HTTP_PORT \
        condenser_api_patterns/ \
        api_smoketest_condenser_api.xml \
        $RUNNER_PYTEST_WORKERS  || true



    ./scripts/ci/start-api-smoketest.sh \
        localhost \
        $RUNNER_HIVEMIND_SERVER_HTTP_PORT \
        condenser_api_negative/ \
        api_smoketest_condenser_api_negative.xml \
        $RUNNER_PYTEST_WORKERS  || true


    ./scripts/ci/start-api-smoketest.sh \
        localhost \
        $RUNNER_HIVEMIND_SERVER_HTTP_PORT \
        database_api_patterns/ \
        api_smoketest_database_api.xml \
        $RUNNER_PYTEST_WORKERS  || true



    ./scripts/ci/start-api-smoketest.sh \
        localhost \
        $RUNNER_HIVEMIND_SERVER_HTTP_PORT \
        database_api_negative/ \
        api_smoketest_database_api_negative.xml \
        $RUNNER_PYTEST_WORKERS  || true



    ./scripts/ci/start-api-smoketest.sh \
        localhost \
        $RUNNER_HIVEMIND_SERVER_HTTP_PORT \
        follow_api_patterns/ \
        api_smoketest_follow_api.xml \
        $RUNNER_PYTEST_WORKERS  || true



    ./scripts/ci/start-api-smoketest.sh \
        localhost \
        $RUNNER_HIVEMIND_SERVER_HTTP_PORT \
        follow_api_negative/ \
        api_smoketest_follow_api_negative.xml \
        $RUNNER_PYTEST_WORKERS  || true



    ./scripts/ci/start-api-smoketest.sh \
        localhost \
        $RUNNER_HIVEMIND_SERVER_HTTP_PORT \
        tags_api_negative/ \
        api_smoketest_tags_api_negative.xml \
        $RUNNER_PYTEST_WORKERS  || true



    ./scripts/ci/start-api-smoketest.sh \
        localhost \
        $RUNNER_HIVEMIND_SERVER_HTTP_PORT \
        tags_api_patterns/ \
        api_smoketest_tags_api.xml \
        $RUNNER_PYTEST_WORKERS  || true


    ./scripts/ci/start-api-smoketest.sh \
        localhost \
        $RUNNER_HIVEMIND_SERVER_HTTP_PORT \
        mock_tests/ \
        api_smoketest_mock_tests.xml \
        $RUNNER_PYTEST_WORKERS  || true



    ./scripts/ci/start-api-smoketest.sh \
        localhost \
        $RUNNER_HIVEMIND_SERVER_HTTP_PORT \
        hive_api_patterns/ \
        api_smoketest_hive_api.xml \
        $RUNNER_PYTEST_WORKERS  || true


