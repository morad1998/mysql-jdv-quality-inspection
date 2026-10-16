# AI-3a: OCI infrastructure inventory (personal tenancy)

Date: 2026-10-16

Region: `me-riyadh-1` (Saudi Arabia Central, Riyadh). Compartment: `mysql-jdv-quality-inspection`. Identity domain: `Default`.

Every resource below was created through the local wrapper `D:\ov\ocip.ps1`, which uses only the personal config file and the `PERSONAL` profile. The original `%USERPROFILE%\.oci\config` was not read or changed; its SHA-256 hash was the same before and after every phase. OCIDs are kept in a local file outside this repository (`D:\ov\jdv-ai-ids.txt`) and are not recorded here.

This document records the state verified by read-only checks in the same session. It was written without new OCI calls.

## Network

| Resource | Name | Detail |
|---|---|---|
| VCN | `jdv-ai-vcn` | `10.20.0.0/16`, DNS label `jdvaivcn` |
| Internet Gateway | `jdv-ai-igw` | enabled |
| Service Gateway | `jdv-ai-sgw` | `All RUH Services In Oracle Services Network` |
| NAT Gateway | none | not needed: Generative AI inference, Container Registry and Functions are reachable through the Service Gateway |

### Subnets (both regional)

| Subnet | CIDR | Type | `prohibit-public-ip-on-vnic` | Route table | Security list |
|---|---|---|---|---|---|
| `jdv-ai-gw-subnet` | `10.20.1.0/24` | public (for a future API Gateway) | `false` | `jdv-ai-gw-rt` | `jdv-ai-gw-sl` |
| `jdv-ai-fn-subnet` | `10.20.2.0/24` | private (for the function) | `true` | `jdv-ai-fn-rt` | `jdv-ai-fn-sl` |

### Route tables

| Route table | Rules |
|---|---|
| `jdv-ai-gw-rt` | `0.0.0.0/0` (CIDR_BLOCK) -> `jdv-ai-igw` |
| `jdv-ai-fn-rt` | `all-ruh-services-in-oracle-services-network` (SERVICE_CIDR_BLOCK) -> `jdv-ai-sgw` |
| Default Route Table for `jdv-ai-vcn` | no rules; not used by either subnet |

### Security lists (all rules stateful)

| Security list | Ingress | Egress |
|---|---|---|
| `jdv-ai-gw-sl` | TCP 443 from `0.0.0.0/0` | TCP 443 to `0.0.0.0/0` |
| `jdv-ai-fn-sl` | none | TCP 443 to `all-ruh-services-in-oracle-services-network` |
| Default Security List for `jdv-ai-vcn` | none (the 3 default ingress rules, including SSH 22, were removed) | all protocols to `0.0.0.0/0` (kept) |

The function subnet has no ingress on purpose: callers reach a function through the Functions service invoke endpoint, not through an address in the subnet.

## Container registry

| Repository | Visibility | Images | Compartment |
|---|---|---|---|
| `jdv-ai/jdv-genai-gateway` | private | 0 | `mysql-jdv-quality-inspection` |

Registry endpoint for the region: `ruh.ocir.io`.

## Identity and access

### Dynamic group (Default identity domain)

| Name | Matching rule |
|---|---|
| `jdv-ai-fn-dg` | `ALL {resource.type = 'fnfunc', resource.compartment.id = '<mysql-jdv-quality-inspection compartment OCID>'}` |

The identity domains API returns the matching rule only when the `matchingRule` attribute is requested; the stored rule was confirmed that way.

### Policy `jdv-ai-policy` (attached to the compartment)

```
Allow dynamic-group jdv-ai-fn-dg to use generative-ai-chat in compartment mysql-jdv-quality-inspection
Allow any-user to use functions-family in compartment mysql-jdv-quality-inspection where ALL {request.principal.type = 'ApiGateway', request.resource.compartment.id = '<mysql-jdv-quality-inspection compartment OCID>'}
```

- `generative-ai-chat` is narrower than `generative-ai-family`: it grants only the chat operation.
- No `read repos` statement: Oracle's Functions documentation does not list one for pulling an image from a repository in the same tenancy.
- No `Allow service faas to use virtual-network-family` statement: current Functions documentation gives only a user-group network statement. Revisit if the deploy or an invoke fails on networking.
- Policy and dynamic group changes can take up to 15 minutes to reach a function (resource principal token cache).

## Functions

| Application | State | Shape | Subnet |
|---|---|---|---|
| `jdv-ai-app` | ACTIVE | `GENERIC_X86` | `jdv-ai-fn-subnet` |

Application configuration (names only; inherited by its functions and read by `func.py`):

| Key | Purpose |
|---|---|
| `COMPARTMENT_ID` | compartment billed for the Generative AI call |
| `MODEL_ID` | the model to call; must be on the allow-list in `core.py` |
| `GENAI_REGION` | region of the inference endpoint |
| `API_FORMAT` | request format (`COHERE`) |
| `API_KEY_SHA256` | SHA-256 hash of the gateway key; the key itself is only in the untracked `.env` (`AI_OCI_API_KEY`) |

## Not created yet

- **No function image has been deployed.** The repository holds 0 images and `jdv-ai-app` has no function.
- **No API Gateway.** The public subnet and the `functions-family` policy statement are ready for one.
- No NAT Gateway (not needed).

## Sources

- Service Gateway supported services (Generative AI Service Inference API, OCI Container Registry, Functions Service API): https://www.oracle.com/cloud/networking/private-service-access/service-gateway-and-psa-supported-services/
- Functions, private subnet needs a service gateway: https://docs.oracle.com/en-us/iaas/Content/Functions/Tasks/functionscreatingapps.htm
- API Gateway VCN and port 443 rule: https://docs.oracle.com/iaas/Content/APIGateway/Tasks/apigatewaycreatingvcn.htm
- Function dynamic group rule: https://docs.oracle.com/en-us/iaas/Content/Functions/Tasks/functionsaccessingociresources.htm
- API Gateway access to functions: https://docs.oracle.com/en-us/iaas/Content/APIGateway/Tasks/apigatewaycreatingpolicies.htm
- Generative AI chat permission: https://docs.oracle.com/en-us/iaas/Content/generative-ai/chat-permissions.htm
- Functions policies: https://docs.oracle.com/en-us/iaas/Content/Functions/Tasks/functionscreatingpolicies.htm
- Registry endpoints: https://docs.oracle.com/en-us/iaas/Content/Registry/Concepts/registryprerequisites.htm
