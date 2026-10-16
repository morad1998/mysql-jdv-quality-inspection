# AI-3c: gateway function deployment (personal tenancy)

Date: 2026-10-16

Region: `me-riyadh-1`. Compartment: `mysql-jdv-quality-inspection`. Tenancy namespace: `axccntovaczp`.

The build, push, deploy and smoke test were run by the owner in OCI Cloud Shell. The results below are as reported by the owner from that session; they were not re-checked from the laptop when this document was written. OCIDs are not recorded here.

## Result

| Item | Result |
|---|---|
| Fn application | `jdv-ai-app`, recreated with shape `GENERIC_ARM` (see below) |
| Image | `jdv-genai-gateway:0.0.4` |
| Registry repository | `ruh.ocir.io/axccntovaczp/jdv-ai/jdv-genai-gateway` (private) |
| Function | `jdv-genai-gateway` created in `jdv-ai-app` |
| `fdk` installed by the build | `0.1.128`, now pinned in `oci-function/jdv-genai-gateway/requirements.txt` |
| Smoke test | `fn invoke jdv-ai-app jdv-genai-gateway` returned `401 UNAUTHORIZED` (expected) |
| Generative AI call | none; zero inference cost |

## Why the application shape changed to GENERIC_ARM

- The application was first created with shape `GENERIC_X86` (see `ai-3a-infra-inventory.md`).
- In the owner's Cloud Shell session, the build ran on ARM; per that session, building an x86 image there (cross-compilation) was not available.
- The shape of a Functions application cannot be changed after creation, so `jdv-ai-app` was deleted and recreated with shape `GENERIC_ARM`, and the image was built for ARM.
- The recreated application has a new OCID. The local ID file used by the laptop wrapper (`D:\ov\jdv-ai-ids.txt`, outside this repository) still holds the OCID of the first application and must be updated before it is used again.
- Configuration keys expected on the recreated application (names only), as read by `func.py`: `COMPARTMENT_ID`, `MODEL_ID`, `GENAI_REGION`, `API_FORMAT`, `API_KEY_SHA256`.

## What the smoke test proves

The function requires `Authorization: Bearer <gateway key>` (`core.check_key`). `fn invoke` cannot add that header (OCI request signing already uses `Authorization`), so a direct invoke is expected to be refused. The `401 UNAUTHORIZED` answer shows that:

- the image starts and the FDK handler runs on the ARM shape;
- the application configuration is loaded (`API_KEY_SHA256` is present; without it the answer would be `500 NOT_CONFIGURED`);
- the key check refuses a request without the bearer key, before any call to Generative AI.

It does not prove the Generative AI path: the resource principal, the `jdv-ai-policy` permission and the Service Gateway route to the inference endpoint are still untested from inside the function.

## Next step: API Gateway

A real reply needs an API Gateway in front of the function. The gateway forwards the caller's `Authorization` header to the function as `Fn-Http-H-Authorization`, which `core.get_header` already accepts. The public subnet `jdv-ai-gw-subnet` and the policy statement that lets API Gateways in the compartment use `functions-family` are already in place (`ai-3a-infra-inventory.md`). No API Gateway has been created yet.

The function returns only `{"text": ...}`; it does not return token usage. Reporting token counts would need a small change to `oci_chat.py` and `core.py`.

## Open items

- Re-check from the laptop (read-only): application shape and configuration keys, function image tag and digest, repository image count.
- Update `D:\ov\jdv-ai-ids.txt` with the recreated application's OCID and add the function's OCID.
- `ai-3a-infra-inventory.md` still shows the first application (`GENERIC_X86`); this document supersedes that row.
