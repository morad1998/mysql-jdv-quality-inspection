# Project Blocker Register

## Status definitions

- OPEN: Prevents the next required activity.
- WATCH: Does not block current work but requires later validation.
- RESOLVED: The issue was corrected and verified.

## B-001 - Docker Linux engine unavailable

- Status: RESOLVED
- Date identified: 2026-10-02
- Symptom: Docker CLI could not connect to the Docker Desktop Linux engine named pipe.
- Resolution: Started Docker Desktop.
- Verification: docker info returned a populated server section for Docker Server 29.6.2.

## B-002 - Stale Docker Hub credentials

- Status: RESOLVED
- Date identified: 2026-10-02
- Symptom: Pulling the public mysql:9.7.2 image returned an authentication error.
- Resolution: Removed the stale Docker Hub login using docker logout.
- Verification: mysql:9.7.2 downloaded successfully and its digest was recorded.

## B-003 - Obsolete user-level npm override

- Status: RESOLVED
- Date identified: 2026-10-02
- Symptom: Node.js 24.19.0 invoked user-level npm 8.5.3 instead of bundled npm 11.17.0.
- Resolution: Renamed the obsolete user-level npm package directory as a reversible backup.
- Verification: npm --version returned 11.17.0.

## B-004 - Windows MySQL client unavailable

- Status: RESOLVED
- Date identified: 2026-10-02
- Symptom: mysqlsh and mysql were not available as Windows commands.
- Resolution: Use the MySQL 9.7.2 client included in the pinned Docker image.
- Verification: The containerized client returned MySQL Community Server 9.7.2 for Linux x86_64.

## B-005 - MySQL server runtime verified

- Status: RESOLVED
- Date identified: 2026-10-02
- Resolution: Started the persistent MySQL 9.7.2 container with a named volume and local-only port binding.
- Verification: Container health was healthy and SELECT VERSION() returned 9.7.2.

## B-006 - JSON Duality View support proven

- Status: RESOLVED
- Date identified: 2026-10-02
- Resolution: Executed the minimum capability spike against MySQL Community Server 9.7.2.
- Verification: Proved reads, INSERT, UPDATE, DELETE, relational persistence, validation rejection, atomic rollback, and optimistic concurrency protection.

## B-007 - MySQL REST Service availability

- Status: WATCH
- Date identified: 2026-10-02
- Impact: REST integration remains a bonus feature and its availability in the selected environment has not been validated.
- Control: Use a transparent Node.js and TypeScript REST adapter if MySQL REST Service is unavailable.

## B-008 - Generated column compatibility with Duality Views

- Status: WATCH
- Date identified: 2026-10-16
- Impact: inspection_card contains the virtual generated column open_unit_key (D-012). A READ-ONLY Duality View over inspection_card that does not expose the column was created and is valid (D2 step 1, 2026-10-16). A WRITABLE view over this table has not been tested.
- Control: Re-check when write annotations are added to a view over inspection_card. If MySQL rejects the table or column for a writable view, enforce the one-active-card rule with a trigger instead and record the limitation.

## B-009 - AI model provider not selected

- Status: WATCH
- Date identified: 2026-10-16
- Impact: The AI assistant (D-015) will call a hosted model with the owner's own API key, but the specific provider has not been chosen. This does not block D1 or D2.
- Control: Choose the provider before the AI phase. Use one adapter so the provider can be swapped. AI_PROVIDER stays disabled until the read-only controls are tested.

## B-010 - Test output order in Windows PowerShell capture

- Status: RESOLVED
- Date identified: 2026-10-16
- Symptom: In the captured D1 test output, ERROR lines appear out of order relative to the test labels, and a pattern search for "ERROR" counted 17 lines instead of 8.
- Resolution: Each test prints a label and a post-failure state check, so results are read by error number and state check, not by line order. The extra count came from test labels that contain the text "EXPECT ERROR" and one PowerShell error wrapper line.
- Verification: All eight expected errors are present by number (1062, 50001, 50002, 50003, 3819, 1452, 50010, 50011) and the data was unchanged after each.

## B-011 - Git dubious ownership on a copied repository

- Status: RESOLVED
- Date identified: 2026-10-16
- Symptom: Git refused to run in the repository copied from another machine ("detected dubious ownership").
- Resolution: Added a safe.directory exception for that one folder only.
- Verification: git status, git log and git rev-parse HEAD returned the expected Day 0 commit with a clean working tree.

## B-012 - Second backup copy not made

- Status: WATCH
- Date identified: 2026-10-16
- Impact: The backup set exists only on one machine. The code and full history are also on the public GitHub repository, and the database content is synthetic and reproducible from the scripts (Path B in the restore runbook), so the data-loss risk is low. The backup validation gate asks for a copy on different storage.
- Control: Copy the backup folder to a second location chosen by the owner and verify the hashes there. Close this item when done.

## B-013 - Restored Duality Views unreadable until the jdv_spike grant is restored

- Status: RESOLVED
- Date identified: 2026-10-16
- Symptom: After restoring the dump into a fresh container, reading customer_orders_dv failed with ERROR 1356 (definer/invoker of view lack rights).
- Resolution: The dump contains no grants and the views are defined by quality_app. Granted ALL PRIVILEGES on jdv_spike.* to quality_app after the load. The restore runbook now lists this as step A6.
- Verification: After the grant, document queries returned output identical to the live database, including ETags (86 lines on each side).

## B-014 - First restore rehearsal container failed to start

- Status: RESOLVED
- Date identified: 2026-10-16
- Symptom: The throwaway container exited with "Database is uninitialized and password option is not specified".
- Resolution: A typing error in the password-generation command left the passwords empty. Re-ran with New-Guid, and the rehearsal script now stops if a password is not 32 characters or if the container exits.
- Verification: The retry started, the restore exit code was 0, and the data compared identical.

## B-015 - Weak negative test hid the read-only behavior

- Status: RESOLVED
- Date identified: 2026-10-16
- Symptom: The first read-only test updated a field to the value it already had. MySQL returned no error, which looked like a failure of the read-only protection.
- Resolution: Added a test that makes a real change inside a transaction that is rolled back. MySQL refused it with ERROR 6497 and the data and ETag were unchanged afterwards. A no-change update is accepted silently (see D-018).
- Verification: docs/evidence/day-2/d2-1-followup.txt (F1 to F5).

## B-016 - Update error names a path that was not changed

- Status: WATCH
- Date identified: 2026-10-16
- Impact: ERROR 6497 names the changed path for root-level changes and for changes to fields of a nested object, but for a change inside an array element it names inspection_card.unit_id, path $.unit.unit_id, whenever the view contains a nested single object. Observed in the full view in steps 3 to 6 (every array: measurements, checklist, findings, attachments) and in the throwaway views. The behavior is deterministic and independent of the card, the array, the element index and the field. The refusal is always correct; only the path in the message is misleading.
- Evidence, throwaway views: probe_a_dv (no nested object) named the correct array path, measurement_result.result_status at $.measurements[0].result_status. probe_b_dv (nested unit object) named inspection_card.unit_id at $.unit.unit_id for the same change. probe_c_dv (D2 step 6) wrote the nested object's keys so that the stored key order was ["sn", "unit_id"], confirmed with JSON_KEYS; the array-element change still named inspection_card.unit_id at $.unit.unit_id, while a change to $.unit.sn named production_unit.unit_serial at $.unit.sn (correct).
- Conclusion: the hypothesis "the error names the first key of the nested object" is refuted. The named column is the join column of the nested object (the foreign key unit_id in the parent table inspection_card) in every observed case, which is consistent with, but does not prove, a join-column explanation. The cause is unknown.
- Not separated: in every probe the nested object came before the array in stored key order (unit has 4 characters; measurements has 12), so "the nested object is checked before the arrays" fits the data as well as "the join column is named".
- Control: Do not use the path in error 6497 to locate an array change when the view contains a nested object. Re-check when write annotations are added, because the message may mislead about which table needs an annotation. An optional probe (an array key shorter than the object key) would separate the two remaining explanations; it is not planned.

## Current blocking summary

- Active OPEN blockers: None.
- Remaining WATCH items: B-007 (MySQL REST Service availability), B-008 (generated column vs Duality Views), B-009 (AI model provider), B-012 (second backup copy), B-016 (update error path).
- Next controlled gate: write phase: a separate edit view with modification tags (tests B-008); design agreed before scripts are written.
