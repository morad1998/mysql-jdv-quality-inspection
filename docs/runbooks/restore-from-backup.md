# Restore From Backup (D1 baseline)

## Status

| Path | Status |
|---|---|
| Restore from the logical dump into a fresh container (Path A) | VERIFIED by a restore rehearsal on 2026-10-16 |
| Rebuild from the version-controlled scripts (Path B) | VERIFIED: it is how the D1 database was created on a new machine |
| Git bundle integrity and a clone from the bundle | VERIFIED (see evidence in docs/evidence/day-1/backup/) |
| Restore using docker compose instead of docker run | NOT rehearsed |
| Granting the jdv_spike rights before loading the dump | NOT rehearsed |
| Restoring a Docker volume snapshot | NOT rehearsed |
| Second copy of the backup on different storage | NOT done (blocker B-012) |

## What a backup set contains

A backup set is a folder stored OUTSIDE the repository.

| File | Purpose |
|---|---|
| mysql-jdv-quality-inspection.bundle | Full Git history, all branches and tags |
| d1_dump.sql | Logical dump of quality_inspection and jdv_spike: tables, data, triggers and Duality Views |
| baseline-counts.txt | Row count of every table at backup time |
| runtime-manifest.txt | Git commit, tag list, tool versions and the MySQL image digest |
| SHA256SUMS.txt | SHA256 hash of the four files above |

Not in a backup set: database users and grants, the .env file and its secrets, and the Docker volume itself.

## Rebuild versus restore

- Restore recovers a captured state. Use Path A.
- Rebuild recreates a valid environment from source scripts. The data is the deterministic seed, not the captured state. Use Path B.

## Path A: restore from the logical dump

Preconditions: Docker Desktop is running and the backup folder is available. Use Windows PowerShell and a normal (non-admin) window.

### A1. Verify the backup files

Run this inside the backup folder. Every line must say OK.

```powershell
Get-Content .\SHA256SUMS.txt | ForEach-Object { $h,$f = $_ -split '\s+',2; $a = (Get-FileHash ".\$f" -Algorithm SHA256).Hash; "{0}  {1}" -f $(if ($a -eq $h) {'OK '} else {'BAD'}), $f }
git bundle verify .\mysql-jdv-quality-inspection.bundle
```

### A2. Recover the repository

Clone from GitHub, or from the bundle:

```powershell
git clone .\mysql-jdv-quality-inspection.bundle <target folder>
```

### A3. Start a fresh MySQL container

The image creates the application account and its rights on quality_inspection from environment variables. The rehearsal used random passwords:

```powershell
$rp = (New-Guid).ToString('N')
$ap = (New-Guid).ToString('N')
docker run -d --name <container name> -e MYSQL_ROOT_PASSWORD=$rp -e MYSQL_USER=quality_app -e MYSQL_PASSWORD=$ap -e MYSQL_DATABASE=quality_inspection mysql:9.7.2
```

An empty or missing root password makes the image exit with "Database is uninitialized and password option is not specified". Check that both variables are 32 characters before starting.

For the real project, create the container from compose.yaml and .env instead (generate new secrets if the old .env is lost). That variant was not rehearsed with a dump load.

### A4. Wait until the server answers

```powershell
foreach ($i in 1..40) {
  docker exec <container name> sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysqladmin ping -h127.0.0.1 -uroot --silent' 2>$null
  if ($LASTEXITCODE -eq 0) { "ready after attempt $i"; break }
  Start-Sleep -Seconds 3
}
```

### A5. Load the dump as root

Copy the file into the container. Do not pipe or redirect the dump through Windows PowerShell, because that changes its encoding.

```powershell
docker cp .\d1_dump.sql <container name>:/tmp/d1_dump.sql
docker exec <container name> sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql -uroot --default-character-set=utf8mb4 < /tmp/d1_dump.sql'
"restore exit code: $LASTEXITCODE"
```

Expected: exit code 0 and no output.

### A6. Restore the jdv_spike rights

```powershell
"GRANT ALL PRIVILEGES ON jdv_spike.* TO 'quality_app'@'%';" | docker exec -i <container name> sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql -uroot'
```

Without this grant, reading a Duality View in jdv_spike fails with ERROR 1356 ("definer/invoker of view lack rights"), because the views are defined by quality_app and the dump contains no grants (B-013).

### A7. Verify

1. Compare row counts with baseline-counts.txt.
2. Triggers: 5 rows in INFORMATION_SCHEMA.TRIGGERS for quality_inspection.
3. Read a document: SELECT JSON_PRETTY(data) FROM jdv_spike.customer_orders_dv.
4. Optional rule probes (change data, so use a throwaway container only): open a card on a unit that has no active card and expect 3 pending checklist rows; open a second active card for the same unit and expect error 1062; update an audit_event row and expect error 50010.

### Result of the rehearsal (2026-10-16)

- Restore exit code 0, no output.
- Row counts, table checksums, triggers, constraints, the generated column open_unit_key and the Duality View metadata were identical to the live database.
- Documents and ETags were identical after the A6 grant (86 lines on each side).
- The rules still worked on the restored copy (pending rows created, one-active-card rule, append-only audit).
- The live database was untouched and the four backup files still matched their hashes.

## Path B: rebuild from the scripts (no dump)

Use this when the dump is lost but the repository survives. The final mutated data state will differ from the backup.

1. Start the container from compose.yaml and .env.
2. As root, create the disposable database and grant: CREATE DATABASE IF NOT EXISTS jdv_spike CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci; then GRANT ALL PRIVILEGES ON jdv_spike.* TO 'quality_app'@'%';
3. As quality_app, run database/00_environment/01_minimum_jdv_spike.sql. The concurrency test 02_optimistic_concurrency_test.sql is optional and changes data.
4. As quality_app, run database/01_domain_model/01_schema.sql.
5. As root, run database/01_domain_model/02_rules_triggers.sql (see D-013 for why root).
6. As quality_app, run database/01_domain_model/03_seed.sql.
7. 04_tests.sql is optional. It changes data, so reset first (99_rollback.sql, 01, 02, 03) before running it again.

## Known gotchas

- The dump contains no users or grants. The account quality_app must exist before loading, because triggers and views name it as definer.
- mysqldump prints a GTID warning for a partial dump. It was harmless here: exit code 0 and the restore succeeded.
- Creating triggers needs root when binary logging is on (D-013).
- Create dumps inside the container and copy them out with docker cp. Redirecting with ">" in Windows PowerShell 5.1 changes the encoding.
- Tee-Object and Out-File in Windows PowerShell write UTF-16 by default. Evidence files in the repository are converted to UTF-8 with LF line endings.
- Never put passwords in documents. Search a dump for the real secret values before sharing it.
- The copy of SHA256SUMS.txt under docs/evidence/day-1/backup/ records the hashes of the original backup files. The text files stored in the repository were converted to LF line endings, so their hashes differ. Verify against the backup folder, not the repository copies.
