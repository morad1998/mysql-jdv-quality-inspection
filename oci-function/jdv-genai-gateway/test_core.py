import hashlib
import json
import unittest

import core

KEY = "k" * 64
CFG = {"api_key_sha256": hashlib.sha256(KEY.encode()).hexdigest()}
GOOD_HEADERS = {"Authorization": "Bearer " + KEY}


def body(**over):
    b = {"model": "label", "messages": [{"role": "system", "content": "RULES"}, {"role": "user", "content": "DATA"}], "temperature": 0, "max_tokens": 500}
    b.update(over)
    return json.dumps(b).encode()


class Recorder:
    def __init__(self, reply="hello [card:1]"):
        self.calls = []
        self.reply = reply

    def __call__(self, system, user, temperature, max_tokens):
        self.calls.append((system, user, temperature, max_tokens))
        if isinstance(self.reply, Exception):
            raise self.reply
        return self.reply


class KeyTests(unittest.TestCase):
    def test_accepts_the_right_key_in_any_header_case_and_with_a_gateway_prefix(self):
        for headers in ({"Authorization": "Bearer " + KEY}, {"authorization": "bearer " + KEY}, {"Fn-Http-H-Authorization": "Bearer " + KEY}, {"authorization": ["Bearer " + KEY]}):
            status, out = core.handle(body(), headers, CFG, Recorder())
            self.assertEqual(status, 200, headers)
            self.assertEqual(out, {"text": "hello [card:1]"})

    def test_refuses_missing_wrong_or_malformed_keys_with_the_same_answer_and_never_calls_the_model(self):
        rec = Recorder()
        for headers in ({}, {"Authorization": "Bearer wrong"}, {"Authorization": KEY}, {"Authorization": "Basic " + KEY}, {"Authorization": "Bearer "}):
            status, out = core.handle(body(), headers, CFG, rec)
            self.assertEqual(status, 401, headers)
            self.assertEqual(out["error"]["code"], "UNAUTHORIZED")
        self.assertEqual(rec.calls, [])
        self.assertEqual(len({json.dumps(core.handle(body(), h, CFG, rec)[1]) for h in ({}, {"Authorization": "Bearer wrong"})}), 1)

    def test_answers_500_when_no_key_hash_is_configured(self):
        status, out = core.handle(body(), GOOD_HEADERS, {"api_key_sha256": ""}, Recorder())
        self.assertEqual((status, out["error"]["code"]), (500, "NOT_CONFIGURED"))

    def test_a_hash_in_capitals_with_spaces_still_matches(self):
        cfg = {"api_key_sha256": "  " + CFG["api_key_sha256"].upper() + "\n"}
        self.assertEqual(core.handle(body(), GOOD_HEADERS, cfg, Recorder())[0], 200)


class RequestTests(unittest.TestCase):
    def test_passes_system_user_and_settings_to_the_model_and_ignores_the_requested_model(self):
        rec = Recorder()
        core.handle(body(model="some-expensive-model"), GOOD_HEADERS, CFG, rec)
        self.assertEqual(rec.calls, [("RULES", "DATA", 0, 500)])

    def test_joins_several_messages_and_leaves_unset_options_out(self):
        rec = Recorder()
        raw = json.dumps({"messages": [{"role": "system", "content": "A"}, {"role": "system", "content": "B"}, {"role": "user", "content": "C"}, {"role": "user", "content": "D"}]}).encode()
        core.handle(raw, GOOD_HEADERS, CFG, rec)
        self.assertEqual(rec.calls, [("A\n\nB", "C\n\nD", None, None)])

    def test_rejects_bad_bodies_with_400_and_never_calls_the_model(self):
        rec = Recorder()
        bad = [b"", b"{not json", b"[]", b"\xff\xfe", json.dumps({}).encode(), body(messages=[]), body(messages="x"),
               body(messages=[{"role": "assistant", "content": "x"}]), body(messages=[{"role": "user", "content": ""}]),
               body(messages=[{"role": "user", "content": 5}]), body(messages=[{"role": "system", "content": "only system"}]),
               body(messages=[{"role": "user", "content": "x"}] * 9), body(temperature=3), body(temperature="0"), body(temperature=True),
               body(max_tokens=0), body(max_tokens=4001), body(max_tokens=1.5), body(max_tokens=True)]
        for raw in bad:
            status, out = core.handle(raw, GOOD_HEADERS, CFG, rec)
            self.assertEqual(status, 400, raw[:60])
            self.assertIn("code", out["error"])
        self.assertEqual(rec.calls, [])

    def test_rejects_oversized_bodies_with_413(self):
        self.assertEqual(core.handle(b"x" * (core.MAX_BODY_BYTES + 1), GOOD_HEADERS, CFG, Recorder())[0], 413)
        big = json.dumps({"messages": [{"role": "user", "content": "x" * (core.MAX_TOTAL_CHARS + 1)}]}).encode()
        self.assertEqual(core.handle(big, GOOD_HEADERS, CFG, Recorder())[0], 413)


class ModelTests(unittest.TestCase):
    def test_only_the_allow_listed_model_is_accepted(self):
        core.check_model("cohere.command-a-03-2025")
        for bad in ("", None, "cohere.command-a-reasoning", "meta.llama-3.3-70b-instruct", "COHERE.COMMAND-A-03-2025"):
            with self.assertRaises(core.RequestError) as ctx:
                core.check_model(bad)
            self.assertEqual((ctx.exception.status, ctx.exception.code), (500, "NOT_CONFIGURED"))


class UpstreamTests(unittest.TestCase):
    def test_upstream_failures_become_502_without_the_provider_text(self):
        logs = []
        status, out = core.handle(body(), GOOD_HEADERS, CFG, Recorder(RuntimeError("secret prompt echo: DATA")), logs.append)
        self.assertEqual((status, out["error"]["code"]), (502, "UPSTREAM_ERROR"))
        self.assertNotIn("secret", json.dumps(out))
        self.assertEqual(logs, ["upstream error: RuntimeError"])

    def test_an_empty_answer_is_an_error_not_a_success(self):
        for reply in ("", "   ", None):
            status, out = core.handle(body(), GOOD_HEADERS, CFG, Recorder(reply))
            self.assertEqual((status, out["error"]["code"]), (502, "EMPTY_ANSWER"))

    def test_a_configuration_error_raised_by_the_chat_function_is_returned_as_it_is(self):
        status, out = core.handle(body(), GOOD_HEADERS, CFG, Recorder(core.RequestError(500, "NOT_CONFIGURED", "The function is not configured.")))
        self.assertEqual((status, out["error"]["code"]), (500, "NOT_CONFIGURED"))

    def test_nothing_ever_raises(self):
        status, out = core.handle(body(), GOOD_HEADERS, None, Recorder())
        self.assertEqual(status, 500)


if __name__ == "__main__":
    unittest.main()
