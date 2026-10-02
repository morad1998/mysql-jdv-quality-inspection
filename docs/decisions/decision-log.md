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
