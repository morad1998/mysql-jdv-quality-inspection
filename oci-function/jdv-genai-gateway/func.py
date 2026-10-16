import io
import json
import os
import sys

from fdk import response

import core

_chat_fn = None


def _config():
    return {
        "api_key_sha256": os.environ.get("API_KEY_SHA256", ""),
        "compartment_id": os.environ.get("COMPARTMENT_ID", ""),
        "model_id": os.environ.get("MODEL_ID", ""),
        "region": os.environ.get("GENAI_REGION", ""),
        "api_format": os.environ.get("API_FORMAT", "COHERE"),
    }


def _log(line):
    print(line, file=sys.stderr)


def handler(ctx, data: io.BytesIO = None):
    global _chat_fn
    cfg = _config()
    raw = data.getvalue() if data is not None else b""

    def chat(system, user, temperature, max_tokens):
        global _chat_fn
        missing = [k for k in ("compartment_id", "model_id", "region") if not cfg[k]]
        if missing:
            raise core.RequestError(500, "NOT_CONFIGURED", "The function is not configured.")
        core.check_model(cfg["model_id"])
        if _chat_fn is None:
            import oci_chat  # imported late so a configuration error is reported as an answer, not a crash
            _chat_fn = oci_chat.make_chat_fn(cfg)
        return _chat_fn(system, user, temperature, max_tokens)

    status, body = core.handle(raw, ctx.Headers(), cfg, chat, _log)
    return response.Response(ctx, response_data=json.dumps(body), headers={"Content-Type": "application/json"}, status_code=status)
