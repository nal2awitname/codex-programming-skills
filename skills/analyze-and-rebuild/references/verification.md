# Verify behavior and implementation provenance

## Behavioral verification

1. Map each in-scope requirement to independently authored cases. Include an edge/error/stateful case when the relevant behavior exists. Avoid asserting coverage for requirements that have no test or direct observation.
2. Build and execute the new code in an appropriate environment. Record commands, environment assumptions, actual results, and unavailable checks. A successful parser/type check alone does not prove runtime behavior.
3. If the original can be exercised, run the same synthetic inputs separately against reference and rebuild. Capture the reference's actual output, errors, state transitions, and externally visible side effects. Never link the original into the new implementation to perform its work.
4. Normalize only contractually irrelevant variation, such as explicitly unordered sets or nondeterministic IDs. Do not sort ordered output, suppress errors, or round away meaningful differences. Use stated numerical tolerances and controlled clock/seed/locale when relevant.
5. Without an executable oracle, use public specifications, source-confirmed requirements, and invariants. Distinguish implementation consistency from reference equivalence. Do not fabricate expected reference observations.
6. Investigate failures against the requirement and evidence. Correct the new implementation or justify an evidence-based contract change. Add a regression case for a material defect; avoid tests that merely repeat implementation details.

## Provenance and separation review

- Verify the builder's inputs and context history. Record whether it previously saw the original and whether filesystem/network access to the original was restricted. Distinguish instructed abstention from enforced isolation.
- Inspect imports, manifests, lockfiles, symlinks, bundled resources, output packages, and runtime loading for original-code or original-binary dependencies. Check that the original is not invoked behind an adapter.
- Review suspicious exact blocks, distinctive comments/identifiers, unnecessary internal constants, private structural similarity, and unexplained assets. If similarity tooling is available, inspect each meaningful match; standard syntax and necessary public interfaces can coincide.
- Do not claim that a low similarity score proves independence. Document the workflow and evidence without inventing certifications.
- If copied material is found, remove the affected implementation and reconstruct it from the audited contract. Do not conceal a finding by renaming or rearranging copied code.

## Result record

| Requirement | Evidence/observation ID | New implementation component | Cases executed | Result and remaining gap |
| --- | --- | --- | --- | --- |

Summarize results as exercised cases and known gaps, not a fabricated percentage of total compatibility. State whether checks were executed, statically inspected, or blocked by the environment.

## Final delivery

Provide the runnable implementation, necessary dependency/build/run files, behavioral contract, concise analysis report, and reconstruction record when a rebuild was requested. Keep analyst and builder areas distinct during construction. Use the applicable artifact saving workflow for deliverables; do not save external-repository-backed code twice. Deliver analysis only when that was the user's scope.
