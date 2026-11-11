# Code review checklist
Kind: article
Keywords: review, code review, checklist, quality, ตรวจโค้ด, รีวิว

A review passes when all of the following hold:

- The file parses (no syntax errors).
- The module has a docstring explaining its purpose.
- Every public function has a docstring.
- No TODO, FIXME or NotImplementedError remains in shipped code.
- Lines are at most 100 characters; indentation uses spaces; no trailing whitespace; the file ends with a newline.
- Inputs that cannot be handled raise a clear exception instead of returning a wrong value.

Report each problem with the line number and a concrete fix. Approve explicitly when everything passes.
