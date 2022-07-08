from pathlib import Path
from typing import Final

from setuptools import setup

VERSION_FILEPATH: Final[Path] = Path('hive/version.py')

version_namespace = {}
with open(VERSION_FILEPATH, encoding='utf-8') as ver_file:
    exec(ver_file.read(), version_namespace)

setup(version=f'{version_namespace["VERSION"]}+git{version_namespace["GIT_REVISION"]}')
