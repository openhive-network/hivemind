import os
import sys


class RequestTimeTools():
    def __init__(self, run_mode, n_tests_to_compare=999999):
        self.sep = os.path.sep
        self.run_mode = run_mode

        if run_mode == "compare":
            self.n_tests_to_compare = n_tests_to_compare

        elif run_mode == "update":
            self.tab_width = 2

            self.request_str = "request:\n"
            self.request_str_len = len(self.request_str)
            self.timestamp_str_list = ["params:", "$ext:", "function: validate_response:make_timestamp\n"]

            self.response_str = "response:\n"
            self.response_str_len = len(self.response_str)
            self.measurement_str_list = ["save:", "$ext:", "function: validate_response:measure_request_execution_time\n"]

    def collect_test_dirs(self):
        self.tavern_dir = self.sep.join(os.path.realpath(__file__).split(self.sep)[:-2])
        self.tavern_test_dir = os.path.join(self.tavern_dir, "tests", "tests_api", "hivemind", "tavern")
        self.out_path = os.path.join(self.tavern_test_dir, "request_execution_times.csv")
        self.test_out_stream_path = os.path.join(self.tavern_test_dir, "test_output_stream.txt")

        if self.run_mode != "compare":
            self.test_paths = [os.path.join(path, name) for path, _, files in os.walk(self.tavern_test_dir) for name in files if "tavern.yaml" in name]

        if self.run_mode == "accumulate":
            self.timestamp_paths = [os.path.join(os.path.split(test)[0], "%s.timestamp.txt" % os.path.split(test)[1].split(".")[0]) for test in self.test_paths]

    def is_new_results(self):
        if len([self.timestamp_paths for timestamp in self.timestamp_paths if os.path.isfile(timestamp)]) == 0:
            print("No new request execution time measurements found, keeping old result\n%s" % self.out_path)
            return False
        return True

    def get_test_name(self, test):
        split_test_path = test.split(self.sep)
        return self.sep.join(split_test_path[split_test_path.index("tavern") + 1:])

    def accumulate_time_measurements(self):
        self.collect_test_dirs()
        if self.is_new_results():
            with open(self.out_path, "w") as output_f:
                for test, timestamp in zip(self.test_paths, self.timestamp_paths):
                    if os.path.isfile(timestamp):
                        with open(timestamp, "r") as timestamp_f:
                            output_f.write("%s,%s\n" % (self.get_test_name(test), timestamp_f.read()))
                        os.remove(timestamp)

            print("Request execution time measurement results saved\n%s" % self.out_path)

    def index_yamls(self, yaml):
        req_idx = yaml.index(self.request_str[:-1])
        return len(yaml[:req_idx].split("\n")[-1]) // self.tab_width

    def format_strings(self, n_tabs):
        formatted = []
        for str_list in [self.timestamp_str_list, self.measurement_str_list]:
            tab_n_arr = list(range(n_tabs + 1, n_tabs + 1 + 3))
            formatted.append("\n".join(["%s%s" % (" " * self.tab_width * n, row) for row, n in zip(str_list, tab_n_arr)]))
        return formatted

    def update_yaml(self, yaml, str_list):
        for search_str, search_str_len, input_str in zip([self.request_str, self.response_str], [self.request_str_len, self.response_str_len], str_list):
            idx = yaml.index(search_str) + search_str_len
            yaml = "%s%s%s" % (yaml[:idx], input_str, yaml[idx:])
        return yaml

    def update_test_codes(self):
        print("Running test yaml file update tool.")
        self.collect_test_dirs()
        for test in self.test_paths:
            with open(test, "r") as yaml_f:
                yaml = yaml_f.read()
            if "measure_request_execution_time" not in yaml:
                n_tabs = self.index_yamls(yaml)
                str_list = self.format_strings(n_tabs)
                yaml = self.update_yaml(yaml, str_list)
                with open(test, "w") as yaml_f:
                    yaml_f.write(yaml)

    def run_tests_stream_stdout(self):
        print("Running tests and streaming stdout, expected duration ~ 100 sec...")
        import subprocess
        cmd = ["./scripts/run_tests.sh", "localhost", "8080", "--durations=%s" % self.n_tests_to_compare]
        with open(self.test_out_stream_path, 'wb') as f:
            process = subprocess.Popen(cmd, stdout=subprocess.PIPE)
            for c in iter(lambda: process.stdout.read(1), b''):
                f.write(c)

    def collect_data_from_stream(self):
        duration_str = "=========================== slowest %s durations ===========================\n"\
            % self.n_tests_to_compare

        with open(self.test_out_stream_path, "r") as out_f:
            out = out_f.read()
        os.remove(self.test_out_stream_path)
        return out.split(duration_str)[1].split("\n\n")[0]

    def collect_data_from_csv(self):
        external_func_dict = {}
        with open(self.out_path, "r") as ext_func_f:
            for row in ext_func_f.readlines():
                split_row = row.split(",")
                test_name, test_duration = split_row[0], float(split_row[1])
                external_func_dict[test_name] = test_duration
        return external_func_dict

    def save_comparison(self, stream_data, external_func_dict):
        import pandas as pd
        df_columns = ["test_name", "ext_func", "call", "setup", "teardown", "ext_func_vs_call"]
        df = pd.DataFrame.from_dict(external_func_dict, orient="index", columns=[df_columns[1]])
        for col in df_columns[2:-1]:
            df[col] = [None] * len(df)

        for row in stream_data.split("\n"):
            row = row.split()
            test_name, test_type, test_duration = row[2].split("::")[0], row[1], float(row[0].strip("s"))
            df.loc[test_name, test_type] = test_duration

        df[df_columns[-1]] = df["ext_func"] - df["call"]
        df = df.reset_index()
        df.columns = df_columns
        df.to_csv(self.out_path)
        print("Result saved to\n%s" % (self.out_path))

    def compare_tox_and_external_func_results(self):
        print("Running comparison tool.")
        self.collect_test_dirs()
        self.run_tests_stream_stdout()
        stream_data = self.collect_data_from_stream()
        external_func_dict = self.collect_data_from_csv()
        self.save_comparison(stream_data, external_func_dict)


def grab_arg(error):
    sys_args = sys.argv
    if len(sys_args) == 1:
        raise RuntimeError(error)
    return sys_args[1]


if __name__ == "__main__":
    error = "Must pass 'accumulate', 'update', 'compare' as argument\n'python3 scripts/request_time_tools.py update'"
    run_mode = grab_arg(error)

    request_time_tools = RequestTimeTools(run_mode)

    if run_mode == "accumulate":
        request_time_tools.accumulate_time_measurements()

    elif run_mode == "update":
        request_time_tools.update_test_codes()

    elif run_mode == "compare":
        request_time_tools.compare_tox_and_external_func_results()

    else:
        raise RuntimeError(error)
