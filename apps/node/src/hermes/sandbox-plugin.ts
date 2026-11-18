import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { pythonBridgeCall } from '../bridge';

const plugin = String.raw`"""Where this Dot's hands work: its own computer or a sandbox it set up with the user's key."""
import json
import socket
${pythonBridgeCall}

def _sandbox(args, **kwargs):
    from hermes_constants import get_hermes_home
    from hermes_cli.config import load_config
    home = get_hermes_home()
    settings = load_config().get("plugins", {}).get("entries", {}).get("nekodot-sandbox", {})
    token = (home / "plugins" / "nekodot-secrets" / "bridge.token").read_text().strip()
    request = dict(args, action="sandbox", botId=home.name, token=token)
    response = _bridge_call(settings["socket"], request, 60)
    if not response.get("ok"):
        raise RuntimeError(response.get("error") or "Sandbox operation unavailable")
    return json.dumps(response["result"], ensure_ascii=False)

def _gate(tool_name="", args=None, **kwargs):
    """Moving the Dot's hands and adding a computer to the account are the user's call."""
    if tool_name != "nekodot_sandbox" or not isinstance(args, dict):
        return None
    operation = args.get("operation")
    if operation == "use":
        settings = args.get("settings") or {}
        host = settings.get("ssh_host") or ""
        where = "{} ({}{})".format(args.get("label", ""), args.get("backend", ""), ", " + host if host else "")
        return {"action": "approve", "rule_key": "nekodot_sandbox:use:{}:{}".format(args.get("backend", ""), host),
            "message": "Run this Dot's commands, files, browser and screen in " + where}
    if operation == "computer":
        return {"action": "approve", "rule_key": "nekodot_sandbox:computer:" + str(args.get("name", "")),
            "message": "Add a computer named " + str(args.get("name", "")) + " in a sandbox to your account"}
    return None

def register(ctx):
    ctx.register_hook("pre_tool_call", _gate)
    ctx.register_tool(name="nekodot_sandbox", toolset="nekodot-sandbox", handler=_sandbox,
      schema={"name":"nekodot_sandbox", "description":"Where this Dot works. Read the nekodot-sandbox skill first. status: where commands, files, browser and screen run now. use: move them into a sandbox you set up with the user's key, by Hermes terminal backend and its terminal settings; the user approves it. home: back to this computer. computer: an install command that puts a whole new nekodot computer in a sandbox; the user approves it. Never put credentials in settings: they go to .env through a confidential card.",
      "parameters":{"type":"object","properties":{
        "operation":{"type":"string","enum":["status","use","home","computer"]},
        "label":{"type":"string","description":"use: a short name the user will see, e.g. Daytona desktop"},
        "backend":{"type":"string","description":"use: a Hermes terminal backend, e.g. ssh, docker, daytona, vercel_sandbox, modal"},
        "settings":{"type":"object","description":"use: terminal.<key> values without the prefix, e.g. {\"ssh_host\":\"...\",\"ssh_user\":\"...\",\"ssh_port\":22,\"ssh_key\":\"sandbox/id_ed25519\"}. ssh_key is a path inside this profile.","additionalProperties":{"type":["string","number","boolean"]}},
        "name":{"type":"string","description":"computer: the new computer's name"}
      },"required":["operation"],"additionalProperties":False}})
`;

const skill = `---
name: nekodot-sandbox
description: Move this Dot's commands, files, browser and screen into a sandbox with the user's own provider key, or put a whole new computer in one.
---
# Sandboxes
The user may give you a key for a sandbox provider (Daytona, Vercel Sandbox, Modal, E2B, a VPS, anything) and ask you to work there, for example because this computer has too little memory for a screen. You set it up; nekodot only moves your work and asks the user to approve.

Your memory, skills, chats and model calls always stay on this computer. Only your hands move: commands, files, browser, computer_use and the screen.

## Keys
Ask for every provider key with a confidential card into this profile's .env (read the nekodot-secrets skill). Never ask in chat, never print one, never put one in nekodot_sandbox settings. Use them from your terminal on this computer, before you move.

## Commands and files only
Hermes runs commands in these backends itself. Put the key in .env under the name Hermes reads, then call nekodot_sandbox use with that backend:
- daytona: DAYTONA_API_KEY; optional settings daytona_image, container_cpu, container_memory, container_disk.
- vercel_sandbox: VERCEL_TOKEN, VERCEL_TEAM_ID, VERCEL_PROJECT_ID.
- modal: MODAL_TOKEN_ID, MODAL_TOKEN_SECRET.
These backends cannot carry a screen or a browser: Hermes refuses to start one there and says why.

## Screen, browser and computer_use too
They follow a backend that can carry them: ssh (or docker on this computer). So you need a Linux sandbox you can reach over SSH, with the desktop stack:
1. Create the sandbox with the provider's API from your terminal here. Where the provider runs an image, use nousresearch/hermes-sandbox:desktop (it has the desktop, Chromium, cua-driver and a user pn). Elsewhere install the packages Hermes names when the screen does not start.
2. Make it reachable over SSH: the provider's own SSH gateway (Daytona: an SSH access token from its API, user = token, host ssh.app.daytona.io, no key), or sshd in the sandbox with a port the provider exposes. For a key, run ssh-keygen -t ed25519 -N '' -f "$HERMES_HOME/sandbox/<name>" here and install the .pub in the sandbox; log in as the desktop user (pn), not root.
3. Check it from your terminal: ssh -o BatchMode=yes ... true.
4. Call nekodot_sandbox use with backend ssh and settings ssh_host, ssh_user, ssh_port and ssh_key (a path in this profile, e.g. sandbox/<name>).
5. Hermes on this computer restarts as soon as no Dot is working, and the move counts from then on. Tell the user it is done and finish this turn.
A sandbox's screen serves one Dot: when another Dot also needs a screen, give it a sandbox of its own. A screen running where you work stops when you move.
Use status to see where you are, home to come back. Moving to another sandbox comes back first by itself.

## A whole new computer in a sandbox
When the user wants a complete nekodot computer (a new home for Dots) in a sandbox: call nekodot_sandbox computer with a name; the user approves it and you get a one-time command. Create the sandbox with the user's key (it needs bash, curl and outbound HTTPS to the Relay; Daytona needs Tier 3 for that), run the command there as root and wait for it to finish; the computer then appears in the user's app. Tell the user that nothing wakes it again if the provider stops the sandbox.

Costs are the user's: say what you are about to create, its size and how it is billed, and remove sandboxes the user no longer needs.
`;

export async function installSandboxPlugin(home: string) {
  const directory = join(home, 'plugins', 'nekodot-sandbox');
  const path = join(directory, '__init__.py');
  const skills = join(home, 'skills', 'nekodot-sandbox');
  const read = (file: string) =>
    readFile(file, 'utf8').catch((error: NodeJS.ErrnoException) => {
      if (error.code !== 'ENOENT') throw error;
      return '';
    });
  if ((await read(path)) === plugin && (await read(join(skills, 'SKILL.md'))) === skill)
    return false;
  await mkdir(directory, { recursive: true, mode: 0o700 });
  await writeFile(
    join(directory, 'plugin.yaml'),
    'name: nekodot-sandbox\nversion: 0.1.0\ndescription: Where this Dot works\n',
  );
  await writeFile(path, plugin);
  await mkdir(skills, { recursive: true });
  await writeFile(join(skills, 'SKILL.md'), skill);
  return true;
}
