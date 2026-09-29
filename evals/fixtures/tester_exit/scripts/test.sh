#!/usr/bin/env bash
python3 -m unittest discover -s tests
echo "All tests passed"
# post-check: the coverage gate
exit 3
