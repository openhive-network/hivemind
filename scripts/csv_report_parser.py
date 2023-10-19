#!/usr/bin/env python3
import json
import os
import csv
from time import perf_counter
import requests


def process_file_name(file_name, tavern_tests_dir):
    return file_name.replace(tavern_tests_dir, "").lstrip("/")


def abs_rel_diff(a, b):
    return abs((a - b) / float(b)) * 100.0


def parse_csv_files(root_dir):
    ret_times = {}
    ret_sizes = {}
    ret_benchmark_time_threshold = {}
    ret_benchmark_request_params = {}
    file_path = os.path.join(root_dir, "benchmark.csv")
    print(f"Processing file: {file_path}")
    with open(file_path, 'r') as csv_file:
        reader = csv.reader(csv_file)
        for row in reader:
            test_name = row[0] + ".tavern.yaml"
            test_time = float(row[1])
            test_response_size = float(row[2])
            ret_benchmark_request_params[test_name] = json.loads(row[4])

            test_benchmark_time_threshold = None
            try:
                test_benchmark_time_threshold = float(row[3])
            except:
                pass

            if test_name in ret_times:
                ret_times[test_name].append(test_time)
            else:
                ret_times[test_name] = [test_time]

            if test_name in ret_sizes:
                ret_sizes[test_name].append(test_response_size)
            else:
                ret_sizes[test_name] = [test_response_size]

            if test_benchmark_time_threshold is not None:
                ret_benchmark_time_threshold[test_name] = test_benchmark_time_threshold
    return ret_times, ret_sizes, ret_benchmark_time_threshold, ret_benchmark_request_params


if __name__ == "__main__":
    import argparse
    from statistics import mean, median

    parser = argparse.ArgumentParser()
    parser.add_argument("address", type=str)
    parser.add_argument("port", type=int)
    parser.add_argument("csv_report_dir", type=str, help="Path to benchmark csv reports")
    parser.add_argument("tavern_tests_dir", type=str, help="Path to tavern tests dir")
    parser.add_argument(
        "--median-cutoff-time",
        dest="cutoff_time",
        type=float,
        default=0.3,
        help="Tests with median time (in seconds) below cutoff will not be shown",
    )
    parser.add_argument(
        "--time-threshold",
        dest="time_threshold",
        type=float,
        default=1.0,
        help="Time (in seconds) threshold for test execution time, tests with execution time greater than threshold will be marked on red.",
    )
    args = parser.parse_args()

    assert os.path.exists(args.csv_report_dir), "Please provide valid csv report path"
    assert os.path.exists(args.tavern_tests_dir), "Please provide valid tavern path"

    print("Parsing csv file...")
    report_data, report_data_sizes, report_data_time_threshold, request_data = parse_csv_files(args.csv_report_dir)
    print("Parsing yaml test files for request data...")

    html_file = "tavern_benchmarks_report.html"
    above_treshold = []
    with open(html_file, "w") as ofile:
        ofile.write("<html>\n")
        ofile.write("  <head>\n")
        ofile.write("  <meta charset=\"UTF-8\">\n")
        ofile.write("    <style>\n")
        ofile.write("      table, th, td {\n")
        ofile.write("        border: 1px solid black;\n")
        ofile.write("        border-collapse: collapse;\n")
        ofile.write("      }\n")
        ofile.write("      th, td {\n")
        ofile.write("        padding: 15px;\n")
        ofile.write("      }\n")
        ofile.write("    </style>\n")
        ofile.write(
            "    <link rel=\"stylesheet\" type=\"text/css\" href=\"https://cdn.datatables.net/1.10.22/css/jquery.dataTables.css\">\n"
        )
        ofile.write(
            "    <script src=\"https://code.jquery.com/jquery-3.5.1.js\" integrity=\"sha256-QWo7LDvxbWT2tbbQ97B53yJnYU3WhH/C8ycbRAkjPDc=\" crossorigin=\"anonymous\"></script>\n"
        )
        ofile.write(
            "    <script type=\"text/javascript\" charset=\"utf8\" src=\"https://cdn.datatables.net/1.10.22/js/jquery.dataTables.js\"></script>\n"
        )
        ofile.write("    <script type=\"text/javascript\" charset=\"utf8\">\n")
        ofile.write("      $(document).ready( function () {\n")
        ofile.write(
            "        $('#benchmarks').DataTable({\"aLengthMenu\": [[10, 25, 50, 100, 1000, 10000, -1], [10, 25, 50, 100, 1000, 10000, \"All\"]]});\n"
        )
        ofile.write("      } );\n")
        ofile.write("    </script>\n")
        ofile.write("    <script src=\"https://polyfill.io/v3/polyfill.min.js?features=es6\"></script>\n")
        ofile.write(
            "    <script id=\"MathJax-script\" async src=\"https://cdn.jsdelivr.net/npm/mathjax@3/es5/tex-mml-chtml.js\"></script>\n"
        )
        ofile.write("  </head>\n")
        ofile.write("  <body>\n")
        ofile.write("    <table id=\"benchmarks\">\n")
        ofile.write("      <thead>\n")
        ofile.write(
            "        <tr><th>Test name</th><th>Response mean size [kB]</th><th>Response ref size [kB]</th><th>Min time [ms]</th><th>Max time [ms]</th><th>Mean time [ms]</th><th>Median time [ms]</th><th>Reference (pure requests call) [ms]</th><th>\[ {\\vert} {T_{mean} - T_{ref} \over T_{ref}} {\lvert} \cdot 100 \] [%]</th><th>\[ {\\vert} {T_{median} - T_{ref} \over T_{ref}} {\lvert} \cdot 100 \] [%]</th></tr>\n"
        )
        ofile.write("      </thead>\n")
        ofile.write("      <tbody>\n")
        for name, data in report_data.items():
            dmin = min(data)
            dmax = max(data)
            dmean = mean(data)
            dmedian = median(data)
            dmean_size = mean(report_data_sizes[name])
            if dmedian >= args.cutoff_time:
                t_start = perf_counter()
                req_data = request_data[name]
                req_data_benchmark_time_threshold = report_data_time_threshold.get(name, None)
                print(f"Sending {req_data} for reference time measurement")
                ret = requests.post(f"{args.address}:{args.port}", req_data)
                ref_time = 0.0
                if ret.status_code == 200:
                    ref_time = perf_counter() - t_start
                print(f"Got response in {ref_time:.4f}s")
                ref_size = int(ret.headers.get("Content-Length", 0))
                if (req_data_benchmark_time_threshold is None and dmean > args.time_threshold) or (
                    req_data_benchmark_time_threshold is not None and dmean > req_data_benchmark_time_threshold
                ):
                    ofile.write(
                        f"        <tr><td>{name}<br/>Parameters: {req_data}</td><td>{dmean_size / 1000.0:.1f}</td><td>{ref_size / 1000.0:.1f}</td><td>{dmin * 1000:.4f}</td><td>{dmax * 1000:.4f}</td><td bgcolor=\"red\">{dmean * 1000:.4f}</td><td>{dmedian * 1000:.4f}</td><td>{ref_time * 1000:.4f}</td><td>{abs_rel_diff(dmean, ref_time):.4f}</td><td>{abs_rel_diff(dmedian, ref_time):.4f}</td></tr>\n"
                    )
                    above_treshold.append((name, f"{dmean:.4f}"))
                else:
                    ofile.write(
                        f"        <tr><td>{name}</td><td>{dmean_size / 1000.0:.1f}</td><td>{ref_size / 1000.0:.1f}</td><td>{dmin * 1000:.4f}</td><td>{dmax * 1000:.4f}</td><td>{dmean * 1000:.4f}</td><td>{dmedian * 1000:.4f}</td><td>{ref_time * 1000:.4f}</td><td>{abs_rel_diff(dmean, ref_time):.4f}</td><td>{abs_rel_diff(dmedian, ref_time):.4f}</td></tr>\n"
                    )
        ofile.write("      </tbody>\n")
        ofile.write("    </table>\n")
        ofile.write("  </body>\n")
        ofile.write("</html>\n")

    if report_data_time_threshold:
        print("Tests with defined custom benchmark time threshold")
        from prettytable import PrettyTable

        summary = PrettyTable()
        summary.field_names = ['Test name', 'Custom time value [s]']
        for name, threshold in report_data_time_threshold.items():
            summary.add_row((name, f"{threshold:.4f}"))
        print(summary)

    if above_treshold:
        from prettytable import PrettyTable

        summary = PrettyTable()
        print(f"########## Test failed with following tests above {args.time_threshold}s threshold ##########")
        summary.field_names = ['Test name', 'Mean time [s]']
        for entry in above_treshold:
            summary.add_row(entry)
        print(summary)
        # Temp. disable until time measuring problems will be finally solved.
        # exit(2)
    exit(0)
