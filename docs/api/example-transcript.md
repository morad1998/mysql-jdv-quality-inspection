# Example requests and recorded responses

Recorded by api/examples/run-examples.ts at 2026-10-16T03:40:15.250Z against http://127.0.0.1:3000. Demo authentication only.

## 1. Health check (no user needed)

```http
GET /api/health
```

```http
200 OK

{
  "status": "ok"
}
```

## 2. Open a card on unit SN-DEMO-0002 (a plain INSERT; a trigger creates the PENDING rows)

```http
POST /api/cards
X-Demo-User: inspector1
Content-Type: application/json

{
  "unit_serial": "SN-DEMO-0002"
}
```

```http
201 Created
etag: "ea93023f4f5e782eb6d20869307e18ba"
location: /api/cards/939

{
  "_id": 939,
  "unit": {
    "unit_id": 2,
    "unit_serial": "SN-DEMO-0002",
    "work_order_id": 1
  },
  "findings": null,
  "_metadata": {
    "etag": "ea93023f4f5e782eb6d20869307e18ba"
  },
  "checklist": [
    {
      "answer_code": "PENDING",
      "answered_at": null,
      "answered_by": null,
      "checklist_result_id": 58,
      "checklist_definition_id": 1
    },
    {
      "answer_code": "PENDING",
      "answered_at": null,
      "answered_by": null,
      "checklist_result_id": 59,
      "checklist_definition_id": 2
    },
    {
      "answer_code": "PENDING",
      "answered_at": null,
      "answered_by": null,
      "checklist_result_id": 60,
      "checklist_definition_id": 3
    }
  ],
  "closed_at": null,
  "closed_by": null,
  "opened_at": "2026-10-16 03:40:15.000000",
  "opened_by": 1,
  "attachments": null,
  "card_status": "OPEN",
  "disposition": null,
  "measurements": [
    {
      "recorded_at": null,
      "recorded_by": null,
      "result_status": "PENDING",
      "measured_value": null,
      "measurement_result_id": 58,
      "measurement_definition_id": 1
    },
    {
      "recorded_at": null,
      "recorded_by": null,
      "result_status": "PENDING",
      "measured_value": null,
      "measurement_result_id": 59,
      "measurement_definition_id": 2
    }
  ]
}
```

## 3. Opening a second card on the same unit is refused by the database (one-active-card rule, error 1062)

```http
POST /api/cards
X-Demo-User: inspector1
Content-Type: application/json

{
  "unit_serial": "SN-DEMO-0002"
}
```

```http
409 Conflict

{
  "error": {
    "code": "ACTIVE_CARD_EXISTS",
    "message": "The unit already has an open card. Close it before opening another.",
    "db_errno": 1062
  }
}
```

## 4. Read the card for display (read view; note the nested unit and the four arrays)

```http
GET /api/cards/939
X-Demo-User: inspector1
```

```http
200 OK
etag: "ea93023f4f5e782eb6d20869307e18ba"
link: </api/cards/939/edit>; rel="edit"

{
  "_id": 939,
  "unit": {
    "unit_id": 2,
    "unit_serial": "SN-DEMO-0002",
    "work_order_id": 1
  },
  "findings": null,
  "_metadata": {
    "etag": "ea93023f4f5e782eb6d20869307e18ba"
  },
  "checklist": [
    {
      "answer_code": "PENDING",
      "answered_at": null,
      "answered_by": null,
      "checklist_result_id": 58,
      "checklist_definition_id": 1
    },
    {
      "answer_code": "PENDING",
      "answered_at": null,
      "answered_by": null,
      "checklist_result_id": 59,
      "checklist_definition_id": 2
    },
    {
      "answer_code": "PENDING",
      "answered_at": null,
      "answered_by": null,
      "checklist_result_id": 60,
      "checklist_definition_id": 3
    }
  ],
  "closed_at": null,
  "closed_by": null,
  "opened_at": "2026-10-16 03:40:15.000000",
  "opened_by": 1,
  "attachments": null,
  "card_status": "OPEN",
  "disposition": null,
  "measurements": [
    {
      "recorded_at": null,
      "recorded_by": null,
      "result_status": "PENDING",
      "measured_value": null,
      "measurement_result_id": 58,
      "measurement_definition_id": 1
    },
    {
      "recorded_at": null,
      "recorded_by": null,
      "result_status": "PENDING",
      "measured_value": null,
      "measurement_result_id": 59,
      "measurement_definition_id": 2
    }
  ]
}
```

## 5. Read the card for editing (edit view; its ETag differs from the read view)

```http
GET /api/cards/939/edit
X-Demo-User: inspector1
```

```http
200 OK
etag: "ba8de0d1809efc630857853f893604dd"

{
  "_id": 939,
  "_metadata": {
    "etag": "ba8de0d1809efc630857853f893604dd"
  },
  "checklist": [
    {
      "answer_code": "PENDING",
      "answered_at": null,
      "answered_by": null,
      "checklist_result_id": 58
    },
    {
      "answer_code": "PENDING",
      "answered_at": null,
      "answered_by": null,
      "checklist_result_id": 59
    },
    {
      "answer_code": "PENDING",
      "answered_at": null,
      "answered_by": null,
      "checklist_result_id": 60
    }
  ],
  "closed_at": null,
  "closed_by": null,
  "card_status": "OPEN",
  "disposition": null,
  "measurements": [
    {
      "recorded_at": null,
      "recorded_by": null,
      "result_status": "PENDING",
      "measured_value": null,
      "measurement_result_id": 58
    },
    {
      "recorded_at": null,
      "recorded_by": null,
      "result_status": "PENDING",
      "measured_value": null,
      "measurement_result_id": 59
    }
  ]
}
```

## 6. A stale ETag is refused with 412 and the current document is returned

```http
PUT /api/cards/939/edit
X-Demo-User: inspector1
If-Match: "00000000000000000000000000000000"
Content-Type: application/json

{
  "checklist": [
    {
      "checklist_result_id": 58,
      "answer_code": "YES"
    }
  ]
}
```

```http
412 Precondition Failed
etag: "ba8de0d1809efc630857853f893604dd"

{
  "error": {
    "code": "STALE_ETAG",
    "message": "The card was changed after you read it. The current version is in this response; read it, apply your change to it, and retry."
  },
  "current": {
    "etag": "ba8de0d1809efc630857853f893604dd",
    "document": {
      "_id": 939,
      "_metadata": {
        "etag": "ba8de0d1809efc630857853f893604dd"
      },
      "checklist": [
        {
          "answer_code": "PENDING",
          "answered_at": null,
          "answered_by": null,
          "checklist_result_id": 58
        },
        {
          "answer_code": "PENDING",
          "answered_at": null,
          "answered_by": null,
          "checklist_result_id": 59
        },
        {
          "answer_code": "PENDING",
          "answered_at": null,
          "answered_by": null,
          "checklist_result_id": 60
        }
      ],
      "closed_at": null,
      "closed_by": null,
      "card_status": "OPEN",
      "disposition": null,
      "measurements": [
        {
          "recorded_at": null,
          "recorded_by": null,
          "result_status": "PENDING",
          "measured_value": null,
          "measurement_result_id": 58
        },
        {
          "recorded_at": null,
          "recorded_by": null,
          "result_status": "PENDING",
          "measured_value": null,
          "measurement_result_id": 59
        }
      ]
    }
  }
}
```

## 7. Only a SUPERVISOR may close

```http
POST /api/cards/939/close
X-Demo-User: inspector1
If-Match: "ba8de0d1809efc630857853f893604dd"
Content-Type: application/json

{
  "disposition": "PASS"
}
```

```http
403 Forbidden

{
  "error": {
    "code": "FORBIDDEN",
    "message": "Only a SUPERVISOR may do this."
  }
}
```

## 8. Closing with unanswered checklist items is refused by the database (trigger error 50002)

```http
POST /api/cards/939/close
X-Demo-User: supervisor1
If-Match: "ba8de0d1809efc630857853f893604dd"
Content-Type: application/json

{
  "disposition": "PASS"
}
```

```http
409 Conflict

{
  "error": {
    "code": "CHECKLIST_INCOMPLETE",
    "message": "The card cannot be closed: at least one checklist item is still unanswered.",
    "db_errno": 50002
  }
}
```

## 9. Write step one: answer every checklist item and record a measurement

```http
PUT /api/cards/939/edit
X-Demo-User: inspector2
If-Match: "ba8de0d1809efc630857853f893604dd"
Content-Type: application/json

{
  "checklist": [
    {
      "checklist_result_id": 58,
      "answer_code": "YES"
    },
    {
      "checklist_result_id": 59,
      "answer_code": "YES"
    },
    {
      "checklist_result_id": 60,
      "answer_code": "YES"
    }
  ],
  "measurements": [
    {
      "measurement_result_id": 58,
      "result_status": "RECORDED",
      "measured_value": 1000.125
    }
  ]
}
```

```http
200 OK
etag: "2c4d312b9cf06769a5ae01e3f7362f9b"

{
  "_id": 939,
  "_metadata": {
    "etag": "2c4d312b9cf06769a5ae01e3f7362f9b"
  },
  "checklist": [
    {
      "answer_code": "YES",
      "answered_at": "2026-10-16 03:40:15.000000",
      "answered_by": 2,
      "checklist_result_id": 58
    },
    {
      "answer_code": "YES",
      "answered_at": "2026-10-16 03:40:15.000000",
      "answered_by": 2,
      "checklist_result_id": 59
    },
    {
      "answer_code": "YES",
      "answered_at": "2026-10-16 03:40:15.000000",
      "answered_by": 2,
      "checklist_result_id": 60
    }
  ],
  "closed_at": null,
  "closed_by": null,
  "card_status": "OPEN",
  "disposition": null,
  "measurements": [
    {
      "recorded_at": "2026-10-16 03:40:15.000000",
      "recorded_by": 2,
      "result_status": "RECORDED",
      "measured_value": 1000.125,
      "measurement_result_id": 58
    },
    {
      "recorded_at": null,
      "recorded_by": null,
      "result_status": "PENDING",
      "measured_value": null,
      "measurement_result_id": 59
    }
  ]
}
```

## 10. An unknown property is refused by the API before it reaches the database

```http
PUT /api/cards/939/edit
X-Demo-User: inspector1
If-Match: "2c4d312b9cf06769a5ae01e3f7362f9b"
Content-Type: application/json

{
  "bogus": 1
}
```

```http
400 Bad Request

{
  "error": {
    "code": "UNKNOWN_PROPERTY",
    "message": "Property 'bogus' is not accepted in the request."
  }
}
```

## 11. Write step two: close the card with the ETag from step one

```http
POST /api/cards/939/close
X-Demo-User: supervisor1
If-Match: "2c4d312b9cf06769a5ae01e3f7362f9b"
Content-Type: application/json

{
  "disposition": "PASS"
}
```

```http
200 OK
etag: "9779815b93041208eae32ede74ce686a"

{
  "_id": 939,
  "_metadata": {
    "etag": "9779815b93041208eae32ede74ce686a"
  },
  "checklist": [
    {
      "answer_code": "YES",
      "answered_at": "2026-10-16 03:40:15.000000",
      "answered_by": 2,
      "checklist_result_id": 58
    },
    {
      "answer_code": "YES",
      "answered_at": "2026-10-16 03:40:15.000000",
      "answered_by": 2,
      "checklist_result_id": 59
    },
    {
      "answer_code": "YES",
      "answered_at": "2026-10-16 03:40:15.000000",
      "answered_by": 2,
      "checklist_result_id": 60
    }
  ],
  "closed_at": "2026-10-16 03:40:15.000000",
  "closed_by": 3,
  "card_status": "CLOSED",
  "disposition": "PASS",
  "measurements": [
    {
      "recorded_at": "2026-10-16 03:40:15.000000",
      "recorded_by": 2,
      "result_status": "RECORDED",
      "measured_value": 1000.125,
      "measurement_result_id": 58
    },
    {
      "recorded_at": null,
      "recorded_by": null,
      "result_status": "PENDING",
      "measured_value": null,
      "measurement_result_id": 59
    }
  ]
}
```

## 12. Read the closed card for editing

```http
GET /api/cards/939/edit
X-Demo-User: inspector1
```

```http
200 OK
etag: "9779815b93041208eae32ede74ce686a"

{
  "_id": 939,
  "_metadata": {
    "etag": "9779815b93041208eae32ede74ce686a"
  },
  "checklist": [
    {
      "answer_code": "YES",
      "answered_at": "2026-10-16 03:40:15.000000",
      "answered_by": 2,
      "checklist_result_id": 58
    },
    {
      "answer_code": "YES",
      "answered_at": "2026-10-16 03:40:15.000000",
      "answered_by": 2,
      "checklist_result_id": 59
    },
    {
      "answer_code": "YES",
      "answered_at": "2026-10-16 03:40:15.000000",
      "answered_by": 2,
      "checklist_result_id": 60
    }
  ],
  "closed_at": "2026-10-16 03:40:15.000000",
  "closed_by": 3,
  "card_status": "CLOSED",
  "disposition": "PASS",
  "measurements": [
    {
      "recorded_at": "2026-10-16 03:40:15.000000",
      "recorded_by": 2,
      "result_status": "RECORDED",
      "measured_value": 1000.125,
      "measurement_result_id": 58
    },
    {
      "recorded_at": null,
      "recorded_by": null,
      "result_status": "PENDING",
      "measured_value": null,
      "measurement_result_id": 59
    }
  ]
}
```

## 13. A closed card is read-only: the database lock answers 50022 and the API maps it to 409

```http
PUT /api/cards/939/edit
X-Demo-User: inspector1
If-Match: "9779815b93041208eae32ede74ce686a"
Content-Type: application/json

{
  "checklist": [
    {
      "checklist_result_id": 58,
      "answer_code": "NO"
    }
  ]
}
```

```http
409 Conflict

{
  "error": {
    "code": "CARD_FINAL",
    "message": "A closed card cannot be changed. Open a new card on the unit instead.",
    "db_errno": 50022
  }
}
```

## 14. List the cards

```http
GET /api/cards
X-Demo-User: inspector1
```

```http
200 OK

{
  "cards": [
    {
      "card_id": 1,
      "card_status": "CLOSED",
      "disposition": "PASS",
      "unit_serial": "SN-DEMO-0001"
    },
    {
      "card_id": 2,
      "card_status": "REJECTED",
      "disposition": "REJECT",
      "unit_serial": "SN-DEMO-0001"
    },
    {
      "card_id": 939,
      "card_status": "CLOSED",
      "disposition": "PASS",
      "unit_serial": "SN-DEMO-0002"
    }
  ]
}
```

