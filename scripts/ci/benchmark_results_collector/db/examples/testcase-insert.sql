INSERT INTO public.testcase
VALUES (default, 'testapi', 'method', '{"param": "aaabbb"}')
ON CONFLICT (hash) DO UPDATE
SET api = public.testcase.api
RETURNING id;

SELECT setval('public.testcase_id_seq', MAX(id)) FROM public.testcase;