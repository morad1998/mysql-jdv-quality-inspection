"""
Request handling for the Generative AI gateway function. No OCI code in this file: the call to the model is a function that
is passed in, so everything here is tested without a cloud account.

Contract (also in docs/ai/README.md of the repository):
  POST   Authorization: Bearer <key>      (the function holds only the SHA-256 hash of the key)
  body   {"model": "label, ignored", "messages": [{"role": "system"|"user", "content": "..."}], "temperature": 0, "max_tokens": 1200}
  200    {"text": "the model's answer"}
  errors {"error": {"code": "...", "message": "..."}} with 400, 401, 413, 500 or 502
The model that is called is chosen by the function's own configuration, never by the request.
"""
import hashlib
import hmac
import json

MAX_BODY_BYTES = 400_000
MAX_MESSAGES = 8
MAX_TOTAL_CHARS = 300_000
MAX_TOKENS_CAP = 4000
ALLOWED_ROLES = ("system", "user")
ALLOWED_MODEL_IDS = ("cohere.command-a-03-2025",)  # the only on-demand Command A model in me-riyadh-1


class RequestError(Exception):
    def __init__(self, status, code, message):
        super().__init__(message)
        self.status = status
        self.code = code
        self.message = message


def get_header(headers, name):
    """Case-insensitive header lookup. An API Gateway can prefix forwarded headers (for example Fn-Http-H-Authorization)."""
    wanted = name.lower()
    for key, value in (headers or {}).items():
        k = str(key).lower()
        if k == wanted or k.endswith("-h-" + wanted):
            return value if isinstance(value, str) else (value[0] if value else None)
    return None


def check_key(headers, expected_sha256):
    if not expected_sha256:
        raise RequestError(500, "NOT_CONFIGURED", "The function is not configured.")
    auth = get_header(headers, "authorization")
    prefix = "bearer "
    if not auth or not auth.lower().startswith(prefix):
        raise RequestError(401, "UNAUTHORIZED", "A valid bearer key is required.")
    presented = hashlib.sha256(auth[len(prefix):].strip().encode("utf-8")).hexdigest()
    if not hmac.compare_digest(presented, expected_sha256.strip().lower()):
        raise RequestError(401, "UNAUTHORIZED", "A valid bearer key is required.")


def check_model(model_id):
    """The configured model must be on the allow-list. Same answer as a missing setting: no detail leaks to the caller."""
    if model_id not in ALLOWED_MODEL_IDS:
        raise RequestError(500, "NOT_CONFIGURED", "The function is not configured.")


def parse_request(raw):
    if raw is None or len(raw) == 0:
        raise RequestError(400, "INVALID_BODY", "Send a JSON object as the request body.")
    if len(raw) > MAX_BODY_BYTES:
        raise RequestError(413, "BODY_TOO_LARGE", "The request body is too large.")
    try:
        body = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, ValueError):
        raise RequestError(400, "INVALID_JSON", "The request body is not valid JSON.")
    if not isinstance(body, dict):
        raise RequestError(400, "INVALID_BODY", "Send a JSON object as the request body.")

    messages = body.get("messages")
    if not isinstance(messages, list) or not messages or len(messages) > MAX_MESSAGES:
        raise RequestError(400, "INVALID_MESSAGES", "messages must be a list of 1 to %d entries." % MAX_MESSAGES)
    system_parts, user_parts, total = [], [], 0
    for m in messages:
        if not isinstance(m, dict) or m.get("role") not in ALLOWED_ROLES or not isinstance(m.get("content"), str) or not m["content"].strip():
            raise RequestError(400, "INVALID_MESSAGES", "Each message needs a role (system or user) and non-empty text content.")
        total += len(m["content"])
        (system_parts if m["role"] == "system" else user_parts).append(m["content"])
    if total > MAX_TOTAL_CHARS:
        raise RequestError(413, "BODY_TOO_LARGE", "The messages are too long.")
    if not user_parts:
        raise RequestError(400, "INVALID_MESSAGES", "At least one user message is required.")

    temperature = body.get("temperature")
    if temperature is not None:
        if isinstance(temperature, bool) or not isinstance(temperature, (int, float)) or not 0 <= temperature <= 2:
            raise RequestError(400, "INVALID_TEMPERATURE", "temperature must be a number from 0 to 2.")
    max_tokens = body.get("max_tokens")
    if max_tokens is not None:
        if isinstance(max_tokens, bool) or not isinstance(max_tokens, int) or not 1 <= max_tokens <= MAX_TOKENS_CAP:
            raise RequestError(400, "INVALID_MAX_TOKENS", "max_tokens must be a whole number from 1 to %d." % MAX_TOKENS_CAP)

    return {
        "system": "\n\n".join(system_parts),
        "user": "\n\n".join(user_parts),
        "temperature": temperature,
        "max_tokens": max_tokens,
    }


def handle(raw, headers, cfg, chat_fn, log=lambda line: None):
    """Returns (http_status, body_dict). Never raises: every failure becomes an answer without internal details."""
    try:
        check_key(headers, cfg.get("api_key_sha256"))
        req = parse_request(raw)
        try:
            text = chat_fn(req["system"], req["user"], req["temperature"], req["max_tokens"])
        except RequestError:
            raise
        except Exception as err:  # the provider's message can echo the prompt: log the type only, never return the text
            log("upstream error: %s" % type(err).__name__)
            raise RequestError(502, "UPSTREAM_ERROR", "The model service could not answer.")
        if not isinstance(text, str) or not text.strip():
            raise RequestError(502, "EMPTY_ANSWER", "The model service returned no text.")
        return 200, {"text": text}
    except RequestError as e:
        return e.status, {"error": {"code": e.code, "message": e.message}}
    except Exception as err:
        log("internal error: %s" % type(err).__name__)
        return 500, {"error": {"code": "INTERNAL_ERROR", "message": "Unexpected error."}}
