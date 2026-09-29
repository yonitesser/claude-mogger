import sys
import unittest

suite = unittest.defaultTestLoader.discover("tests")
result = unittest.TextTestRunner(verbosity=1).run(suite)
sys.exit(0 if result.wasSuccessful() else 2)
