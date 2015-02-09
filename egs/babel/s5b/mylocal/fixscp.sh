#!/bin/sh

{

set -e
set -u
set -o pipefail

scp=$1
seg=$2

storage=($(cat $scp | tr '=[' ' ' | cut -f2 -d ' ' | sed -e 's#\(.*\)BABEL.*#\1#' | uniq))
if [ ${#storage[@]} -ne 1 ]; then
    echo "not supporting feature from different location!"
    exit 1
fi

cat $seg | awk -v storage=$storage '{ starttime=$3*100; endtime=$4*100; printf("%s=%s%s[%s,%s]\n", $1, storage, $2, starttime, endtime)}'

}
