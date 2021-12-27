BEGIN;

DROP TABLE public.benchmark_description CASCADE;
CREATE TABLE IF NOT EXISTS public.benchmark_description
(
    id bigint NOT NULL GENERATED BY DEFAULT AS IDENTITY,
    description text NOT NULL,
    execution_environment_description text NOT NULL,
    "timestamp" timestamp without time zone NOT NULL,
    server_name text NOT NULL,
    app_version text NOT NULL,
    testsuite_version text NOT NULL,
    runner text NOT NULL,
    PRIMARY KEY (id)
);

DROP TABLE public.testcase CASCADE;
CREATE TABLE IF NOT EXISTS public.testcase
(
    hash text NOT NULL,
    caller text NOT NULL,
    method text NOT NULL,
    params text NOT NULL,
    PRIMARY KEY (hash)
);

DROP TABLE public.benchmark_values CASCADE;
CREATE TABLE IF NOT EXISTS public.benchmark_values
(
    benchmark_description_id bigint NOT NULL,
    testcase_hash text NOT NULL,
    occurrence_number integer NOT NULL,
    value bigint NOT NULL,
    unit text NOT NULL,
    PRIMARY KEY (benchmark_description_id, testcase_hash, occurrence_number)
);

ALTER TABLE IF EXISTS public.benchmark_values
    ADD FOREIGN KEY (benchmark_description_id)
    REFERENCES public.benchmark_description (id) MATCH SIMPLE
    ON UPDATE NO ACTION
    ON DELETE NO ACTION
    NOT VALID;


ALTER TABLE IF EXISTS public.benchmark_values
    ADD FOREIGN KEY (testcase_hash)
    REFERENCES public.testcase (hash) MATCH SIMPLE
    ON UPDATE NO ACTION
    ON DELETE NO ACTION
    NOT VALID;


CREATE UNIQUE INDEX unique_testcase_hash ON testcase (hash);

CREATE VIEW benchmark_results_collector_merged AS
    SELECT  b.id,
            b.description,
            b.execution_environment_description,
            b.timestamp,
            b.server_name,
            b.app_version,
            b.testsuite_version,
            b.runner,
            bv.value,
            bv.unit,
            t.hash,
            t.caller,
            t.method,
            t.params
    FROM benchmark_description  b
    JOIN benchmark_values       bv  ON (b.id    = bv.benchmark_description_id)
    JOIN testcase               t   ON (t.hash  = bv.testcase_hash);

END;