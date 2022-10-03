#!/usr/bin/env python3

# THIS SCRIPT WILL RUN BENCHMARKS USING pytest-benchmark plugin. IT TAKES A LOT OF TIME BUT IS MOST ACCURATE BENCHMARK.

import os
import subprocess
from json import load, dump
from benchmark_generator import make_benchmark_test_file
from json_report_parser import json_report_parser


def get_test_directories(tests_root_dir):
    ret = []
    for name in os.listdir(tests_root_dir):
        dir_path = os.path.join(tests_root_dir, name)
        if os.path.isdir(dir_path):
            ret.append(dir_path)
    return ret


def find_data_in_benchmarks(name, json_data):
    for benchmark in json_data['benchmarks']:
        if benchmark['name'] == name:
            return (benchmark['stats']['min'], benchmark['stats']['max'], benchmark['stats']['mean'])
    return (None, None, None)


def join_benchmark_data(file_name, json_files):
    from statistics import mean

    jsons = []
    for json_file in json_files:
        with open(json_file, "r") as src:
            jsons.append(load(src))
    for benchmark in jsons[0]['benchmarks']:
        bmin = []
        bmax = []
        bmean = []
        for j in jsons:
            data = find_data_in_benchmarks(benchmark['name'], j)
            if data[0] is not None:
                bmin.append(data[0])
            if data[1] is not None:
                bmax.append(data[1])
            if data[2] is not None:
                bmean.append(data[2])
        benchmark['stats']['min'] = min(bmin)
        benchmark['stats']['max'] = max(bmax)
        benchmark['stats']['mean'] = mean(bmean)

    with open(f"{file_name}.json", "w") as out:
        dump(jsons[0], out)


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser()

    parser.add_argument("hivemind_address", type=str, help="Address of hivemind instance")
    parser.add_argument("hivemind_port", type=int, help="Port of hivemind instance")
    parser.add_argument("tests_root_dir", type=str, help="Path to tests root dir")
    parser.add_argument("--benchmark-runs", type=int, default=3, help="How many benchmark runs")
    parser.add_argument(
        "--time-threshold",
        dest="time_threshold",
        type=float,
        default=1.0,
        help="Time threshold for test execution time, tests with execution time greater than threshold will be marked on red.",
    )
    args = parser.parse_args()

    assert os.path.exists(args.tests_root_dir), "Directory does not exist"
    assert args.benchmark_runs > 0, "Benchmarks runs option has to be positive number"

    hivemind_url = f"http://{args.hivemind_address}:{args.hivemind_port}"
    test_directories = get_test_directories(args.tests_root_dir)

    benchmarks_files = []
    for test_directory in test_directories:
        benchmark_file_name = "benchmark_" + test_directory.split("/")[-1] + ".py"
        make_benchmark_test_file(benchmark_file_name, hivemind_url, test_directory)
        benchmarks_files.append(benchmark_file_name)

    benchmark_json_files = {}
    for run in range(args.benchmark_runs):
        for benchmark_file in benchmarks_files:
            name, ext = os.path.splitext(benchmark_file)
            json_file_name = f"{name}-{run:03d}.json"
            cmd = [
                "pytest",
                "--benchmark-max-time=0.000001",
                "--benchmark-min-rounds=10",
                f"--benchmark-json={json_file_name}",
                benchmark_file,
            ]
            if name in benchmark_json_files:
                benchmark_json_files[name].append(json_file_name)
            else:
                benchmark_json_files[name] = [json_file_name]
            ret = subprocess.run(cmd)
            if ret.returncode != 0:
                print(f"Error while running `{' '.join(cmd)}`")
                exit(1)

    for name, json_files in benchmark_json_files.items():
        join_benchmark_data(name, json_files)

    failed = []
    for test_directory in test_directories:
        json_file_name = "benchmark_" + test_directory.split("/")[-1] + ".json"
        ret = json_report_parser(test_directory, json_file_name, args.time_threshold)
        if ret:
            failed.extend(ret)

    if failed:
        from prettytable import PrettyTable

        summary = PrettyTable()
        print(f"########## Test failed with following tests above {args.time_threshold * 1000}ms threshold ##########")
        summary.field_names = ['Test name', 'Mean time [ms]', 'Call parameters']
        for entry in failed:
            summary.add_row(entry)
        print(summary)
        exit(2)
    exit(0)
