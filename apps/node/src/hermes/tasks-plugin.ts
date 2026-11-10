import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { pythonBridgeCall } from '../bridge';

export const taskPlugin = String.raw`"""Native coordination tools. The caller's profile and session are supplied by Hermes."""
import json
import socket
${pythonBridgeCall}

def _task(args, session_id="", **kwargs):
    from hermes_constants import get_hermes_home
    from hermes_cli.config import load_config
    from tools.approval_context import _approval_tool_call_id
    from gateway.session_display import _submission_turn
    home = get_hermes_home()
    settings = load_config().get("plugins", {}).get("entries", {}).get("nekodot-tasks", {})
    token = (home / "plugins" / "nekodot-secrets" / "bridge.token").read_text().strip()
    request = dict(args, action="task", botId=home.name, sessionId=session_id,
        callId=_approval_tool_call_id.get(), admissionId=_submission_turn.get()[0], token=token)
    response = _bridge_call(settings["socket"], request, 120)
    if not response.get("ok"):
        raise RuntimeError(response.get("error") or "Task operation unavailable")
    return json.dumps(response["result"], ensure_ascii=False)

def register(ctx):
    ctx.register_tool(name="nekodot_task", toolset="nekodot-tasks", handler=_task,
        schema={"name":"nekodot_task", "description":"Manage independent requirements for this chat. This is private implementation machinery: never announce task creation, dispatch, IDs or worker returns to the user. Start returns immediately; results arrive automatically. Use list/get for relevant existing work, steer for a running task, continue for a finished task, and stop for an explicitly requested task. Do not poll. Only coordinating sessions may use this tool.",
        "parameters":{"type":"object", "properties":{
            "operation":{"type":"string","enum":["start","list","get","continue","steer","stop"]},
            "taskId":{"type":"string"}, "title":{"type":"string","maxLength":7,"description":"A complete, concise task label in the user's language, at most 7 characters including spaces. Name the work, not internal agents; omit paths, IDs and step lists."},
            "input":{"type":"string","description":"The complete requirement or correction, including relevant constraints, evidence and attachment paths. Never include credential values."},
            "refreshCapabilities":{"type":"boolean","description":"Continue the same finished requirement in a fresh native session after reloading newly configured MCP/Skills."}
        },"required":["operation"],"additionalProperties":False}})
`;

export async function installTaskPlugin(home: string) {
  const directory = join(home, 'plugins', 'nekodot-tasks');
  const previous = await readFile(join(directory, '__init__.py'), 'utf8').catch(
    (error: NodeJS.ErrnoException) => {
      if (error.code !== 'ENOENT') throw error;
      return '';
    },
  );
  if (previous === taskPlugin) return false;
  await mkdir(directory, { recursive: true, mode: 0o700 });
  await writeFile(
    join(directory, 'plugin.yaml'),
    'name: nekodot-tasks\nversion: 0.1.0\ndescription: Native requirement coordination\n',
  );
  await writeFile(join(directory, '__init__.py'), taskPlugin);
  return true;
}
