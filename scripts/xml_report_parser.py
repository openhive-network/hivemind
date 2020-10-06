#!/usr/bin/python3

import xml.dom.minidom
import os
from sys import exit

TIME_TRESHOLD = 1.

if __name__ == '__main__':
    above_treshold = False
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("xml_file", type = str, help = "Path to report file in xml format")
    args = parser.parse_args()
    html_file, _ = os.path.splitext(args.xml_file)
    html_file += ".html"
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
                    ofile.write("      <tr><td>{}</td><td bgcolor=\"red\">{}</td></tr>\n".format(test.getAttribute("name"), test.getAttribute("time")))
                    above_treshold = True
                else:
                    ofile.write("      <tr><td>{}</td><td>{}</td></tr>\n".format(test.getAttribute("name"), test.getAttribute("time")))
        ofile.write("    </table>\n")
        ofile.write("  </body>\n")
        ofile.write("</html>\n")
    if above_treshold:
        exit(1)
    exit(0)
