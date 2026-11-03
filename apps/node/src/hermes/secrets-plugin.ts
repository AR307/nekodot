import { randomBytes } from 'node:crypto';
import { mkdir, access, writeFile } from 'node:fs/promises';
import { join } from 'node:path';

const plugin = String.raw`"""Confidential UI adapter. No secret values are returned by CLI commands."""
import json
import os
import socket


def _call(operation, **params):
    from hermes_constants import get_hermes_home
    from hermes_cli.config import load_config
    home = get_hermes_home()
    settings = load_config().get("plugins", {}).get("entries", {}).get("nekodot-secrets", {})
    token = (home / "plugins" / "nekodot-secrets" / "bridge.token").read_text().strip()
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
        client.settimeout(30)
        client.connect(settings["socket"])
        client.sendall((json.dumps(dict(action="secret", operation=operation, botId=home.name,
            token=token, sessionId=os.environ.get("HERMES_SESSION_ID", ""), **params)) + "\n").encode())
        data = b""
        while not data.endswith(b"\n"):
            chunk = client.recv(65536)
            if not chunk:
                raise RuntimeError("Confidential bridge disconnected")
            data += chunk
    response = json.loads(data)
    if not response.get("ok"):
        raise RuntimeError("Confidential operation failed; open the nekodot card for status")
    return response["result"]


def _setup(parser):
    commands = parser.add_subparsers(dest="secret_action", required=True)
    request = commands.add_parser("request")
    request.add_argument("--spec", required=True, help="Metadata JSON only; never put secret values here")
    for name in ("status", "apply"):
        command = commands.add_parser(name)
        command.add_argument("reference")


def _command(args):
    if args.secret_action == "request":
        result = _call("request", spec=json.loads(args.spec))
    else:
        result = _call(args.secret_action, requestId=args.reference)
    print(json.dumps(result, ensure_ascii=False))


def _scrub(result=None, output=None, **kwargs):
    value = result if result is not None else output
    if value is None:
        return None
    encoded = value if isinstance(value, str) else json.dumps(value, ensure_ascii=False)
    cleaned = _call("scrub", text=encoded)
    from agent.vault_store import get_vault_store
    for item in get_vault_store().list_items():
        if item.identifier:
            cleaned = cleaned.replace(item.identifier, "[confidential identifier]")
    return cleaned if cleaned != encoded else None


def _browser(args, task_id="default", **kwargs):
    from agent.vault_store import get_vault_store, normalize_origin
    from agent.redact import register_vault_redaction_value
    from tools.browser_vault_tool import (browser_vault_fill, _current_page_origin,
        _eval_js_secret, _fenced_page_op, _parse_json_result, _focus_bound_origin)
    reference = args["reference"]
    request = _call("status", requestId=reference)
    if request["state"] not in ("applied", "delivered"):
        return json.dumps(dict(success=False, error="Open and deliver the confidential card first"))
    target = request["target"]
    if target["kind"] not in ("vault", "browser-code"):
        return json.dumps(dict(success=False, error="This reference is not a browser destination"))
    expected = normalize_origin(target["origin"])

    def fill():
        _focus_bound_origin(task_id, expected, "login" if target["kind"] == "vault" else "otp")
        if _current_page_origin(task_id) != expected:
            return json.dumps(dict(success=False, error="Browser origin differs from the approved card"))
        if target["kind"] == "vault":
            meta = get_vault_store().get_meta(request["vaultId"])
            if meta is None:
                return json.dumps(dict(success=False, error="Profile vault item is unavailable; deliver again"))
            register_vault_redaction_value(meta.identifier)
            result = json.loads(browser_vault_fill(meta.id, task_id=task_id))
            if not result.get("success"):
                return json.dumps(result)
            selector = 'input[autocomplete="username"],input[type="email"],input[name="username"],input[name="identifier"],input[name="email"]'
            value = meta.identifier
        else:
            selector = 'input[autocomplete="one-time-code"],input[name="otp"],input[name="code"]'
            value = _call("browser-code", requestId=reference)["code"]
            register_vault_redaction_value(value)
        # Native supervisor transport and lease checks; credential bytes never enter argv/tool args.
        expression = "(() => { if (location.origin !== " + json.dumps(expected) + ") return {filled:false}; const e=document.querySelector(" + json.dumps(selector) + "); if(!e) return {filled:false}; Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'value').set.call(e," + json.dumps(value) + "); e.dispatchEvent(new Event('input',{bubbles:true})); e.dispatchEvent(new Event('change',{bubbles:true})); return {filled:true}; })()"
        written = _eval_js_secret(task_id, expression)
        payload = _parse_json_result(written.get("result"))
        return json.dumps(dict(success=written.get("success") is True and isinstance(payload, dict) and payload.get("filled") is True,
            origin=expected, next="Submit the existing form. Never read back input values."))
    return _fenced_page_op(task_id, fill)


def register(ctx):
    from agent.secret_sources.base import SecretSource, FetchResult, ErrorKind

    class NekodotSource(SecretSource):
        name = "nekodot"
        label = "This Bot's approved nekodot credentials"
        shape = "bulk"

        def fetch(self, cfg, home_path):
            try:
                return FetchResult(secrets=_call("source"))
            except Exception:
                return FetchResult().fail("nekodot Node is unavailable", ErrorKind.NETWORK)

    ctx.register_cli_command("secret", "Request confidential delivery or apply an approved reference", _setup, _command)
    ctx.register_secret_source(NekodotSource())
    ctx.register_hook("transform_tool_result", _scrub)
    from tools.browser_vault_tool import _check_vault_available
    ctx.register_tool(name="nekodot_secret_browser", toolset="nekodot-secrets", check_fn=_check_vault_available,
        handler=_browser, schema={"name":"nekodot_secret_browser",
        "description":"Fill an approved nekodot confidential reference in this profile browser using native vault/supervisor. No secret values in arguments. Open the approved site with browser_exec first.",
        "parameters":{"type":"object","properties":{"reference":{"type":"string"}},"required":["reference"]}})
`;

const skill = `---
name: nekodot-secrets
description: Request API keys, passwords or private keys through encrypted chat cards; configure services and browser logins without exposing values to the model.
---
# Confidential delivery
Never ask for secrets in normal chat, tool arguments or generated scripts. Never read back the approved destination or print secret-bearing environment variables.
Run \`hermes secret request --spec 'METADATA_JSON'\` from the active session. Fields: service, purpose, fields [{name,label,kind}], target. Kinds: text/password/private-key/otp. Keep the service, purpose and destination exact; the user is approving these together.
- API config: target {"kind":"file","path":"/absolute/config.env","format":"env"}; fields named after environment keys. JSON and YAML merge those keys. raw writes exactly one field, preserving all whitespace (use for a private key).
- Website: target {"kind":"vault","origin":"https://actual-site.example"}; fields identifier/password. Use the actual site. After delivery use nekodot_secret_browser with the reference; it delegates to native browser_vault and also fills the confidential identifier. Never read form values. Then submit with native browser tools.
- One-time codes: request a separate card with one field of kind otp and target {"kind":"browser-code","origin":"https://actual-site.example"}. Use nekodot_secret_browser with that reference. Codes cannot be saved. CAPTCHA and other human verification require screen takeover. Payments are not supported.
Example: \`hermes secret request --spec '{"service":"Test API","purpose":"Configure the monitoring client","fields":[{"name":"TEST_API_KEY","label":"API Key","kind":"password"}],"target":{"kind":"file","path":"/absolute/monitor.env","format":"env"}}'\`.
The command returns pending metadata/reference immediately. Tell the user to open the card, then finish this turn. nekodot queues ONE native continuation in the original session after submission; do not poll, wait in terminal, or rerun earlier tools.
If the same Bot already has a saved exact service/purpose/target match, the command applies it and returns applied metadata. Continue the remaining work in this turn. A changed purpose/destination requires another user confirmation.
Delivery applies only the displayed destination. \`hermes secret status REF\` and \`hermes secret apply REF\` return metadata and idempotent results, never values. Do not substitute another destination. For scripts, load the approved target config or use native secrets.nekodot (only saved env credentials, profile-scoped); never embed values in script source.
Not saving means no extra reusable copy: approved config files and browser sessions can still persist. Temporary vault items are withdrawn at task completion. Saved entries can be replaced or disabled in Bot details.
`;

export async function installSecretsPlugin(home: string) {
  const directory = join(home, 'plugins', 'nekodot-secrets');
  await mkdir(directory, { recursive: true, mode: 0o700 });
  const token = join(directory, 'bridge.token');
  if (
    !(await access(token).then(
      () => true,
      () => false,
    ))
  )
    await writeFile(token, randomBytes(32).toString('hex'), { mode: 0o600, flag: 'wx' });
  await writeFile(
    join(directory, 'plugin.yaml'),
    'name: nekodot-secrets\nversion: 0.1.0\ndescription: Encrypted, Bot-scoped confidential delivery\n',
  );
  await writeFile(join(directory, '__init__.py'), plugin);
  const skills = join(home, 'skills', 'nekodot-secrets');
  await mkdir(skills, { recursive: true });
  await writeFile(join(skills, 'SKILL.md'), skill);
}
