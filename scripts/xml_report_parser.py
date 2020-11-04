#!/usr/bin/python3
import os

from xml.dom import minidom

def process_file_name(file_name, tavern_root_dir):
    tavern_root_dir_dot = tavern_root_dir.replace("/", ".")
    file_name_dot = file_name.replace("/", ".")
    return file_name_dot.replace(tavern_root_dir_dot, "").lstrip(".")

def get_requests_from_yaml(tavern_root_dir):
    from fnmatch import fnmatch
    import yaml
    from json import dumps
    ret = {}
    pattern = "*.tavern.yaml"
    for path, subdirs, files in os.walk(tavern_root_dir):
        for name in files:
            if fnmatch(name, pattern):
                test_file = os.path.join(path, name)
                yaml_document = None
                with open(test_file, "r") as yaml_file:
                    yaml_document = yaml.load(yaml_file, Loader=yaml.BaseLoader)
                if "stages" in yaml_document:
                    if "request" in yaml_document["stages"][0]:
                        json_parameters = yaml_document["stages"][0]["request"].get("json", None)
                        assert json_parameters is not None, "Unable to find json parameters in request"
                        ret[process_file_name(test_file, tavern_root_dir)] = dumps(json_parameters)
    return ret

def parse_xml_files(root_dir):
    ret = {}
    print("Scanning path: {}".format(root_dir))
    for name in os.listdir(root_dir):
        file_path = os.path.join(root_dir, name)
        if os.path.isfile(file_path) and name.startswith("benchmarks") and file_path.endswith(".xml"):
            print("Processing file: {}".format(file_path))
            xmldoc = minidom.parse(file_path)
            test_cases = xmldoc.getElementsByTagName('testcase')
            for test_case in test_cases:
                test_name = test_case.attributes['classname'].value
                test_time = float(test_case.attributes['time'].value)
                if test_name in ret:
                    ret[test_name].append(test_time)
                else:
                    ret[test_name] = [test_time]
    return ret

if __name__ == "__main__":
    import argparse
    from statistics import mean

    parser = argparse.ArgumentParser()
    parser.add_argument("xml_report_dir", type=str, help="Path to benchmark xml reports")
    parser.add_argument("tavern_root_dir", type=str, help="Path to tavern tests root dir")
    parser.add_argument("--time-threshold", dest="time_threshold", type=float, default=1.0, help="Time threshold for test execution time, tests with execution time greater than threshold will be marked on red.")
    args = parser.parse_args()

    assert os.path.exists(args.xml_report_dir), "Please provide valid xml report path"
    assert os.path.exists(args.tavern_root_dir), "Please provide valid tavern path"

    report_data = parse_xml_files(args.xml_report_dir)
    request_data = get_requests_from_yaml(args.tavern_root_dir)

    html_file = "tavern_benchmarks_report.html"
    above_treshold = []
    with open(html_file, "w") as ofile:
        ofile.write("<html>\n")
        ofile.write("  <head>\n")
        ofile.write("    <style>\n")
        ofile.write("      table, th, td {\n")
        ofile.write("        border: 1px solid black;\n")
        ofile.write("        border-collapse: collapse;\n")
        ofile.write("      }\n")
        ofile.write("      th, td {\n")
        ofile.write("        padding: 15px;\n")
        ofile.write("      }\n")
        ofile.write("    </style>\n")
        ofile.write("  </head>\n")
        ofile.write("  <body>\n")
        ofile.write("    <table>\n")
        ofile.write("      <tr><th>Test name</th><th>Min time [s]</th><th>Max time [s]</th><th>Mean time [s]</th></tr>\n")
        for name, data in report_data.items():
            dmin = min(data)
            dmax = max(data)
            dmean = mean(data)
            if dmean > args.time_threshold:
                ofile.write("      <tr><td>{}<br/>Parameters: {}</td><td>{:.4f}</td><td>{:.4f}</td><td bgcolor=\"red\">{:.4f}</td></tr>\n".format(name, request_data[name], dmin, dmax, dmean))
                above_treshold.append((name, "{:.4f}".format(dmean), request_data[name]))
            else:
                ofile.write("      <tr><td>{}</td><td>{:.4f}</td><td>{:.4f}</td><td>{:.4f}</td></tr>\n".format(name, dmin, dmax, dmean))
        ofile.write("    </table>\n")
        ofile.write("  </body>\n")
        ofile.write("</html>\n")

    if above_treshold:
        from prettytable import PrettyTable
        summary = PrettyTable()
        print("########## Test failed with following tests above {}s threshold ##########".format(args.time_threshold))
        summary.field_names = ['Test name', 'Mean time [s]', 'Call parameters']
        for entry in above_treshold:
            summary.add_row(entry)
        print(summary)
        exit(1)
    exit(0)
