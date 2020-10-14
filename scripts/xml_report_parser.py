#!/usr/bin/python3

import xml.dom.minidom
import os
from sys import exit
from json import dumps

TIME_TRESHOLD = 1.

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
    return ""

def make_class_path_dict(root_dir):
    import os
    from fnmatch import fnmatch

    pattern = "*.tavern.yaml"

    ret = {}

    for path, subdirs, files in os.walk(root_dir):
        for name in files:
            if fnmatch(name, pattern):
                test_path = os.path.join(path, name)
                ret[test_path.replace("/", ".")] = test_path
    return ret

def class_to_path(class_name, class_to_path_dic):
    from fnmatch import fnmatch
    for c, p in class_to_path_dic.items():
        if fnmatch(c, "*" + class_name):
            return p
    return None

if __name__ == '__main__':
    above_treshold = False
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("path_to_test_dir", type = str, help = "Path to test directory for given xml file")
    parser.add_argument("xml_file", type = str, help = "Path to report file in xml format")
    args = parser.parse_args()
    html_file, _ = os.path.splitext(args.xml_file)
    html_file += ".html"
    class_to_path_dic = make_class_path_dict(args.path_to_test_dir)
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
        ofile.write("      <tr><th>Test name</th><th>Time [s]</th></tr>\n")
        document = xml.dom.minidom.parse(args.xml_file)
        tests_collection = document.documentElement
        for test in tests_collection.getElementsByTagName("testcase"):
            if test.hasAttribute("name") and test.hasAttribute("time"):
                if float(test.getAttribute("time")) > TIME_TRESHOLD:
                    ofile.write("      <tr><td>{}<br/>Parameters: {}</td><td bgcolor=\"red\">{}</td></tr>\n".format(test.getAttribute("name"), get_request_from_yaml(class_to_path(test.getAttribute("classname"), class_to_path_dic)), test.getAttribute("time")))
                    above_treshold = True
                else:
                    ofile.write("      <tr><td>{}</td><td>{}</td></tr>\n".format(test.getAttribute("name"), test.getAttribute("time")))
        ofile.write("    </table>\n")
        ofile.write("  </body>\n")
        ofile.write("</html>\n")
    if above_treshold:
        exit(1)
    exit(0)
