# Day 1 (D1) Database Completion Summary

## Overall result

PASS for the D1 database part: the relational schema, business-rule triggers, seed data and the positive and expected-failure tests were executed on MySQL 9.7.2 and verified.

D1 is not fully closed. These planned D1 deliverables are still open: inspection-card JSON example, document-boundary decision matrix, read-only and writable behavior matrix, and architecture and ER diagrams. The backup milestone is complete except for a second copy on different storage (see B-012).

## Verified runtime

- MySQL Community Server 9.7.2 (Docker image mysql:9.7.2)
- Git 2.56.0.windows.2
- Docker 29.8.2, Docker Compose 5.5.1
- Node.js 24.20.0, npm 11.19.0
- Application database quality_inspection, application account quality_app

The Day 0 environment was rebuilt on a new machine from the version-controlled files. This is a rebuild, not a restore; the database started empty.

## What was executed

| Script | Purpose | Run as |
|---|---|---|
| database/01_domain_model/01_schema.sql | 12 tables with keys, constraints and indexes | quality_app |
| database/01_domain_model/02_rules_triggers.sql | 5 triggers (N2 pending rows, close rules, append-only audit) | root, DEFINER quality_app |
| database/01_domain_model/03_seed.sql | Deterministic generic demo data | quality_app |
| database/01_domain_model/04_tests.sql | Tests T01 to T14 plus T11b | quality_app, mysql --force |
| database/01_domain_model/99_rollback.sql | Removes D1 objects only | quality_app |

## Structural verification

| Check | Result |
|---|---|
| Tables | 12 |
| Foreign keys | 18 |
| CHECK constraints | 17 |
| UNIQUE constraints | 11 |
| open_unit_key | VIRTUAL GENERATED, unique index uq_card_one_active_per_unit |
| Triggers | 5, definer quality_app@% |

Evidence: 01-schema-counts.txt and 02-triggers.txt.

## Test results

| Test | Expected | Result |
|---|---|---|
| T01 | Card opens with 2 PENDING measurements and 3 PENDING checklist items | PASS |
| T02 | Second active card on one unit rejected, error 1062 | PASS |
| T03 | Card not starting OPEN rejected, error 50001 | PASS |
| T04 | Close with an unanswered checklist item blocked, error 50002 | PASS |
| T05 | Results recorded and checklist answered | PASS |
| T06 | Close with an open CRITICAL finding blocked, error 50003 | PASS |
| T07 | Close after resolving the finding; open_unit_key becomes NULL | PASS |
| T08 | Retest card opens on the same unit | PASS |
| T09 | Disposition on an OPEN card rejected, error 3819 | PASS |
| T10 | Card moved to REJECTED with disposition REJECT | PASS |
| T11 | Attachment pointing at another card's finding rejected, error 1452 | PASS |
| T11b | Two valid attachments inserted | PASS |
| T12 | Audit event appended | PASS |
| T13 | Audit update blocked, error 50010 | PASS |
| T14 | Audit delete blocked, error 50011 | PASS |

After every expected failure a state check showed the data unchanged. Final row counts: inspection_card 2, measurement_result 4, checklist_result 6, quality_finding 1, attachment_metadata 2, audit_event 1.

## Evidence notes

- The captured test output interleaves error lines and result tables, because Windows PowerShell merges the two output streams with different buffering. Read each test by its label, its error number and its state check (see B-010).
- A pattern search for "ERROR" in the capture finds 17 lines, not 8. The extra lines are test labels containing the text "EXPECT ERROR" and one PowerShell error wrapper line.
- The schema and trigger creation runs printed no output, so no output file exists for them. Their proof is 01-schema-counts.txt and 02-triggers.txt, which query the resulting objects.
- Evidence text files were normalized to UTF-8 with LF line endings.

## Backup milestone

PASS for the Git bundle, logical dump, hashes and restore rehearsal. NOT done: a second copy on different storage (B-012).

| Check | Result |
|---|---|
| Git bundle verify | Okay, complete history, main and both tags present |
| Clone from the bundle | HEAD matched the backed-up commit (backup/bundle-clone-check.txt) |
| Logical dump | Exit code 0, 14 CREATE TABLE, 5 triggers, 2 databases, completion marker present, 0 secret values |
| Restore into a fresh container | Exit code 0, no output |
| Live versus restored | Row counts, table checksums, triggers, constraints, open_unit_key and view metadata identical |
| Documents and ETags | Identical (86 lines each) after the jdv_spike grant |
| Rules after restore | Pending rows created (3 for the new card), second active card rejected (1062), audit update blocked (50010) |
| Hashes | All four backup files matched their recorded hashes after the rehearsal |

Backup evidence notes:

- The first rehearsal container failed to start (B-014). The files here are from the second attempt.
- fingerprint-restored.txt stops at the document query, which failed with error 1356 before the grant was restored (B-013). The documents were compared separately in docs-live.txt and docs-restored.txt.
- The rule probes changed only the throwaway container, so the restored copy was no longer identical to the live database after them. The container was removed.
- The restore printed no output, so no output file is included. The exit code 0 is recorded here.
- The text files in backup/ were converted to LF line endings. SHA256SUMS.txt records the hashes of the original backup files, so verify against the backup folder, not these copies.
- The runbook is docs/runbooks/restore-from-backup.md.

## Known limitations

- Role permissions are not enforced by the database (D-010).
- REJECTED cards may still have pending checklist items (D-011).
- Checkpoint definitions are not versioned (D-009).
- The generated column open_unit_key has not been tested with Duality Views (B-008).
- No Duality View exists yet over the D1 tables.

## Next step

D2: create a read-only inspection_card Duality View first, require STATUS valid, and compare the JSON with relational queries before adding nested collections.
