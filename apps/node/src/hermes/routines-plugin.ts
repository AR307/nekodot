import { mkdir, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { pythonBridgeCall } from '../bridge';

const plugin = String.raw`"""nekoDOT UI/transport adapter. All tasks execute in native Hermes."""
import base64
import json
import socket

${pythonBridgeCall}

def _home():
    from hermes_constants import get_hermes_home
    return get_hermes_home()


def _call(action, **params):
    from hermes_cli.config import load_config
    settings = load_config().get("plugins", {}).get("entries", {}).get("nekodot-routines", {})
    path = settings.get("socket")
    if not path:
        raise RuntimeError("nekoDOT routine bridge is not configured")
    result = _bridge_call(path, {"action": action, "botId": _home().name, **params}, 120)
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


def _status(raw_args):
    """Read native admission verdicts, including failures before an agent was constructed."""
    from hermes_state import SessionDB
    from hermes_state_runtime import list_session_admissions
    from gateway.session_results import admission_result
    from hermes_cli.profiles import get_profile_dir
    params = json.loads(raw_args) if raw_args.strip() else {}
    profile = params.get("profile") or _home().name
    known = set(params.get("settled", []))
    events = []
    # command.dispatch has no live session here: bind the native store explicitly.
    db = SessionDB(db_path=get_profile_dir(profile) / "state.db", read_only=True)
    try:
        offset = 0
        while True:
            rows = db.list_sessions_rich(sources=["webhook", "cron", "local"],
                limit=100, offset=offset, include_hidden=True, include_archived=True)
            for row in rows:
                sid = row["id"]
                if sid in known:
                    continue
                route = request_id = job_id = None
                chat = row.get("chat_id") or ""
                if chat.startswith("webhook:v2:"):
                    token = chat[len("webhook:v2:"):]
                    _, route, request_id = json.loads(base64.urlsafe_b64decode(token + "=" * (-len(token) % 4)))
                else:
                    identity = db.cron_run_identity(sid)
                    if identity:
                        job_id = identity["cron_job_id"]
                if not route and not job_id:
                    continue
                admissions = list_session_admissions(db, session_id=sid, pending_only=False)
                if not admissions:
                    continue
                admission = admissions[-1]
                terminal = admission["status"] == "terminal"
                outcome = admission["outcome"]
                text = ""
                reason = str(outcome or admission["status"])
                if terminal:
                    saved = admission_result(db, admission["admission_id"])
                    result = (saved or {}).get("result", {})
                    text = result.get("final_response") or ""
                    reason = str(result.get("error") or reason)
                events.append(dict(phase="ended" if terminal else "started", botId=profile,
                    sessionId=sid, route=route, jobId=job_id, requestId=request_id, text=text,
                    time=row.get("ended_at") or row.get("last_active") or row["started_at"],
                    completed=outcome == "completed", failed=outcome in ("failed", "rejected"),
                    interrupted=outcome in ("interrupted", "cancelled"),
                    reason=reason))
            if len(rows) < 100:
                break
            offset += len(rows)
    finally:
        db.close()
    return json.dumps(events, ensure_ascii=False)


def register(ctx):
    ctx.register_cli_command("routine", "Manage nekoDOT routines and send approved webhook events", _setup, _command)
    ctx.register_command("nekodot-routine-status", _status, "Read native routine execution records")
`;

const skill = `---
name: nekodot-routines
description: Create webhook routines and attach webhook triggers to scheduled jobs in nekoDOT.
---
# nekoDOT routines
Use the native terminal tool to run \`hermes routine\` with your current profile.
- Create: \`hermes routine create --name "Title" --description "Purpose" --prompt "Fixed task. External event: {__raw__}"\`.
- To add a webhook to an existing native scheduled job, also pass \`--cron-job JOB_ID\`. Do not create a second scheduled job.
- List/get/update use \`hermes routine list\`, \`hermes routine get ID\`, and \`hermes routine update ID ...\`.
- After creation, ask the user to open the routine card/details in nekoDOT and approve secure credential delivery. Never ask them to paste a secret into chat or scripts. The entry remains disabled until approved.
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
    'name: nekodot-routines\nversion: 0.1.0\ndescription: nekoDOT native routine UI and transport bridge\n',
  );
  await writeFile(join(directory, '__init__.py'), plugin);
  const skills = join(home, 'skills', 'nekodot-routines');
  await mkdir(skills, { recursive: true });
  await writeFile(join(skills, 'SKILL.md'), skill);
}
