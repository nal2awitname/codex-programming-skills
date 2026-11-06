# Reconstruction record

Reference identity: task-supplied synthetic JSON-argument command. Its version,
implementation language and private structure were not established. The allowed
evidence was process output only; no reference source, tests, assets or binaries
were read, copied, imported, embedded or made runtime dependencies of this program.

Discovery used 39 synthetic observation records. Builder input was the reviewed
eight-requirement / 29-case contract and generated builder guidance. The exported
contract and its input manifest are preserved here. Implementation and tests were
authored from the public behavior definitions, not translated from original code.

Actual isolation: the same context observed public inputs/outputs and later built
the program. It did not inspect reference implementation. No separate builder
agent was created, and no OS/filesystem access controls prevented reference access.
The process provides instructed abstention and data separation, not an enforced
clean room or an originality certificate.

The new implementation uses Python 3.10+ syntax and only the Python standard
library (`json`, `sys`, `collections.abc`); tests additionally use standard-library
utilities. There are no third-party packages or original assets. A single-pass
integer accumulator was chosen from count/range/sum requirements and exact integer
arithmetic needs. No original implementation design is asserted.

Retained exact public compatibility facts: `values`, `count`, `span`, `total`,
`error`, `invalid_json`, `invalid_request`, `integer_list_required`, the empty span
`null`, and the documented zero values/exit status. Each has a reason and neutral
observation ID in `contract.json`.

Verification: candidate acceptance 29/29, nine independent property tests,
reference/candidate comparison 29/29 contract cases and 109/109 additional cases.
See `verification.md`. No behavior mismatch was found in those runs. Local Windows host
execution was unavailable during reconstruction; repository CI records subsequent
candidate-side checks. Unobserved input/resource extremes remain gaps. No claim is made
about hidden functions, original development history, legal certification or
reconstruction of the author's original source.
