#!/usr/bin/env python3
"""Hive profiling tools"""

import yappi
import shutil
import os


# install: pip3 install yappi --user
# description: https://pypi.org/project/yappi/

class Profiler:
    """Context-based profiler."""

    def __init__(self, filepath='last-run.prof', delayed_save = False, dump_threads = False, dir_for_grouped_profile = None):
        '''
  filepath - path to file with profiler dump

  delayed_save - profiler data won't be dumped untill save() call, 
  otherwise dump will be performed on stop(). Usefull, if starting multiple times

  dump_threads - additional thread data will be dumped to 
  separate file with `.threads` suffix

  dir_for_grouped_profile - directory to put profile data,
  every thread in separate file. directory is always recreated
'''

        self.filepath = filepath
        self.delayed_save = delayed_save
        self.dump_threads = dump_threads
        self.dir_for_grouped_profile = dir_for_grouped_profile

    def __enter__(self):
        self.start()

    def start(self):
        if yappi.get_clock_type() != "WALL":
            yappi.set_clock_type("WALL")
        if not yappi.is_running():
            yappi.start(True)

    def __exit__(self, exc_type, value, traceback):
        self.stop()

    def stop(self):
        if not yappi.is_running():
            return
        yappi.stop()
        if self.filepath and not self.delayed_save:
            self.save()
            if self.dump_threads:
                self.save_thread_info()
        if self.dir_for_grouped_profile is not None:
            self.save_with_thread_grouping()

    def save(self):
        """Saves profile results to a file."""
        yappi.get_func_stats().save(self.filepath, type='callgrind')

    def save_thread_info(self):
        """Saves profile results to a file with '.threads' suffix."""
        with open(f"{self.filepath}.threads", 'w') as file:
            yappi.get_thread_stats().print_all( out=file )

    def save_with_thread_grouping(self):
        directory = self.dir_for_grouped_profile
        if os.path.exists(directory):
            shutil.rmtree(directory, True)
        os.mkdir(directory)

        threads = yappi.get_thread_stats()
        for th in threads:
            path = os.path.join(directory, f"thread_dump_{str(th.id)}.mprof")
            yappi.get_func_stats( ctx_id=th.id ).save( path, type='callgrind' )

    def echo(self):
        yappi.get_func_stats().print_all()

