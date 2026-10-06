"""One place for the current time, so tests can fake it."""
import time


def now():
    return time.time()
