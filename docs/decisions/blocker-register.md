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

## Current blocking summary

- Active OPEN blockers: None.
- Remaining WATCH item: MySQL REST Service availability.
- Next controlled gate: Review and commit the verified Day 0 baseline.