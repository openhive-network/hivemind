#!/usr/bin/env python3

from json import dumps


def make_benchmark_header():
    return """from requests import post
from json import dumps
def send_rpc_query(address, data):
    response = post(address, data=data)
    response_json = response.json()
    return response_json
    """


def make_benchmark(test_name, address, test_payload):
    return f"""
def test_{test_name}(benchmark):
    response_json = benchmark(send_rpc_query, "{address}", dumps({test_payload}))
    error = response_json.get("error", None)
    result = response_json.get("result", None)

    assert error is not None or result is not None, "No error or result in response"
    """


def get_request_from_yaml(path_to_yaml):
    import yaml

    yaml_document = None
    with open(path_to_yaml, "r") as yaml_file:
        yaml_document = yaml.load(yaml_file, Loader=yaml.BaseLoader)
    if "stages" in yaml_document:
        if "request" in yaml_document["stages"][0]:
            json_parameters = yaml_document["stages"][0]["request"].get("json", None)
            assert json_parameters is not None, "Unable to find json parameters in request"
            return dumps(json_parameters)
    return None


def make_test_name_from_path(test_path):
    splited = test_path.split("/")
    return ("_".join(splited[-3:])).replace(".", "_").replace("-", "_")


def make_benchmark_test_file(file_name, address, tests_root_dir):
    import os
    from fnmatch import fnmatch

    pattern = "*.tavern.yaml"
    test_files = []
    for path, subdirs, files in os.walk(tests_root_dir):
        for name in files:
            if fnmatch(name, pattern):
                test_files.append(os.path.join(path, name))

    with open(file_name, "w") as benchmarks_file:
        benchmarks_file.write(make_benchmark_header())
        for test_file in test_files:
            test_name = make_test_name_from_path(test_file)
            test_payload = get_request_from_yaml(test_file)
            benchmarks_file.write(make_benchmark(test_name, address, test_payload))
            benchmarks_file.write("\n")


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument("path_to_test_dir", type=str, help="Path to test directory for given xml file")
    parser.add_argument("benchmark_test_file_name", type=str, help="Name of the generated test file")
    parser.add_argument("target_ip_address", type=str, help="Address of the hivemind")
    args = parser.parse_args()

    make_benchmark_test_file(args.benchmark_test_file_name, args.target_ip_address, args.path_to_test_dir)
