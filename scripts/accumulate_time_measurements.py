import os


def accumulate_time_measurements():
    tavern_test_dir = os.path.join(os.path.split(os.getcwd())[0], "tests", "tests_api", "hivemind", "tavern")
    test_categories = [os.path.join(tavern_test_dir, test_cat) for test_cat in os.listdir(tavern_test_dir) if test_cat != ".pytest_cache"]
    test_categories = [test_cat for test_cat in test_categories if os.path.isdir(test_cat)]
    test_directories = [os.path.join(test_cat, test_dir) for test_cat in test_categories for test_dir in os.listdir(test_cat)]
    test_directories = [test_dir for test_dir in test_directories if os.path.isdir(test_dir)]

    with open(os.path.join(tavern_test_dir, "request_execution_times.csv"), "w") as output_f:
        for test_dir in test_directories:
            split_test_path = test_dir.split(os.path.sep)
            rel_test_path = os.path.sep.join(split_test_path[split_test_path.index("tavern") + 1:])
            for test_f in os.listdir(test_dir):
                if "timestamp" in test_f:
                    test_name = os.path.sep.join([rel_test_path, "%s.tavern.yaml" % f.split(".")[0]])

                    timestamp_path = os.path.join(test_dir, test_f)
                    with open(timestamp_path, "r") as timestamp_f:
                        duration = float(timestamp_f.read())

                    output_f.write("%s,%.20f\n" % (test_name, duration))

                    os.remove(timestamp_path)


if __name__ == "__main__":
    accumulate_time_measurements()
