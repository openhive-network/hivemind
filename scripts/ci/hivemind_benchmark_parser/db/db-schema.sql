BEGIN;


CREATE TABLE IF NOT EXISTS public.request
(
    id bigint NOT NULL GENERATED ALWAYS AS IDENTITY,
    api text NOT NULL,
    method text NOT NULL,
    parameters text NOT NULL,
    hash text NOT NULL,
    PRIMARY KEY (id)
);

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

CREATE TABLE IF NOT EXISTS public.request_times
(
    benchmark_id bigint NOT NULL,
    request_id bigint NOT NULL,
    testcase_id integer NOT NULL,
    execution_time bigint NOT NULL,
    PRIMARY KEY (benchmark_id, request_id, testcase_id)
);

ALTER TABLE IF EXISTS public.request_times
    ADD FOREIGN KEY (benchmark_id)
    REFERENCES public.benchmark_description (id) MATCH SIMPLE
    ON UPDATE NO ACTION
    ON DELETE NO ACTION
    NOT VALID;


ALTER TABLE IF EXISTS public.request_times
    ADD FOREIGN KEY (request_id)
    REFERENCES public.request (id) MATCH SIMPLE
    ON UPDATE NO ACTION
    ON DELETE NO ACTION
    NOT VALID;


CREATE UNIQUE INDEX unique_request_idx ON request (hash);

END;