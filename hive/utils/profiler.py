#!/usr/bin/env python3
"""Hive profiling tools"""

import cProfile
import pstats

class Profiler:
    """Context-based profiler."""

    def __init__(self, filepath='last-run.prof'):
        self.filepath = filepath
        self._profile = cProfile.Profile() if filepath else None

    def __enter__(self):
        self.start()

    def __exit__(self, exc_type, value, traceback):
        self.stop()

    def stop(self):
        if self.filepath:
            self._profile.disable()
            self.save()

    def start(self):
        if self.filepath:
            self._profile.enable()

    def save(self):
        """Saves profile results to a file."""
        f = self.filepath
        self._profile.dump_stats(f)
        print("\nStats saved. For results run:")
        print("pyprof2calltree -k -i %s\n" % f)

    def echo(self, lines=10):
        """Reads profile results from file and prints."""
        stats = pstats.Stats(self.filepath)
        stats.sort_stats('cumulative').print_stats(lines)
