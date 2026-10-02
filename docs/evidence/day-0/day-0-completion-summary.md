# Day 0 Completion Summary

## Overall result

PASS - The prerequisite environment and minimum MySQL JSON Duality
View capability spike were completed successfully.

## Verified runtime

- MySQL Community Server 9.7.2
- Docker image mysql:9.7.2
- Local container mysql-jdv-quality-db
- Local binding 127.0.0.1:3307
- Persistent volume mysql-jdv-quality-data
- Application account quality_app
- Application database quality_inspection
- Disposable spike database jdv_spike

## Verified development tools

- Git 2.53.0.windows.2
- Docker client and server 29.6.2
- Docker Compose 5.3.1
- Node.js 24.19.0
- npm 11.17.0
- curl.exe 8.21.0
- MySQL client 9.7.2 from the pinned Docker image

## JSON Duality View capability evidence

- Created normalized customers and orders tables.
- Created customer_orders_dv as a valid read-only Duality View.
- Created order_dv as a valid writable Duality View.
- Read hierarchical customer documents with nested order arrays.
- Read order documents with nested customer objects.
- Confirmed generated document ETags.
- Inserted an order document and verified the relational row.
- Updated an order document and verified relational persistence.
- Deleted an order document while preserving the shared customer.
- Confirmed that missing write annotations enforce read-only behavior.
- Confirmed rejection of an unmapped JSON property.
- Confirmed no partial persistence after validation rejection.
- Confirmed atomic rollback after a related-table insert failure.
- Confirmed stale-document rejection through ETag comparison.
- Confirmed preservation of the newer value after the conflict.

## Important evidence-based conclusions

1. Normalized relational tables remained the system of record.
2. Applications can consume hierarchical JSON documents without
   maintaining a duplicated JSON copy.
3. Writable Duality Views translate JSON document operations into
   changes against normalized relational tables.
4. Write annotations explicitly control permitted modifications.
5. Unmapped JSON properties are rejected rather than ignored.
6. Multi-table document operations are atomic.
7. Generated ETags support optimistic concurrency protection.

## Evidence files

- 01_minimum_jdv_spike_output.txt
- 02_jdv_document_read_output.txt
- 03_jdv_update_output.txt
- 04_jdv_insert_output.txt
- 05_jdv_delete_output.txt
- 06_read_only_rejection_output.txt
- 07_read_only_unchanged_output.txt
- 08_schema_validation_rejection_output.txt
- 09_schema_validation_rollback_output.txt
- 10_atomic_insert_rejection_output.txt
- 11_atomic_rollback_verification_output.txt
- 12_optimistic_concurrency_rejection_output.txt
- 13_optimistic_concurrency_state_output.txt

## Corrections and lessons

- Docker Desktop must be running before container commands execute.
- Stale Docker Hub credentials can block public-image downloads.
- Windows PowerShell requires curl.exe to bypass the curl alias.
- The obsolete user-level npm override was isolated.
- PowerShell here-strings require the opening and closing markers
  to appear on their own lines.
- A nonzero exit code alone does not prove an expected rejection.
- Error content and post-operation state must also be validated.
- JSON values stored in MySQL variables should be inspected with
  JSON_EXTRACT and JSON_UNQUOTE rather than column shorthand.

## Remaining Day 0 closure actions

- Update the blocker register.
- Verify repository contents and secret exclusion.
- Stage the approved files.
- Review the staged diff.
- Create the Day 0 Git commit.
