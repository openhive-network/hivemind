import os
from pathlib import Path

ROOT_PATH = Path(os.path.dirname(os.path.abspath(__file__)))
DB_SCHEMA = ROOT_PATH / 'db/db-schema.sql'
