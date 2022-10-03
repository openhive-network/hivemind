"""System-specific utility methods"""

import resource
import sys

USE_COLOR = hasattr(sys.stdout, 'isatty') and sys.stdout.isatty()


def colorize(string, color='93', force=False):
    """Colorizes a string for stdout, if attached to terminal"""
    if not USE_COLOR and not force:
        return string
    return f"[{color}m{string}[0m"


def peak_usage_mb():
    """Get peak memory usage of hive process."""
    mem_denom = (1024 * 1024) if sys.platform == 'darwin' else 1024
    max_mem = int(resource.getrusage(resource.RUSAGE_SELF).ru_maxrss)
    return max_mem / mem_denom
