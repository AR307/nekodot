import { mkdir, writeFile } from 'node:fs/promises';
import { join } from 'node:path';

const plugin = String.raw`"""nekodot UI/transport adapter. All tasks execute in native Hermes."""
import base64
import json
import socket
import time
import uuid


def _home():
    from hermes_constants import get_hermes_home
    return get_hermes_home()


def _call(action, **params):
    from hermes_cli.config import load_config
    settings = load_config().get("plugins", {}).get("entries", {}).get("nekodot-routines", {})
    path = settings.get("socket")
    if not path:
        raise RuntimeError("nekodot routine bridge is not configured")
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
        client.settimeout(120)
        client.connect(path)
        client.sendall((json.dumps({"action": action, "botId": _home().name, **params}) + "\n").encode())
        data = b""
        while not data.endswith(b"\n"):
            chunk = client.recv(65536)
            if not chunk:
                raise RuntimeError("nekodot routine bridge disconnected")
            data += chunk
    result = json.loads(data)
    if not result.get("ok"):
        raise RuntimeError(result.get("error", "Routine operation failed"))
    return result["result"]


def _setup(parser):
    commands = parser.add_subparsers(dest="routine_action", required=True)
    for action in ("create", "update"):
        sub = commands.add_parser(action)
        if action == "update":
            sub.add_argument("routine_id")
        sub.add_argument("--name", required=True)
        sub.add_argument("--description", default="")
        sub.add_argument("--prompt", required=True)
        sub.add_argument("--events", default="")
        sub.add_argument("--skills", default="")
        sub.add_argument("--cron-job")
    commands.add_parser("list")
    for action in ("get", "send"):
        sub = commands.add_parser(action)
        sub.add_argument("routine_id")
        if action == "send":
            sub.add_argument("--payload", default="{}")
            sub.add_argument("--request-id", required=True)


def _command(args):
    action = args.routine_action
    params = {}
    if action in ("create", "update"):
        params = dict(name=args.name, description=args.description, prompt=args.prompt,
                      events=[s.strip() for s in args.events.split(",") if s.strip()],
                      skills=[s.strip() for s in args.skills.split(",") if s.strip()])
        if args.cron_job:
            params["cronJobId"] = args.cron_job
    if action in ("update", "get", "send"):
        params["routineId"] = args.routine_id
    if action == "send":
        params.update(payload=json.loads(args.payload), requestId=args.request_id)
    # No credential-read operation is exposed to the agent or its scripts.
    print(json.dumps(_call(action, **params), ensure_ascii=False))


def _event(phase, session_id=None, platform=None, assistant_response="", **kwargs):
    if not session_id:
        return
    from gateway.session_context import get_session_env
    chat = get_session_env("HERMES_SESSION_CHAT_ID") or ""
    route = None
    request_id = None
    job_id = None
    if chat.startswith("webhook:v2:"):
        token = chat[len("webhook:v2:"):]
        _, route, request_id = json.loads(base64.urlsafe_b64decode(token + "=" * (-len(token) % 4)))
    else:
        from hermes_state import SessionDB
        db = SessionDB()
        try:
            identity = db.cron_run_identity(session_id)
        finally:
            db.close()
        if identity:
            job_id = identity["cron_job_id"]
    if not route and not job_id:
        return
    event = dict(phase=phase, botId=_home().name, sessionId=session_id,
                 route=route, requestId=request_id, jobId=job_id,
                 text=assistant_response or "", time=time.time())
    if phase == "ended":
        event["interrupted"] = bool(kwargs.get("interrupted"))
        event["completed"] = bool(kwargs.get("completed"))
        event["failed"] = bool(kwargs.get("failed"))
        event["reason"] = str(kwargs.get("turn_exit_reason") or "")
    directory = _home() / "plugin-data" / "nekodot-routines" / "outbox"
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    path = directory / (str(time.time_ns()) + "-" + str(uuid.uuid4()) + ".pending")
    # Retained outbox lets Node collect a completion even across its own restart.
    with path.open("x", encoding="utf-8") as stream:
        json.dump(event, stream, ensure_ascii=False)
    path.chmod(0o600)
    path.rename(path.with_suffix(".json"))
    try:
        _call("drain")
    except (OSError, RuntimeError):
        pass  # The retained outbox is collected when the node is available again.


def register(ctx):
    ctx.register_cli_command("routine", "Manage nekodot routines and send approved webhook events", _setup, _command)
    ctx.register_hook("on_session_start", lambda **kw: _event("started", **kw))
    ctx.register_hook("post_llm_call", lambda **kw: _event("response", **kw))
    ctx.register_hook("on_session_end", lambda **kw: _event("ended", **kw))
`;

const skill = `---
name: nekodot-routines
description: Create webhook routines and attach webhook triggers to scheduled jobs in nekodot.
---
# nekodot routines
Use the native terminal tool to run \`hermes routine\` with your current profile.
- Create: \`hermes routine create --name "Title" --description "Purpose" --prompt "Fixed task. External event: {__raw__}"\`.
- To add a webhook to an existing native scheduled job, also pass \`--cron-job JOB_ID\`. Do not create a second scheduled job.
- List/get/update use \`hermes routine list\`, \`hermes routine get ID\`, and \`hermes routine update ID ...\`.
- After creation, ask the user to open the routine card/details in nekodot and approve secure credential delivery. Never ask them to paste a secret into chat or scripts. The entry remains disabled until approved.
- Once approved, scripts use \`hermes routine send ID --request-id STABLE_EVENT_ID --payload '{"message":"event"}'\`. This helper calls the actual public HTTPS URL without printing or embedding its secret. New events need new IDs; retries reuse the original ID.
- Each webhook runs as a separate native background task; it does not steer the private conversation. Native cron/webhook permissions still apply. Do not promise terminal access that native webhook mode does not grant.
- Never print credentials, read the credential store, enable a route without the user, or claim a 202 receipt means task completion. A test must check the resulting routine execution.
`;

/** Embedded so the single-file node distribution needs no checkout or Python package fork. */
export async function installRoutinePlugin(home: string) {
  const directory = join(home, 'plugins', 'nekodot-routines');
  await mkdir(directory, { recursive: true, mode: 0o700 });
  await writeFile(
    join(directory, 'plugin.yaml'),
    'name: nekodot-routines\nversion: 0.1.0\ndescription: nekodot native routine UI and transport bridge\nprovides_hooks:\n  - on_session_start\n  - post_llm_call\n  - on_session_end\n',
  );
  await writeFile(join(directory, '__init__.py'), plugin);
  const skills = join(home, 'skills', 'nekodot-routines');
  await mkdir(skills, { recursive: true });
  await writeFile(join(skills, 'SKILL.md'), skill);
}
