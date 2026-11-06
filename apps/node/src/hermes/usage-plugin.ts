import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { join } from 'node:path';

/** Observer only: never retains the hook's messages, response, URL or credentials. */
export const usagePlugin = String.raw`import base64
import json
import sqlite3
from contextlib import closing


def _connect(home):
    db = sqlite3.connect(str(home / "nekodot-usage.sqlite"), timeout=5)
    db.execute("CREATE TABLE IF NOT EXISTS calls(seq INTEGER PRIMARY KEY AUTOINCREMENT, id TEXT UNIQUE, data TEXT NOT NULL)")
    db.execute("CREATE TABLE IF NOT EXISTS owners(session_id TEXT PRIMARY KEY, execution_id TEXT NOT NULL)")
    return db


def _execution():
    # v0.22.6 binds this native admission ContextVar before the turn and copies it to hook threads.
    from gateway.session_display import _submission_turn
    from tools.async_delegation_worker import worker_ledger
    submission = _submission_turn.get()
    if submission:
        return "admission:" + submission[0]
    ledger = worker_ledger()
    execution = ledger.store.scope.get("execution_id", "") if ledger is not None else ""
    return execution.replace("admission-worker:", "admission:", 1)


def _child(child_session_id=None, **_):
    from hermes_constants import get_hermes_home
    execution = _execution()
    if child_session_id and execution:
        with closing(_connect(get_hermes_home())) as db, db:
            db.execute("INSERT OR IGNORE INTO owners VALUES(?,?)", (child_session_id, execution))


def _record(kind, payload):
    from hermes_constants import get_hermes_home
    from tools.async_delegation_worker import worker_ledger
    home = get_hermes_home()
    request_id = payload.get("api_request_id")
    if not request_id:
        return
    # MoA's main response contains the aggregator; advisor calls are separate.
    if kind == "aux" and payload.get("aux_task") == "moa_aggregator" and not payload.get("error_type"):
        return
    ledger = worker_ledger()
    scope = ledger.store.scope if ledger is not None else {}
    usage = payload.get("usage")
    tokens = None if usage is None else dict(
        input=int(usage.get("input_tokens") or 0), output=int(usage.get("output_tokens") or 0),
        cacheRead=int(usage.get("cache_read_tokens") or 0), cacheWrite=int(usage.get("cache_write_tokens") or 0))
    # The native main retry loop reuses request_id AND started_at. Error attempts must
    # not occupy the successful response's identity (nor conceal unknown billed usage).
    identity = kind + ":" + request_id + ":" + str(payload["ended_at"] if kind == "error" else payload["started_at"])
    row = dict(id=identity, sessionId=payload.get("session_id") or scope.get("session_id", ""),
               executionId=_execution(), at=payload["ended_at"], tokens=tokens)
    with closing(_connect(home)) as db, db:
        db.execute("INSERT OR IGNORE INTO calls(id,data) VALUES(?,?)", (identity, json.dumps(row)))


def _main(**payload):
    _record("main", payload)


def _aux(**payload):
    _record("aux", payload)


def _error(**payload):
    _record("error", payload)


def _origin(db, sid):
    lineage = []
    result = dict(lineage=lineage)
    while sid and sid not in lineage:
        lineage.append(sid)
        row = db.get_session(sid)
        if not row:
            break
        chat = row.get("chat_id") or ""
        if chat.startswith("webhook:v2:"):
            encoded = chat[len("webhook:v2:"):]
            _, route, _ = json.loads(base64.urlsafe_b64decode(encoded + "=" * (-len(encoded) % 4)))
            result["route"] = route
        cron = db.cron_run_identity(sid)
        if cron:
            result["jobId"] = cron["cron_job_id"]
        sid = row.get("parent_session_id")
    return result


def _read(raw_args):
    from hermes_cli.profiles import get_profile_dir
    from hermes_state import SessionDB
    params = json.loads(raw_args)
    home = get_profile_dir(params["profile"])
    with closing(_connect(home)) as db:
        rows = db.execute("SELECT seq,data FROM calls WHERE seq>? ORDER BY seq LIMIT 500", (params["after"],)).fetchall()
        owners = dict(db.execute("SELECT session_id,execution_id FROM owners"))
    native = SessionDB(db_path=home / "state.db", read_only=True)
    try:
        origins = {}
        result = []
        for seq, data in rows:
            row = json.loads(data)
            sid = row["sessionId"]
            if sid not in origins:
                origins[sid] = _origin(native, sid)
            if not row["executionId"]:
                row["executionId"] = next((owners[s] for s in origins[sid]["lineage"] if s in owners), "")
            result.append(dict(row, seq=seq, **origins[sid]))
        return json.dumps(result)
    finally:
        native.close()


def register(ctx):
    ctx.register_hook("post_api_request", _main)
    ctx.register_hook("post_auxiliary_call", _aux)
    ctx.register_hook("api_request_error", _error)
    ctx.register_hook("subagent_start", _child)
    ctx.register_command("nekodot-usage-read", _read, "Read numeric usage records")
`;

export async function installUsagePlugin(home: string) {
  const directory = join(home, 'plugins', 'nekodot-usage');
  const previous = await readFile(join(directory, '__init__.py'), 'utf8').catch(
    (error: NodeJS.ErrnoException) => {
      if (error.code !== 'ENOENT') throw error;
      return '';
    },
  );
  if (previous === usagePlugin) return false;
  await mkdir(directory, { recursive: true, mode: 0o700 });
  await writeFile(
    join(directory, 'plugin.yaml'),
    'name: nekodot-usage\nversion: 0.1.0\ndescription: nekodot numeric usage observer\n',
  );
  await writeFile(join(directory, '__init__.py'), usagePlugin);
  return true;
}
