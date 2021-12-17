BEGIN;


CREATE TABLE IF NOT EXISTS public.benchmark_description
(
    id bigint NOT NULL GENERATED ALWAYS AS IDENTITY,
    description text NOT NULL,
    execution_environment_description text NOT NULL,
    "timestamp" timestamp without time zone NOT NULL,
    server_name text NOT NULL,
    app_version text NOT NULL,
    testsuite_version text NOT NULL,
    runner text NOT NULL,
    PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.testcase
(
    hash text NOT NULL,
    caller text NOT NULL,
    method text NOT NULL,
    params text NOT NULL,
    PRIMARY KEY (hash)
);

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

END;