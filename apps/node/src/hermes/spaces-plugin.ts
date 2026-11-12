import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { pythonBridgeCall } from '../bridge';

const plugin = String.raw`"""Profile-bound private HTML spaces."""
import json
import socket
${pythonBridgeCall}

def _space(args, session_id="", **kwargs):
    from hermes_constants import get_hermes_home
    from hermes_cli.config import load_config
    from tools.approval_context import _approval_tool_call_id
    from gateway.session_display import _submission_turn
    home = get_hermes_home()
    settings = load_config().get("plugins", {}).get("entries", {}).get("nekodot-spaces", {})
    token = (home / "plugins" / "nekodot-secrets" / "bridge.token").read_text().strip()
    request = dict(args, action="space", botId=home.name, sessionId=session_id,
        callId=_approval_tool_call_id.get(), admissionId=_submission_turn.get()[0], token=token)
    response = _bridge_call(settings["socket"], request, 120)
    if not response.get("ok"):
        raise RuntimeError(response.get("error") or "Space operation unavailable")
    return json.dumps(response["result"], ensure_ascii=False)

def register(ctx):
    ctx.register_tool(name="nekodot_space", toolset="nekodot-spaces", handler=_space,
      schema={"name":"nekodot_space", "description":"Create and publish private interactive HTML spaces in Nekodot. Read the nekodot-spaces skill first. prepare returns a dedicated directory: write index.html and its assets there, then publish the same spaceId. Updates reuse that ID and preserve user records. list/get only access this Dot's spaces. Website origins are requested, not authorized by this tool. The app delivers a space card with your main-chat result; never give the user internal IDs or file paths.",
      "parameters":{"type":"object","properties":{
        "operation":{"type":"string","enum":["prepare","publish","list","get"]},
        "spaceId":{"type":"string"},"name":{"type":"string"},
        "origins":{"type":"array","items":{"type":"string"},"description":"Exact HTTPS origins needed by the page, e.g. https://example.com. The user must authorize them in the app. Bundle essential scripts and styles locally."}
      },"required":["operation"],"additionalProperties":False}})
`;

const skill = `---
name: nekodot-spaces
description: Create or update private interactive HTML spaces for games, study and reports.
---
# Private HTML spaces
The user need not name this feature or open New Space first. When a persistent interactive page is useful for their goal, the main Dot can propose it conversationally, ask for agreement, and then create it through the normal task flow. A direct request to create a Space already expresses agreement. Do not turn every ordinary question into a Space or create one before the user accepts your suggestion.
The main Dot delegates file creation and editing through its existing task tool, passing the user's requirements and space reference. The execution task uses this skill and the publication tool, then reports back for the main Dot to summarize. Do not ask the user to enable file tools in the coordinator session.
Use nekodot_space prepare with a short name. It returns spaceId and a dedicated directory. Put index.html and its HTML/CSS/JS/JSON/media assets there. Publish only that directory through nekodot_space publish. Do not start a web server, install a frontend framework or publish a public URL. Reuse the same spaceId to modify a space; get returns its current saved records. Existing records must survive code updates.
The SDK exists only inside the Nekodot app. Do not substitute a mock SDK or search for client debug ports/processes to claim native verification. After publication, report the actual deliverable; the user can open and test it in the app.

Use responsive semantic HTML, touch targets, keyboard controls, light/dark CSS and prefers-reduced-motion. Match the user's language. Keep core behavior bundled and usable offline. No external iframes, service workers, popups, remote logins or native privileges. Package paths must be relative; no hidden files or symlinks. Never include credentials. A native Space SDK is installed before your page scripts:

    await window.nekodotSpace.ready;
    const value = await window.nekodotSpace.get('settings');
    const records = await window.nekodotSpace.list(); // object keyed by record ID
    await window.nekodotSpace.set('settings', {sound: true});

Writes persist on the current client first, then synchronize with the owning Node. Store each attempt/game result under its own stable record ID, not one shared counter; settings are last-write-wins per key. Use null to clear a value. Do not use localStorage or IndexedDB for durable user records. SDK errors must be shown by the page without discarding inputs. Listen for the window event nekodotspacechange and re-read the SDK to update an already open page when another device synchronizes records; do not reload the page or discard in-progress form input.

Bundled data.json can be fetched with a relative URL. For outside requests, declare exact HTTPS origins in publish. They remain blocked until the user approves them in the native interface. HTTPS and the remote service's CORS still apply. Do not request host credentials or bypass CORS. API keys and private data acquisition belong to the Dot using existing authorized tools, followed by a package update, not to page scripts.

Updates are staged until the user refreshes/reopens the page. For recurring reports, use the existing routine tool and the same spaceId; do not create a new space each run. Publication returns a real reference and the main Dot's final reply carries the space card automatically. Explain the result naturally, not the private publication machinery.
`;

export async function installSpacesPlugin(home: string) {
  const directory = join(home, 'plugins', 'nekodot-spaces');
  const path = join(directory, '__init__.py');
  const skills = join(home, 'skills', 'nekodot-spaces');
  const previous = await readFile(path, 'utf8').catch((error: NodeJS.ErrnoException) => {
    if (error.code !== 'ENOENT') throw error;
    return '';
  });
  const previousSkill = await readFile(join(skills, 'SKILL.md'), 'utf8').catch(
    (error: NodeJS.ErrnoException) => {
      if (error.code !== 'ENOENT') throw error;
      return '';
    },
  );
  if (previous === plugin && previousSkill === skill) return false;
  await mkdir(directory, { recursive: true, mode: 0o700 });
  await writeFile(
    join(directory, 'plugin.yaml'),
    'name: nekodot-spaces\nversion: 0.1.0\ndescription: Private interactive HTML spaces\n',
  );
  await writeFile(path, plugin);
  await mkdir(skills, { recursive: true });
  await writeFile(join(skills, 'SKILL.md'), skill);
  return true;
}
