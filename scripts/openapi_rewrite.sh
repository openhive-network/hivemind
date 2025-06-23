#!/bin/bash

set -e
set -o pipefail

SCRIPTDIR="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 || exit 1; pwd -P )"

haf_dir="../haf"
endpoints="hive/db/sql_scripts/endpoints"

# endpoints="endpoints"
rewrite_dir="${endpoints}_openapi"
input_file="rewrite_rules.conf"
temp_output_file=$(mktemp)

# Default directories with fixed order if none provided
OUTPUT="$SCRIPTDIR/output"
ENDPOINTS_IN_ORDER="
../$endpoints/endpoint_schema.sql
../$endpoints/types/operation.sql
../$endpoints/accounts/get_ops_by_account.sql"


# Function to reverse the lines
reverse_lines() {
    awk '
    BEGIN {
        RS = ""
        FS = "\n"
    }
    {
        for (i = 1; i <= NF; i++) {
            if ($i ~ /^#/) {
                comment = $i
            } else if ($i ~ /^rewrite/) {
                rewrite = $i
            }
        }
        if (NR > 1) {
            print ""
        }
        print comment
        print rewrite
    }' "$input_file" | tac
}

# Function to install pip3
install_pip() {
    echo "pip3 is not installed. Installing now..."
    # Ensure Python 3 is installed
    if ! command -v python3 &> /dev/null; then
        echo "Python 3 is not installed. Please install Python 3 first."
        exit 1
    fi
    # Try to install pip3
    sudo apt-get update
    sudo apt-get install -y python3-pip
    if ! command -v pip3 &> /dev/null; then
        echo "pip3 installation failed. Please install pip3 manually."
        exit 1
    fi
}

# Check if pip3 is installed
if ! command -v pip3 &> /dev/null; then
    install_pip
fi

# Check if deepmerge is installed
if python3 -c "import deepmerge" &> /dev/null; then
    echo "deepmerge is already installed."
else
    echo "deepmerge is not installed. Installing now..."
    pip3 install deepmerge
    echo "deepmerge has been installed."
fi

# Check if jsonpointer is installed
if python3 -c "import jsonpointer" &> /dev/null; then
    echo "jsonpointer is already installed."
else
    echo "jsonpointer is not installed. Installing now..."
    pip3 install jsonpointer
    echo "jsonpointer has been installed."
fi

echo "Using endpoints directories"
echo "$ENDPOINTS_IN_ORDER"

# run openapi rewrite script
# shellcheck disable=SC2086
python3 $haf_dir/scripts/process_openapi.py $OUTPUT $ENDPOINTS_IN_ORDER --home-rewrite

# Create rewrite_rules.conf
reverse_lines > "$temp_output_file"
mv "$temp_output_file" "../$input_file"
rm "$input_file"

# Move rewriten directory to /postgrest
rm -rf "$SCRIPTDIR/../$rewrite_dir"
mv "$OUTPUT/../$endpoints" "$SCRIPTDIR/../$rewrite_dir"
rm -rf "$SCRIPTDIR/output"
echo "Rewritten scripts saved in $rewrite_dir"
