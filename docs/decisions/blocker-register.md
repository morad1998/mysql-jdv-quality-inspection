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

## Current blocking summary

- Active OPEN blockers: None.
- Remaining WATCH items: B-007 (MySQL REST Service availability), B-008 (generated column vs Duality Views), B-009 (AI model provider), B-012 (second backup copy).
- Next controlled gate: D2 step 2: add the production unit as a nested object in inspection_card_dv.
