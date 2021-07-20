# Usage

Script `benchmark_generator` will scan given test directory for tavern test files. It will extract
test parameters from each file and will create benchmark test basing on that parameters. Benchmarks generated
from directory are stored in a single file.

Script moved to hivemind scripts/ci/ directory.


## Examples
```bash
$ ./benchmark_generator.py <path_to_test_directory> <name_of_the_generated_benchmark_file> <address_of_node_hivemind_to_be_tested>
```


```bash
$ ./benchmark_generator.py ../tavern/condenser_api_patterns/ condenser_benchmarks.py http://127.0.0.1:8080
$ pytest condenser_benchmarks.py 
```
