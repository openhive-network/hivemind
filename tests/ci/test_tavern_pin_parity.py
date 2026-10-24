"""CI's tox tavern env and the aidev runtime image must pin the same test packages.

The aidev `tavern` step runs the suite on the runtime image's packages, CI runs it through
`tox -e tavern`: a package at another version there passes or fails one and not the other.
"""

import configparser
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TOX_INI = ROOT / 'tox.ini'
DOCKERFILE = ROOT / '.aidev' / 'runtime' / 'Dockerfile'
TOX_ENV = 'testenv:tavern'

_TOX_REFERENCE_RE = re.compile(r'\{\[([^\]]+)\]deps\}')
_PIN_RE = re.compile(r"""['"]?([A-Za-z0-9_.-]+)(?:\[[^\]]*\])?==([^\s'"]+)['"]?""")


def _tox_pins(tox_ini: str, section: str = TOX_ENV) -> dict[str, str]:
    """The `name==version` deps of tox.ini's `section`, its `{[other]deps}` references expanded."""
    parser = configparser.ConfigParser(interpolation=None)
    parser.read_string(tox_ini)
    pins: dict[str, str] = {}
    for line in parser.get(section, 'deps', fallback='').splitlines():
        line = line.strip()
        reference = _TOX_REFERENCE_RE.fullmatch(line)
        pin = _PIN_RE.fullmatch(line)
        if reference:
            pins.update(_tox_pins(tox_ini, reference.group(1)))
        elif pin:
            pins[pin.group(1).lower()] = pin.group(2)
    return pins


def _dockerfile_pins(dockerfile: str) -> dict[str, str]:
    """The `name==version` arguments of the Dockerfile's `pip install` commands."""
    pins: dict[str, str] = {}
    for command in re.findall(r'pip install ((?:\\\n|[^\n&])*)', dockerfile):
        for word in command.replace('\\\n', ' ').split():
            pin = _PIN_RE.fullmatch(word)
            if pin:
                pins[pin.group(1).lower()] = pin.group(2)
    return pins


def _mismatches(tox: dict[str, str], image: dict[str, str]) -> list[str]:
    return [
        f'{name}: tox.ini [{TOX_ENV}] pins {version}, .aidev/runtime/Dockerfile '
        + (f'pins {image[name]}' if name in image else 'does not pin it')
        for name, version in sorted(tox.items())
        if image.get(name) != version
    ]


def test_tox_pins_expand_references_and_skip_unpinned_deps() -> None:
    tox_ini = (
        '[testenv]\ndeps =\n  pytest==8.4.2\n\n'
        '[testenv:tavern]\ndeps =\n  {[testenv]deps}\n  tavern==3.0.2\n  deepdiff[murmur]==8.1.1\n  requests\n'
    )

    assert _tox_pins(tox_ini) == {'pytest': '8.4.2', 'tavern': '3.0.2', 'deepdiff': '8.1.1'}


def test_dockerfile_pins_read_continued_and_quoted_arguments() -> None:
    dockerfile = (
        'RUN apt-get install -y gcc \\\n'
        '    && pip install --no-cache-dir -r /tmp/r.txt pytest==8.4.2 \\\n'
        "        tavern==3.0.2 'deepdiff[murmur]==8.1.1' \\\n"
        '    && apt-get purge -y gcc\n'
        'RUN pip install other==1.0\n'
    )

    assert _dockerfile_pins(dockerfile) == {
        'pytest': '8.4.2',
        'tavern': '3.0.2',
        'deepdiff': '8.1.1',
        'other': '1.0',
    }


def test_mismatches_name_the_package_and_both_versions() -> None:
    tox = {'pytest': '8.3.4', 'tavern': '3.0.2', 'jsondiff': '2.2.1'}
    image = {'pytest': '8.4.2', 'tavern': '3.0.2', 'ruff': '0.16.10'}

    assert _mismatches(tox, image) == [
        f'jsondiff: tox.ini [{TOX_ENV}] pins 2.2.1, .aidev/runtime/Dockerfile does not pin it',
        f'pytest: tox.ini [{TOX_ENV}] pins 8.3.4, .aidev/runtime/Dockerfile pins 8.4.2',
    ]


def test_tox_tavern_env_and_aidev_runtime_image_pin_the_same_versions() -> None:
    tox = _tox_pins(TOX_INI.read_text(encoding='utf-8'))
    image = _dockerfile_pins(DOCKERFILE.read_text(encoding='utf-8'))

    assert {'pytest', 'tavern', 'pytest-xdist', 'deepdiff', 'jsondiff'} <= tox.keys()
    mismatches = _mismatches(tox, image)
    assert not mismatches, 'test pins drifted apart:\n' + '\n'.join(mismatches)
