"""preprocess_search_query turns a find_text pattern into a ParadeDB query string the parser accepts."""

import re
import textwrap
from collections.abc import Callable
from pathlib import Path
from typing import cast

import pytest

_SQL = Path(__file__).resolve().parents[2] / 'hive/db/sql_scripts/postgrest/utilities/preprocess_search_query.sql'


def _load_function() -> Callable[[str], str]:
    # PL/Python runs the body as the body of a function taking the SQL arguments; do the same.
    match = re.search(r'^AS \$\$\n(.*?)^\$\$;', _SQL.read_text(), re.S | re.M)
    assert match is not None, f'no PL/Python body in {_SQL}'
    namespace: dict[str, object] = {}
    exec(f'def preprocess(_pattern):\n{textwrap.indent(match.group(1), "    ")}', namespace)
    function = namespace['preprocess']
    assert callable(function)
    return cast(Callable[[str], str], function)


preprocess = _load_function()


@pytest.mark.parametrize(
    ('pattern', 'expected'),
    [
        ('hive', '(title:hive OR body:hive)'),
        ("don't", "(title:don\\'t OR body:don\\'t)"),
        (
            're: hello',
            '(title:re\\: OR body:re\\:) AND (title:hello OR body:hello)',
        ),
        (
            'x OR y',
            '(title:x OR body:x) AND (title:or OR body:or) AND (title:y OR body:y)',
        ),
        (
            'hive [beta]',
            '(title:hive OR body:hive) AND (title:\\[beta\\] OR body:\\[beta\\])',
        ),
        ('<b>', '(title:\\<b\\> OR body:\\<b\\>)'),
        ('C++', '(title:c\\+\\+ OR body:c\\+\\+)'),
        ('hive-engine', '(title:hive\\-engine OR body:hive\\-engine)'),
        ('hive*', '(title:hive\\* OR body:hive\\*)'),
        ('🐝', '(title:🐝 OR body:🐝)'),
    ],
)
def test_words_are_escaped_literals(pattern: str, expected: str) -> None:
    assert preprocess(pattern) == expected


@pytest.mark.parametrize('pattern', ['(', '*', '?', '—', '""', '"?"', '+(', 'title:', 'title:""', ''])
def test_unsearchable_input_builds_no_query(pattern: str) -> None:
    assert preprocess(pattern) == ''


def test_unsearchable_words_are_dropped_from_a_query() -> None:
    assert preprocess('hive ( steem') == '(title:hive OR body:hive) AND (title:steem OR body:steem)'


def test_must_and_mustnot_terms_are_escaped() -> None:
    assert preprocess("hive +don't -it's") == (
        "(title:hive OR body:hive) +(title:don\\'t OR body:don\\'t) -(title:it\\'s OR body:it\\'s)"
    )


def test_phrase_keeps_its_text_and_escapes_quote_and_backslash() -> None:
    assert preprocess('"<b> a OR b"') == '(title:"<b> a OR b" OR body:"<b> a OR b")'
    assert preprocess('"a\\\\b"') == '(title:"a\\\\b" OR body:"a\\\\b")'


def test_field_values_are_escaped() -> None:
    assert preprocess("title:don't") == "title:don\\'t"
    assert preprocess('body:"hive power"') == 'body:"hive power"'
