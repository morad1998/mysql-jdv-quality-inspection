# D3 Summary: demo API

## Overall result

PASS. The API in api/ runs against the real Docker database (MySQL 9.7.2). 54 unit and route tests and 16 integration tests pass, the TypeScript check is clean, 14 example requests were recorded, and the database was back at baseline after every run (cards 2, measurements 4, checklist 6, findings 1, attachments 2).

D3 is not complete as a project phase: a clean-environment replay from the README, the diagrams and the article are still open.

## Installed versions

Node.js 24.20.0, npm 11.19.0, mysql2 3.24.6, typescript 7.0.2, @types/node 26.6.5 (exact tree in api-npm-ls.txt and api/package-lock.json).

## Results

| Check | Result |
|---|---|
| npm test | 54 tests, 54 pass, 0 fail (in-memory model; proves the API's own logic) |
| npm run typecheck | no errors |
| npm run test:integration | 16 tests, 16 pass, 0 fail (real database) |
| Database after the integration run | 2, 4, 6, 1, 2 (db-baseline-after.txt) |
| npm run examples | 14 requests: 200, 201, 409, 200, 200, 412, 403, 409, 200, 400, 200, 200, 409, 200 (docs/api/example-transcript.md) |
| Browser check of GET /api | the self-description answers without a user |

## What the integration tests show on the real database

- Opening a card is a plain INSERT, and the trigger creates the PENDING result rows.
- A stale ETag is answered with 412 and the current document.
- Answers and a measurement written through the edit view carry the user and a whole-second UTC time that the server filled in.
- The one-active-card rule (error 1062) is mapped to 409; closing with unanswered items (50002) is mapped to 409.
- A changed answer on a closed card is refused by the lock (50022) and mapped to 409; a repeated close is refused by the API (see D-028).
- A card closed with REJECT, and the writes visible in the read view and the list.

## Evidence notes

- The test and capture files were written by Windows PowerShell and are converted to UTF-8 with LF line endings. PowerShell may have replaced some symbols (for example the check marks) with a question mark; the counts are unaffected.
- The failing first integration run is not stored as a file (see B-019).
- The transcript shows ETags, demo user names and generic demo data only, and the card it created (id 939) was deleted afterwards, so its ETags no longer match any row.
- api-integration.txt contains the line "reopen attempt answered 409 CARD_FINAL db_errno=50020".
