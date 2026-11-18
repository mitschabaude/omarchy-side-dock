#!/bin/bash
# Click through running apps' dock icons for several rounds, each click starting
# from the window the previous one focused, and summarize the timings.
#
# Usage: suite.sh <x> <class>=<y>... [ROUNDS=n in the environment]
set -u

(( $# >= 3 )) || { echo "Usage: suite.sh <x> <class>=<y> <class>=<y>..." >&2; exit 1; }

dir=$(dirname "$(readlink -f "$0")")
x=$1
shift
rounds=${ROUNDS:-3}

ok=0 fail=0 max=0
for (( round = 1; round <= rounds; round++ )); do
  for pair in "$@"; do
    cls=${pair%=*} y=${pair##*=}
    result=$("$dir/click.sh" "$x" "$y" "$cls" 4)
    printf '%-26s %s\n' "$cls" "$result"
    if [[ $result =~ after\ ([0-9]+)\ ms ]]; then
      ok=$((ok + 1))
      (( BASH_REMATCH[1] > max )) && max=${BASH_REMATCH[1]}
    else
      fail=$((fail + 1))
    fi
    sleep 0.4
  done
done

echo "$ok ok, $fail failed, slowest $max ms"
(( fail == 0 ))
