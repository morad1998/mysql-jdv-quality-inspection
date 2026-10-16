"""
The only file that talks to OCI Generative AI. It is NOT covered by the unit tests: it needs a real tenancy.
It authenticates as the function itself (resource principal), so no key file is stored anywhere.
Two request formats are supported, chosen by the configuration: GENERIC (Llama, gpt-oss, Gemini and Grok models) and COHERE.
"""
import oci
from oci.generative_ai_inference import models as m


def make_chat_fn(cfg):
    signer = oci.auth.signers.get_resource_principals_signer()
    endpoint = "https://inference.generativeai.%s.oci.oraclecloud.com" % cfg["region"]
    client = oci.generative_ai_inference.GenerativeAiInferenceClient(
        config={}, signer=signer, service_endpoint=endpoint,
        retry_strategy=oci.retry.NoneRetryStrategy(), timeout=(10, 110),
    )
    serving = m.OnDemandServingMode(model_id=cfg["model_id"])
    api_format = (cfg.get("api_format") or "COHERE").upper()

    def chat(system, user, temperature, max_tokens):
        if api_format == "COHERE":
            req = m.CohereChatRequest(message=user, preamble_override=system or None, temperature=temperature, max_tokens=max_tokens, is_stream=False)
        else:
            msgs = []
            if system:
                msgs.append(m.SystemMessage(content=[m.TextContent(text=system)]))
            msgs.append(m.UserMessage(content=[m.TextContent(text=user)]))
            req = m.GenericChatRequest(api_format=m.BaseChatRequest.API_FORMAT_GENERIC, messages=msgs, temperature=temperature, max_tokens=max_tokens, is_stream=False)
        details = m.ChatDetails(compartment_id=cfg["compartment_id"], serving_mode=serving, chat_request=req)
        resp = client.chat(details).data.chat_response
        if api_format == "COHERE":
            return resp.text
        return "".join(c.text for c in resp.choices[0].message.content if getattr(c, "text", None))

    return chat
