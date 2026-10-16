# Project Decision Log

## D-001 - Greenfield implementation

- Status: Approved
- Date: 2026-10-02
- Decision: Build the bounty application completely from scratch in a dedicated repository.
- Reason: Keep the public bounty implementation reproducible and separate from the existing QMS Performance Card application.
- Constraint: QMS documents may be consulted only for general architectural, testing, documentation, and manufacturing-domain lessons.
- Constraint: Do not copy proprietary data, credentials, infrastructure details, Oracle-specific SQL, or internal source code.

## D-002 - Primary application scenario

- Status: Approved
- Date: 2026-10-02
- Decision: Use a manufacturing quality-inspection application as the bounty scenario.
- Scope: Work orders, production units, inspection cards, sections, measurements, checklist results, findings, attachment metadata, and audit events.

## D-003 - Database runtime

- Status: Approved
- Date: 2026-10-02
- Decision: Use MySQL Community Server 9.7.2 in Docker.
- Image: mysql:9.7.2
- Reason: Pinning the exact patch version improves reproducibility.
- Verification: The image and included MySQL client were successfully inspected and executed.

## D-004 - Database connectivity

- Status: Approved
- Date: 2026-10-02
- Decision: Use host port 3307 for the local MySQL container.
- Reason: Avoid conflict with the conventional MySQL port 3306.

## D-005 - Development stack

- Status: Approved
- Date: 2026-10-02
- Decision: Use Node.js, TypeScript, React, and a server-side API boundary.
- Security rule: Database credentials and optional AI-provider credentials must not be exposed to the browser.

## D-006 - Evidence standard

- Status: Approved
- Date: 2026-10-02
- Decision: No capability is complete until demonstrated through executed commands and actual output.
- Required proof: JSON verification, relational verification, tested-version evidence, and recorded failures or limitations.

## D-007 - JSON Duality View validation

- Status: Approved
- Date: 2026-10-02
- Decision: Run a minimum official customer-and-order capability spike before designing the full manufacturing schema.
- Required proof: View creation, document read, controlled DML, base-table persistence, invalid-document rejection, and rollback behavior.

## D-008 - AI integration

- Status: Approved
- Date: 2026-10-02
- Decision: Keep AI integration disabled during the initial database and application build.
- Future rule: Any AI assistant must use a restricted, read-only context and must not receive unrestricted database access.

## D-009 - D1 domain vocabulary and lifecycle rules

- Status: Approved
- Date: 2026-10-16
- Decision: Adopt the D1 demo vocabulary. Card status: OPEN, IN_PROGRESS, CLOSED, REJECTED. Disposition: PASS or REJECT, set only on a final card. Finding severity: MINOR, MAJOR, CRITICAL. Finding status: OPEN, RESOLVED. Measurement result: PENDING, RECORDED, NOT_APPLICABLE. Checklist answer: PENDING, YES, NO, NOT_APPLICABLE.
- Scope: Work orders are seeded manually with deterministic scripts. Units are identified by a surrogate unit_id plus a unique unit_serial. A unit may have several cards over time; a retest is a new card and never an overwrite. Attachment bytes stay outside MySQL (metadata only). audit_event requires actor_id, event_type, event_time, target_type and target_id and is append-only.
- Constraint: Every value is a demo vocabulary for a public example. None is claimed to be an organizational or production standard.
- Constraint: Checkpoint definitions are not versioned in the schema. This is a stated limitation of the example.
- Verification: Tests T01 to T14 in database/01_domain_model/04_tests.sql; output in docs/evidence/day-1/04-tests-output.txt.

## D-010 - Demo roles and pre-created pending rows

- Status: Approved
- Date: 2026-10-16
- Decision: Two demo roles are stored in app_user.role_code: INSPECTOR and SUPERVISOR. When a card opens, trigger trg_inspection_card_ai creates one PENDING measurement_result row per measurement_definition and one PENDING checklist_result row per checklist_definition.
- Reason: "Unanswered checklist item" becomes a queryable state instead of a missing row.
- Constraint: Role permissions are not enforced by the database in D1. Enforcement belongs to the API layer in a later phase.
- Verification: T01 and T08 show 2 pending measurements and 3 pending checklist items on each newly opened card.

## D-011 - REJECTED is a final status

- Status: Approved
- Date: 2026-10-16
- Decision: REJECTED is a final status alongside CLOSED. Both require closed_by and closed_at. A disposition is allowed only on a final card and is mandatory for CLOSED. The close checks (unanswered checklist item, open CRITICAL finding) apply only when a card moves to CLOSED.
- Reason: The original decisions did not define REJECTED. This reading was proposed on 2026-10-16 and no objection was raised after test T10 showed the behavior.
- Constraint: A REJECTED card may still have pending checklist items. Revisit if rejection should require the same checks.
- Verification: T09 (disposition on an OPEN card rejected with error 3819) and T10 (card moved to REJECTED).

## D-012 - One active card per unit

- Status: Approved
- Date: 2026-10-16
- Decision: Enforce at most one OPEN or IN_PROGRESS card per unit with a virtual generated column open_unit_key (the unit_id while the card is active, NULL otherwise) and a UNIQUE index uq_card_one_active_per_unit.
- Reason: MySQL allows many NULL values in a unique index, so final cards do not block a retest.
- Constraint: Compatibility of this generated column with JSON Duality Views is not yet proven (see B-008).
- Verification: T02 (error 1062 on the unique index); T07, T08 and T10 (key becomes NULL when a card is final, and a retest card opens).

## D-013 - Business rules are enforced in the database

- Status: Approved
- Date: 2026-10-16
- Decision: Triggers enforce the close rules and the append-only audit table, using user-defined error numbers: 50001 new card must start OPEN; 50002 unanswered checklist item blocks close; 50003 open CRITICAL finding blocks close; 50010 audit_event update blocked; 50011 audit_event delete blocked. CHECK constraints enforce disposition and result rules. A composite foreign key ensures an attachment's finding belongs to the same card.
- Constraint: Triggers are created by the root account with DEFINER quality_app, because a non-root account can fail to create triggers (error 1419) when binary logging is on.
- Verification: T03, T04, T06, T09, T11, T13 and T14 each raised the expected error, and a state check after each showed the data unchanged.

## D-014 - Project documents are versioned

- Status: Approved
- Date: 2026-10-16
- Decision: Every design document carries a version in its file name and is never overwritten; a change creates the next version. Word versions are kept in the owner's cloud storage. Markdown and SQL sources are kept in this repository. Each document states the Git commit it is based on.

## D-015 - AI assistant scope (amends D-008)

- Status: Approved (design only; not implemented)
- Date: 2026-10-16
- Decision: AI stays disabled by default, but one read-only assistant is in scope. It explains an inspection card, produces a full work-order report, and answers manufacturing statistics questions that the schema can support.
- Scope: Two read-only document views (one per card, one per work order) plus fixed aggregate SQL views, because statistics are aggregates and Duality Views are not the right tool for them. A SELECT-only database account. Fixed read-only tool functions; the model never writes SQL and never writes data. Synthetic data only. Each question is logged as an audit_event with event_type AI_QUERY.
- Provider: A hosted model called with the owner's own API key through a thin adapter. AI_PROVIDER stays disabled by default. The specific provider is not yet chosen (see B-009).
- Constraint: Credentials stay server-side (D-005).
- Constraint: Before enabling, test a write request, prompt-injection text inside a finding description, and a request for data outside the views.

## D-016 - Offline scope

- Status: Approved (design only; not implemented)
- Date: 2026-10-16
- Decision: Offline support covers edits to inspection cards already downloaded to the device. Each queued edit carries the ETag of the document it was based on. If MySQL rejects the replay as stale (error 6494, proven in Day 0 and replayed on 2026-10-16), the user is shown both versions and chooses. Offline card creation and offline attachments are out of scope.
- Constraint: A retry after a lost response can look like a conflict. The app must re-read the document and compare before reporting one.

## D-017 - Backup set and restore verification standard

- Status: Approved
- Date: 2026-10-16
- Decision: A backup set consists of a Git bundle, a logical dump of quality_inspection and jdv_spike, baseline row counts, a runtime manifest and SHA256 hashes, stored outside the repository. A backup counts as valid only after a restore rehearsal in a throwaway container with random passwords, compared against the live database, with the live database left untouched.
- Reason: A backup that has never been restored is only an assumption.
- Constraint: The dump contains no users or grants. After loading it, the application account needs rights on jdv_spike, because the Duality Views there are defined by quality_app and fail with error 1356 without them (see B-013).
- Constraint: Dumps are created inside the container and copied out with docker cp, because Windows PowerShell redirection changes the encoding.
- Verification: docs/evidence/day-1/backup/ and docs/runbooks/restore-from-backup.md.

## D-018 - inspection_card_dv exposes real columns only

- Status: Approved
- Date: 2026-10-16
- Decision: The first Duality View over inspection_card, inspection_card_dv, is read-only (no WITH clause) and exposes the card columns card_id (as _id), unit_id, card_status, disposition, opened_by, opened_at, closed_by and closed_at. The generated column open_unit_key is an enforcement mechanism (D-012) and is not exposed.
- Constraint: MySQL writes DATETIME values inside a document as plain strings in the form "2026-10-16 01:13:25.000000": a space between date and time, microseconds, no T and no Z. The values are stored in UTC but the document does not say so. The API layer must label or convert them.
- Constraint: SQL NULL appears in a document as JSON null.
- Constraint: A no-change update through a read-only view (setting a field to the value it already has) is accepted silently. A real change is refused with error 6497 (Missing UPDATE tag on the column and path).
- Verification: docs/evidence/day-2/ (V1 to V5, F1 to F5) and database/02_duality_views/.

## D-019 - Nested unit object and measurements array in inspection_card_dv

- Status: Approved
- Date: 2026-10-16
- Decision: Extend the read-only inspection_card_dv in steps. Step 2 adds the production unit as a nested object ("unit": unit_id, unit_serial, work_order_id). Step 3 adds the measurement results as a nested array ("measurements") that carries the measurement_result columns only. unit_id moved from the document root into the nested unit object. The definition (description, unit of measure) is not yet part of the array elements. The view stays read-only (no WITH clause).
- Constraint: The nested single-object pattern and the JSON_ARRAYAGG array pattern both work in a read-only view and agree with the tables (checks W1 to W6 and X1 to X8).
- Constraint: A card that has no measurement_result rows is shown as "measurements": null (JSON null), not as an empty array. The API layer and every client must treat null as empty.
- Constraint: The ETag covers nested data. It changed when only the nested unit row changed, and when only one measurement row changed, while the card row itself was untouched.
- Constraint: The ETag also depends on the view definition. The same card with the same data had three different ETags in D2 steps 1, 2 and 3 as the document grew. An ETag is comparable only within one view definition.
- Implication for D-016 (offline): a cached ETag is valid only for the view version it came from. The offline cache must treat the document shape as a versioned contract and discard cached ETags and documents when the contract changes. A queued edit that conflicts because a nested row changed is a correct conflict, and the conflict screen must say which part changed.
- Constraint: DECIMAL values keep their scale inside a document (1000.250). JSON keys come back in MySQL's normalized order (shorter keys first, then alphabetical), not the order written in the view. Array elements came back in primary-key order in every test, but nothing in the view guarantees that order, so add an explicit order if a client depends on it.
- Constraint: Primary key values are not contiguous (measurement_result ids 1, 2, 4, 5, then 10 and 11). This is consistent with InnoDB allocating ids in batches for the INSERT ... SELECT inside the card trigger, but that cause is not proven. Clients must not assume contiguous ids.
- Verification: docs/evidence/day-2/d2-2-*.txt and d2-3-*.txt; database/02_duality_views/05 to 10.

## D-020 - Two independent nested arrays in inspection_card_dv

- Status: Approved
- Date: 2026-10-16
- Decision: D2 step 4 adds the checklist results as a second nested array ("checklist": checklist_result_id, checklist_definition_id, answer_code, answered_by, answered_at) next to the measurements array and the nested unit object. The view stays read-only (no WITH clause).
- Constraint: Two independent arrays and a nested object coexist in one read-only document and all agree with the tables (checks Y1 to Y8; the step 3 measurements array still matched 4 of 4).
- Constraint: Adding the array changed the ETag of both cards again (see the ETag table in docs/evidence/day-2/d2-step4-summary.md). The rule from D-019 holds: an ETag is comparable only within one view definition.
- Constraint: JSON keys inside the new array come back in the same normalized order as elsewhere: shorter keys first, then alphabetical. Array elements came back in primary-key order again, still not guaranteed.
- Observation (amends the open cause note in D-019): checklist ids are contiguous (1 to 6) while measurement ids skip (1, 2, 4, 5, then 10 and 11). Both are created by the same INSERT ... SELECT in the card trigger, but a card creates 3 checklist rows and 2 measurement rows. That fits InnoDB reserving auto-increment values in growing batches (1, 2, 4) for INSERT ... SELECT: with 2 rows one reserved id is left unused, with 3 rows none is. Counting failed and rolled-back inserts, the hypothesis predicts the observed measurement ids exactly. It is a hypothesis that fits all observations, not a direct test. The practical rule is unchanged: clients must not assume contiguous ids.
- Verification: docs/evidence/day-2/d2-4-create.txt, d2-4-verify.txt, d2-4-probes.txt; database/02_duality_views/11 to 13.

## D-021 - Third nested array (findings) in inspection_card_dv

- Status: Approved
- Date: 2026-10-16
- Decision: D2 step 5 adds the quality findings as a third nested array ("findings": finding_id, severity, finding_status, description, raised_by, raised_at, resolved_at) next to the unit object, the measurements array and the checklist array. The view stays read-only (no WITH clause).
- Constraint: Three independent arrays and a nested object coexist in one read-only document and agree with the tables (checks Z1 to Z8). Element counts were 4, 6 and 1 for measurements, checklist and findings, equal to the table row counts.
- Constraint: A card without findings is shown as "findings": null (JSON null), as for measurements. Card 2 had no findings and showed null; its ETag still changed when the array was added, because the document shape changed.
- Constraint: The ETag covers the findings array. A second finding inserted directly into the table (inside a rolled-back transaction) gave two elements in primary-key order ([1, 2]) and a different ETag (a7406ed8e5cb22ffaabee4c5464c7539 became b803912342788dd9ce2371d8d2239105 for card 1).
- Implication for D-015 (AI assistant): the free-text finding description appears verbatim in the document. Any document that an AI model reads can therefore carry text typed by a user. The agent-facing views must be separate from the application view, and the prompt-injection test required by D-015 must put hostile text in a finding description.
- Constraint: A real change to a findings element was refused with ERROR 6497 and the data was unchanged. The path in the message followed the B-016 pattern (see B-016).
- Side effect: the rolled-back insert advanced the quality_finding AUTO_INCREMENT counter; the next automatic finding id is expected to be 3.
- Verification: docs/evidence/day-2/d2-5-create.txt, d2-5-verify.txt and d2-5-probe-b016.txt; database/02_duality_views/14 to 16.

## D-022 - Attachments array completes the read side of inspection_card_dv

- Status: Approved
- Date: 2026-10-16
- Decision: D2 step 6 adds the attachment metadata as the fourth nested array ("attachments": attachment_id, finding_id, file_name, mime_type, size_bytes, storage_key, uploaded_by, uploaded_at) at card level. With this step the read-only application view inspection_card_dv has a nested unit object and four independent nested arrays (measurements, checklist, findings, attachments). The read side of D2 is complete. The view stays read-only (no WITH clause).
- Constraint: All five parts agree with the tables (checks AA1 to AA8). Element counts were 4, 6, 1 and 2, equal to the table row counts. Attachment elements matched 2 of 2.
- Constraint: A NULL column inside an array element appears as JSON null (attachment 2 has "finding_id": null and matches the table). A card without attachments shows "attachments": null, as for findings. Card 2 has neither findings nor attachments and showed null for both.
- Constraint: The ETag covers the attachments array. A rolled-back direct insert of an attachment for card 2 changed that array from null to an array of one element and changed the ETag of card 2 (a1d3e9312e549f7dad4fb6c001b2532c became 882e4d34e599239d3e06480459e36302).
- Constraint: Attachments are grouped at card level and carry finding_id as a plain field. Attachments nested inside each finding were not tested, so a consumer that wants them grouped per finding must group them itself.
- Constraint: A real change to an attachments element was refused with ERROR 6497, following the B-016 pattern. The data was unchanged afterwards.
- Implication for D-015 (AI assistant): storage_key is an object location and file_name is user-supplied text. The agent-facing views must leave out storage_key and treat file_name as untrusted text, like the finding description (D-021).
- Verification: docs/evidence/day-2/d2-6-create.txt, d2-6-verify.txt and d2-6-probe-short-key.txt; database/02_duality_views/17 to 19.

## D-023 - Separate writable edit view, root close path (D2 step 7a)

- Status: Approved
- Date: 2026-10-16
- Decision: inspection_card_edit_dv is a separate writable view over inspection_card with WITH (UPDATE) on the root object only (no INSERT, no DELETE). It projects _id, card_status, disposition, closed_by and closed_at. The read view inspection_card_dv is unchanged: a regression check showed it still valid, READ_ONLY 1, with the same ETags as in D2 step 6 (3771df75..., a1d3e931...).
- Constraint: Modification tags apply per object, so the fields an object projects are exactly the fields a document can write. unit_id and opened_by are not projected and cannot be written through this view.
- Constraint: Writing a path the view does not project fails with ERROR 6489 "Path '$.x' is not mapped to any column of `quality_inspection`.`inspection_card`." The text is the same for an unknown property (bogus) and for a real table column that the view does not project (opened_by). "Any column" refers to the view mapping, not to the table.
- Constraint: Database rules still apply to document writes. Closing through the document with a pending checklist item raised trigger error 50002; with an open CRITICAL finding it raised 50003; closing without a disposition raised CHECK error 3819 (chk_card_disposition_final); closing with every rule satisfied succeeded. Trigger errors keep their own numbers, so an API can map them to messages.
- Constraint: A string such as "2026-10-16 02:00:00.000000" is accepted for a DATETIME field in a document write; the table stores 2026-10-16 02:00:00.
- Constraint: Optimistic concurrency works in the edit view. A stale document was refused with ERROR 6494 and the card was unchanged.
- Constraint: The ETag reflects the projected document. A direct change to an unprojected column (opened_by) did not change the ETag of the edit-view document (b6f72c3e... before and after). With D-019 to D-022 this fits an ETag derived from the projected content; how MySQL computes it was not examined.
- Constraint: The edit view has its own ETags (root-only version: 9052eccb... for card 1 and b59ab53f... for card 2), different from the read view. A client must read the document from the edit view to get the ETag it must send back when writing. A client that displays the read view and writes through the edit view therefore needs two reads.
- Constraint: The generated column open_unit_key is maintained correctly under document writes: IN_PROGRESS through the document gave open_unit_key 3, and CLOSED through the document gave NULL.
- Constraint: Role permissions are not enforced by the database (D-010). Any account allowed to update through this view can set the projected fields to any value that the CHECK constraints and triggers accept. Reopening a closed card through a document was found possible in D2 step 7b and is now blocked by the final-card lock (superseded: see D-024 and D-025).
- Verification: docs/evidence/day-2/d2-7a-create.txt, d2-7a-verify.txt and d2-7a-writes.txt; database/02_duality_views/20 to 22 and 98.

## D-024 - Edit view with child arrays, and how document writes behave (D2 step 7b)

- Status: Approved
- Date: 2026-10-16
- Decision: inspection_card_edit_dv gains two child arrays, measurements and checklist, each with WITH (UPDATE) on the array objects and no INSERT or DELETE. The measurement array projects measurement_result_id, result_status, measured_value, recorded_by and recorded_at; the checklist array projects checklist_result_id, answer_code, answered_by and answered_at. The definition ids (measurement_definition_id, checklist_definition_id) are not projected, so a document cannot re-point a result at another definition. The read view inspection_card_dv is unchanged (regression check: same ETags as in D2 step 6).
- Constraint: Recording a measurement and answering all three checklist items of an OPEN card through one document each succeeded. DATETIME values are written as strings ("2026-10-16 02:10:00.000000").
- Constraint: A document write that fails is atomic. A valid root change plus an invalid child value (status BOGUS) was refused with ERROR 3819 (chk_measurement_result_status) and the card stayed OPEN. A valid child change plus an invalid root change (CLOSED without closed_by and closed_at) was refused with ERROR 3819 (chk_card_close_fields) and the child stayed PENDING. In the second case two constraints were violated and MySQL reported one; which one it reports first was not examined.
- Constraint: The root object is written before the child rows. Answering all checklist items and closing in ONE document was refused with ERROR 50002 and the checklist stayed PENDING, because the close trigger saw the old answers. A client therefore closes a card in two writes: first the answers, then (after re-reading the document for its new ETag) the close. This was confirmed independently in D2 step 7c: under the first version of the child lock the trigger saw the parent card already CLOSED while child rows were being updated (see D-025, B-017).
- Constraint: A document write issues UPDATE statements for child rows whose values did not change. Under the first version of the child lock triggers, a document that changed only root fields (the close) raised error 50021 from the measurement_result trigger. Any database rule on a child table must therefore ignore updates that change nothing (D-025).
- Constraint: The one-active-card rule holds for document writes. Reopening card 910 through the document while card 911 was active was refused with ERROR 1062 on uq_card_one_active_per_unit. The same document write after card 911 was removed succeeded and set open_unit_key back to 3; that gap is closed by D-025.
- Constraint: An unknown property and a real column that the view does not project, inside an array element, both fail with ERROR 6489 and the message names the child table and the full path (measurement_result, $.measurements[0].bogus; $.measurements[0].measurement_definition_id). The path in these 6489 messages was correct in the arrays of this view, which has no nested single object; this is a different error from 6497 (B-016).
- Constraint: The ETag of the edit view covers its child rows. After one measurement row was changed directly in the table, the card's edit-view ETag changed (4dcf69d3... to ad8d8545...), and writing the old document was refused with ERROR 6494. The edit view has its own ETags (35f30871... for card 1 and aeb1eb08... for card 2), different from the read view, so a client reads the edit view to get the ETag it sends back.
- Verification: docs/evidence/day-2/d2-7b-create.txt, d2-7b-verify.txt and d2-7b-writes.txt; database/02_duality_views/23 to 25.

## D-025 - Final-card lock: a closed or rejected card cannot be changed (enforces Q5)

- Status: Approved
- Date: 2026-10-16
- Decision: Three BEFORE UPDATE triggers enforce Q5 ("a retest is a new card and never an overwrite", D-009) in the database. trg_inspection_card_bu_lock (error 50020) refuses any change to unit_id, card_status, disposition, opened_by, opened_at, closed_by or closed_at of a CLOSED or REJECTED card. trg_measurement_result_bu_lock (50021) and trg_checklist_result_bu_lock (50022) refuse any change to a result row of a CLOSED or REJECTED card. A statement that changes nothing is allowed. The two final states are treated identically; the open question whether REJECTED should need the same close checks as CLOSED (D-011) is unchanged.
- Order: the root lock is created with FOLLOWS trg_inspection_card_bu, so the D1 close-rule trigger runs first (ACTION_ORDER 1) and the lock second (ACTION_ORDER 2). The D1 triggers are not modified.
- Decision: There is no reopen path. A closed card is corrected by opening a new card on the unit. The one-active-card rule (D-012) allows that as soon as the earlier card is final.
- Constraint: Findings and attachment metadata are not locked, so a photo or a resolved finding can be added after a card is final. Direct INSERT or DELETE of result rows is not locked either (the edit view can do neither); a DBA with direct table access can still add a result row to a final card.
- Constraint: The lock triggers are created by the root account with DEFINER quality_app, as in D-013. File 05 holds the first version of the three triggers; file 06 replaces the two child triggers with a version that ignores unchanged rows (B-017). Replay order: 05, then 06. 98_rollback_final_card_lock.sql drops all three.
- Verification: docs/evidence/day-2/d2-7c-before-lock.txt (every test L1 to L5 and P3 succeeded: the gap), d2-7c-after-lock.txt (first version: L3 and L5 gave 50021 instead of 50022, and the legitimate close P2 was refused), d2-7c-after-lock-v2.txt (second version: L1 and L2 gave 50020, L3 and L5 gave 50022, L4 gave 50021, P0 gave 50002, P1 and P2 succeeded, P3 gave 50022; baseline and ETags restored).

## D-026 - D2 backup set and restore rehearsal

- Status: Approved
- Date: 2026-10-16
- Decision: A second backup set, d2-verified-2026-10-16, was taken at Git commit 44b5712 (tag d2-step7-verified) and proven with a restore rehearsal, as D-017 requires. It supersedes the D1 set for everything after D1: the D1 dump has none of the Duality Views or the lock triggers.
- Constraint: The rehearsal proved a restore from the logical dump. The restored server matched the live one on a fingerprint of row counts, table checksums, trigger order, constraint counts, view metadata and the documents of both D2 views with their ETags, and the lock tests raised the expected errors on the restored copy.
- Constraint: Not rehearsed: restore with docker compose, granting the jdv_spike rights before loading the dump, restoring a Docker volume snapshot, and Path B2 (a full rebuild from scripts) as an end-to-end replay on a clean container. A clean-environment replay is still owed before submission (plan phases D8 and D10).
- Constraint: The second copy on different storage (B-012) is still not made for either set. The repository, with its history on GitHub, holds the scripts; only the exact test data state is not stored elsewhere.
- Verification: docs/evidence/day-2/backup/ and docs/runbooks/restore-from-backup.md (A8, the D2 rehearsal result and Path B2).
