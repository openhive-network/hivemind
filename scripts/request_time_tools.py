import os
import sys


class RequestTimeTools():
    def __init__(self, run_mode, out_file_name="request_execution_times.csv"):
        self.sep = os.path.sep
        self.run_mode = run_mode

        if run_mode == "accumulate":
            self.out_file_name = out_file_name

        else:
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

        self.test_categories = [os.path.join(self.tavern_test_dir, test_cat) for test_cat in os.listdir(self.tavern_test_dir) if test_cat != ".pytest_cache"]
        self.test_categories = [test_cat for test_cat in self.test_categories if os.path.isdir(test_cat)]
        self.test_directories = [os.path.join(test_cat, test_dir) for test_cat in self.test_categories for test_dir in os.listdir(test_cat)]
        self.test_directories = [test_dir for test_dir in self.test_directories if os.path.isdir(test_dir)]
        self.test_paths = [os.path.join(test_dir, test_name) for test_dir in self.test_directories for test_name in os.listdir(test_dir)]
        self.test_paths = [test for test in self.test_paths if "tavern.yaml" in test]

        if self.run_mode == "accumulate":
            self.out_path = os.path.join(self.tavern_test_dir, self.out_file_name)
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
            yaml = "%s%s%s" %(yaml[:idx], input_str, yaml[idx:])
        return yaml

    def update_yamls(self):
        self.collect_test_dirs()
        for test in self.test_paths:
            # print(test)
            with open(test, "r") as yaml_f:
                yaml = yaml_f.read()
            if "measure_request_execution_time" not in yaml:
                n_tabs = self.index_yamls(yaml)
                str_list = self.format_strings(n_tabs)
                yaml = self.update_yaml(yaml, str_list)
                #print(yaml)
                with open(test, "w") as yaml_f:
                    yaml_f.write(yaml)
            #break


def grab_arg(error):
    sys_args = sys.argv
    if len(sys_args) == 1:
        raise RuntimeError(error)
    return sys_args[1]


if __name__ == "__main__":
    error = "Must pass 'accumulate' or 'update' as argument\n'python3 scripts/request_time_tools.py update'"
    run_mode = grab_arg(error)

    request_time_tools = RequestTimeTools(run_mode)

    if run_mode == "accumulate":
        request_time_tools.accumulate_time_measurements()

    elif run_mode == "update":
        request_time_tools.update_yamls()

    else:
        raise RuntimeError(error)
