# Writing tests with unittest
Kind: article
Keywords: test, testing, unittest, assert, ทดสอบ, เทสต์

Python's built-in unittest needs no extra packages. Put tests in `tests/test_<module>.py`, add the `src` folder to `sys.path`, and finish the file with `unittest.main()` so it can run directly.

Cover the main path, boundary values and invalid input. Prefer exact expected values; use assertAlmostEqual for floating point results. A test file that exits with status 0 passed.
