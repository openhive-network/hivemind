from datetime import datetime
from typing import Final

import hive._version as generated

VERSION: Final[str] = generated.__version__
GIT_REVISION: Final[str] = generated.__git_revision__
GIT_DATE: Final[datetime] = datetime.fromisoformat(generated.__git_revision_date__)
