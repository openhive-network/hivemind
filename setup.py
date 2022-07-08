from pathlib import Path
from typing import Final

from setuptools import find_packages, setup

VERSION_FILEPATH: Final[Path] = Path('hive/version.py')

version_namespace = {}
with open(VERSION_FILEPATH, encoding='utf-8') as ver_file:
    exec(ver_file.read(), version_namespace)

setup(
    name='hive',
    version=f'{version_namespace["VERSION"]}_{version_namespace["GIT_REVISION"]}',
    description='Developer-friendly microservice powering social networks on the Hive blockchain.',
    long_description=open('README.md').read(),
    packages=find_packages(exclude=['scripts']),
    package_data={'sql_scripts': ['hive/db/sql_scripts/*.sql']},
    python_requires='>=3.8',
    setup_requires=['pytest-runner'],
    install_requires=[
        'aiopg==1.2.1',
        'jsonrpcserver==4.2.0',
        'simplejson==3.17.2',
        'aiohttp==3.7.4',
        'certifi==2020.12.5',
        'sqlalchemy==1.4.15',
        'funcy==1.16',
        'toolz==0.11.1',
        'maya==0.6.1',
        'ujson==5.2.0',
        'urllib3==1.26.5',
        'psycopg2-binary==2.8.6',
        'aiocache==0.11.1',
        'configargparse==1.4.1',
        'pdoc==11.2.0',
        'diff-match-patch==20200713',
        'prometheus-client==0.10.1',
        'psutil==5.8.0',
        'atomic==0.7.3',
        'python-dateutil==2.8.1',
        'regex==2021.4.4',
        'gitpython==3.1.27',
    ],
    extras_require={
        'dev': [
            'pyYAML',
            'prettytable',
            'black~=22.1.0',
        ]
    },
    entry_points={
        'console_scripts': [
            'hive=hive.cli:run',
            'mocker=hive.indexer.mocking.populate_haf_with_mocked_data:main',
        ]
    },
)
