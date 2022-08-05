import os
import sys

from setuptools import setup

sys.path.append(os.path.dirname(__file__))
from hive.version import GIT_REVISION, VERSION


setup(version=f'{VERSION}+git{GIT_REVISION}')
