# Day 0 Environment Evidence

## Evidence date

2026-10-02

## Workstation tools

| Component | Verified value | Status |
|---|---|---|
| Git | 2.53.0.windows.2 | PASS |
| Docker client | 29.6.2 | PASS |
| Docker server | 29.6.2 | PASS |
| Docker Compose | 5.3.1 | PASS |
| Docker context | desktop-linux | PASS |
| Docker operating system | Docker Desktop Linux | PASS |
| Docker architecture | x86_64 | PASS |
| Docker backend kernel | WSL2 Linux 6.6.87.2 | PASS |
| Node.js | 24.19.0 | PASS |
| npm | 11.17.0 | PASS |
| curl | 8.21.0 for Windows | PASS |
| MySQL client | 9.7.2 for Linux x86_64 | PASS |

## MySQL image

| Property | Verified value |
|---|---|
| Image tag | mysql:9.7.2 |
| Edition | MySQL Community Server - GPL |
| Architecture | amd64 |
| Operating system | linux |
| Image ID | sha256:e2bde46db6563855d7177adb5f0b57b9dc663f5a20927a90f4259d3312068497 |
| Repository digest | mysql@sha256:e2bde46db6563855d7177adb5f0b57b9dc663f5a20927a90f4259d3312068497 |
| Image created | 2026-09-29T18:39:56.756447718Z |

## Repository

| Property | Verified value |
|---|---|
| Local path | C:\Users\morad\mysql-jdv-quality-inspection |
| Initial branch | main |
| Initial state | Greenfield repository with no prior commits |
| MySQL host port | 3307 planned |
| Application database | quality_inspection planned |
| Application database user | quality_app planned |

## Corrections completed

- Started Docker Desktop and verified the Docker server section.
- Cleared stale Docker Hub credentials before pulling the public MySQL image.
- Isolated the obsolete user-level npm 8.5.3 package.
- Verified that Node.js uses bundled npm 11.17.0.
- Confirmed that plain curl is a Windows PowerShell alias.
- Standardized project commands on curl.exe.
- Confirmed that no separate Windows MySQL client installation is required.

## Open Day 0 gates

- Create the decision log.
- Create the blocker register.
- Create the real local environment file without committing it.
- Create the Docker Compose definition.
- Start the MySQL server container.
- Capture SELECT VERSION() from the running server.
- Run the minimum official JSON Duality View capability spike.
- Test read, write, validation, rollback, and relational persistence.
- Create the verified Day 0 Git checkpoint.
