# D2 Backup Milestone Summary

## Overall result

PASS for the Git bundle, the logical dump, the hashes and the restore rehearsal of the D2 state. NOT done: a second copy on different storage (B-012) and an end-to-end replay of Path B2.

Backup set d2-verified-2026-10-16, Git commit 44b5712, tag d2-step7-verified.

| Check | Result |
|---|---|
| Git bundle verify | Okay, complete history, 13 refs (main, origin/main, 10 tags, HEAD) |
| Clone from the bundle | HEAD 44b5712, branch main, 126 tracked files, clean working tree |
| Logical dump | Exit code 0, 14 CREATE TABLE, 8 triggers, 4 duality view lines, completion marker, 0 secret values, 44871 bytes |
| Baseline row counts | 3, 2, 3, 2, 2, 3, 2, 4, 6, 1, 2, 1 and jdv_spike 2 and 4 (every D2 test was rolled back) |
| Restore into a fresh container | Exit code 0, no output; the jdv_spike grant was applied right after the load |
| Live versus restored fingerprint | 387 lines each, identical, including trigger ACTION_ORDER and every ETag of both D2 views |
| Lock tests on the restored copy | The seven expected errors (lines 27, 36, 45, 54, 63, 75, 99) and no others; the FINAL baseline check matched |
| Hashes | All five backup files matched their recorded hashes after the rehearsal |
| Live database | Untouched, Up and healthy; rehearsal container removed |

## Evidence notes

- The dump contains no FOLLOWS clause, yet the restored trigger order was identical to the live one. Why was not examined.
- mysqldump printed the GTID warning for a partial dump again. Exit code 0 and the restore succeeded.
- SHA256SUMS.txt records the hashes of the original backup files. The text files in this folder were converted to UTF-8 with LF line endings, so their hashes differ; verify against the backup folder, not these copies.
- The restore printed no output, so no output file is included.
- The dump and the bundle are not stored in the repository.
