INSERT INTO public.benchmark_description
VALUES (default, 'Sample benchmark description', 'test env', TIMESTAMP WITHOUT TIME ZONE '2021-12-08 10:23:54', 'test server','1.00','2.00', 'runner')
RETURNING id;