# AI-2a: OCI Generative AI probe (personal tenancy)

Date: 2026-10-16

Script: `scripts/oci-genai-probe.ps1`, run once from the repository root with no parameters.

## Result

| Item | Value |
|---|---|
| Region | `me-riyadh-1` (Saudi Arabia Central, Riyadh) |
| Model | `cohere.command-a-03-2025` |
| Compartment | `mysql-jdv-quality-inspection` (OCID looked up by name at run time; not recorded) |
| Serving mode | `ON_DEMAND` |
| Request format | COHERE (`generative-ai-inference chat-result chat-cohere-chat-request`, oci-cli 3.95.0) |
| Message | `Reply with OK.` |
| Max output tokens | 50 |
| Latency | 2567 ms |
| Tokens | prompt 4, completion 2, total 6 |
| Reply | `OK.` |
| Exit code | 0 |

Raw output:

```
Region: me-riyadh-1   Model: cohere.command-a-03-2025   Compartment: mysql-jdv-quality-inspection
Reply (2567 ms): OK.
Tokens: prompt 4, completion 2, total 6
```

## Account and configuration

- Every OCI call goes through the local wrapper `D:\ov\ocip.ps1`, which uses only the personal config file `%USERPROFILE%\.oci-personal\config` and the `PERSONAL` profile. The script itself never reads an OCI config file and never chooses a profile.
- The original `%USERPROFILE%\.oci\config` was not read or changed. Its SHA-256 hash was the same before and after the run.
- Two OCI calls in total: one free compartment lookup and one paid chat call (6 tokens). No resources were created.

## Model availability in Riyadh

Of the Command A family, only `cohere.command-a-03-2025` is available on demand in `me-riyadh-1`. `cohere.command-a-reasoning` and `cohere.command-a-vision` are listed there as ACTIVE but are served on dedicated AI clusters only, so an on-demand call to them would fail. Source: Oracle's "Generative AI Models by Region" page, checked on the same date.
