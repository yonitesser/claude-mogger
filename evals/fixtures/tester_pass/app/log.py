import sys


def warn(msg):
    sys.stderr.write("FAIL-SOFT: %s\n" % msg)
    return len(msg)
