"""hivemind pins no test or lint tool: CI and the aidev runtime take them from common-ci-configuration.

Its tool images (python-test-tools, and docker-builder and haf-app-test-runner built on it)
carry every tool at the versions of its docker-bake.hcl. A pin here, or an override of one
of those images' tags, would run a tool at another version than the rest of the
organisation's CI and stay behind when common-ci-configuration moves.
"""

import configparser
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

TOOLS = frozenset({'pytest', 'pytest-xdist', 'tavern', 'deepdiff', 'jsondiff', 'ruff', 'mypy', 'tox'})
# common-ci-configuration's templates default these to its moving tags.
_IMAGE_TAG_VARIABLES = (
    'DOCKER_BUILDER_TAG',
    'DOCKER_DIND_TAG',
    'PYTHON_TEST_TOOLS_TAG',
    'PYTHON_TEST_TOOLS_IMAGE',
    'HAF_APP_TEST_RUNNER_TAG',
    'HAF_APP_TEST_RUNNER_IMAGE',
)

_REQUIREMENT_RE = re.compile(r"""['"]?([A-Za-z0-9_.-]+)(?:\[[^\]]*\])?\s*([=<>!~][^'"]*)?['"]?""")
_PIP_INSTALL_RE = re.compile(r'pip install ((?:\\\n|[^\n&;|])*)')


def _tool_pin(requirement: str) -> str | None:
    """`requirement` when it names a tool with a version specifier, else None."""
    match = _REQUIREMENT_RE.fullmatch(requirement.strip())
    if match and match.group(1).lower() in TOOLS and match.group(2):
        return requirement.strip()
    return None


def _tox_tool_pins(tox_ini: str) -> list[str]:
    parser = configparser.ConfigParser(interpolation=None)
    parser.read_string(tox_ini)
    return [
        f'[{section}] {pin}'
        for section in parser.sections()
        for line in parser.get(section, 'deps', fallback='').splitlines()
        if (pin := _tool_pin(line))
    ]


def _setup_cfg_tool_pins(setup_cfg: str) -> list[str]:
    parser = configparser.ConfigParser(interpolation=None)
    parser.read_string(setup_cfg)
    extras = parser['options.extras_require'] if parser.has_section('options.extras_require') else {}
    return [
        f'[{extra}] {pin}' for extra, value in extras.items() for line in value.splitlines() if (pin := _tool_pin(line))
    ]


def _pip_installed_tools(text: str) -> list[str]:
    """The tools a `pip install` command of `text` (a Dockerfile or a CI script) names."""
    tools = []
    for command in _PIP_INSTALL_RE.findall(text):
        for word in command.replace('\\\n', ' ').split():
            match = _REQUIREMENT_RE.fullmatch(word)
            if match and match.group(1).lower() in TOOLS:
                tools.append(word)
    return tools


def _image_tag_overrides(gitlab_ci: str) -> list[str]:
    return [
        line.strip() for line in gitlab_ci.splitlines() if re.match(rf'\s+({"|".join(_IMAGE_TAG_VARIABLES)})\s*:', line)
    ]


def _read(path: str) -> str:
    return (ROOT / path).read_text(encoding='utf-8')


def test_tox_tool_pins_name_section_and_requirement() -> None:
    tox_ini = (
        '[testenv]\ndeps =\n  pytest==8.4.2\n  requests==2.32.3\n\n'
        '[testenv:tavern]\ndeps =\n  {[testenv]deps}\n  tavern\n  deepdiff[murmur] >= 8\n'
        '  git+https://example.org/plugin.git@branch#egg=tavern-time-request\n'
    )

    assert _tox_tool_pins(tox_ini) == ['[testenv] pytest==8.4.2', '[testenv:tavern] deepdiff[murmur] >= 8']


def test_setup_cfg_tool_pins_read_the_extras() -> None:
    setup_cfg = (
        '[options]\ninstall_requires =\n    ujson == 5.12.0\n\n'
        '[options.extras_require]\ndev =\n    pyYAML == 6.0.2\n    ruff >= 0.6.5\n\ntests =\n    tox\n'
    )

    assert _setup_cfg_tool_pins(setup_cfg) == ['[dev] ruff >= 0.6.5']


def test_pip_installed_tools_read_continued_and_quoted_arguments() -> None:
    text = (
        'RUN apt-get install -y gcc \\\n'
        '    && python3 -m pip install --no-cache-dir -r /tmp/r.txt pytest==8.4.2 \\\n'
        "        'deepdiff[murmur]==8.1.1' psycopg2-binary \\\n"
        '    && apt-get purge -y gcc\n'
        '  - pip install --quiet --break-system-packages tox\n'
    )

    assert _pip_installed_tools(text) == ['pytest==8.4.2', "'deepdiff[murmur]==8.1.1'", 'tox']


def test_image_tag_overrides_find_variables_not_references() -> None:
    gitlab_ci = (
        'variables:\n  DOCKER_BUILDER_TAG: "47dab930"\n  IMAGE_REMOVER_TAG: "latest"\n'
        'job:\n  image: docker-builder:${DOCKER_BUILDER_TAG}\n'
    )

    assert _image_tag_overrides(gitlab_ci) == ['DOCKER_BUILDER_TAG: "47dab930"']


def test_tox_and_setup_cfg_pin_no_tool() -> None:
    assert _tox_tool_pins(_read('tox.ini')) == []
    assert _setup_cfg_tool_pins(_read('setup.cfg')) == []


def test_no_image_installs_a_tool() -> None:
    for path in ('Dockerfile', '.aidev/runtime/Dockerfile', '.gitlab-ci.yml'):
        assert _pip_installed_tools(_read(path)) == [], path


def test_ci_keeps_common_ci_configuration_image_tags() -> None:
    assert _image_tag_overrides(_read('.gitlab-ci.yml')) == []


def test_aidev_runtime_is_built_on_the_followed_base() -> None:
    dockerfile = _read('.aidev/runtime/Dockerfile')

    assert re.search(r'^ARG BASE_IMAGE\nFROM \$\{BASE_IMAGE\}$', dockerfile, re.MULTILINE)
    assert len(re.findall(r'^FROM ', dockerfile, re.MULTILINE)) == 1
