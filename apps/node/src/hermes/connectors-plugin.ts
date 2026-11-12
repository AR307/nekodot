import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { pythonBridgeCall } from '../bridge';

export const connectorsPlugin = String.raw`"""Account connectors through the existing authenticated Node bridge."""
import json
import socket
${pythonBridgeCall}

def _connector(args, session_id="", **kwargs):
    from hermes_constants import get_hermes_home
    from hermes_cli.config import load_config
    from tools.approval_context import _approval_tool_call_id
    from gateway.session_display import _submission_turn
    home = get_hermes_home()
    settings = load_config().get("plugins", {}).get("entries", {}).get("nekodot-connectors", {})
    token = (home / "plugins" / "nekodot-secrets" / "bridge.token").read_text().strip()
    context = dict(action="connector", botId=home.name, sessionId=session_id,
        callId=_approval_tool_call_id.get(), admissionId=_submission_turn.get()[0], token=token)
    def call(request):
        response = _bridge_call(settings["socket"], dict(context, request=request), 120)
        if not response.get("ok"):
            raise RuntimeError(response.get("error") or "Connector unavailable")
        return response["result"]
    approval = None
    if args.get("operation") == "execute":
        tool = call(dict(operation="describe", toolId=args["toolId"], connectionId=args["connectionId"]))
        if tool["operation"] != "read":
            from tools.approval import request_tool_approval
            decision = request_tool_approval("nekodot_connector",
                json.dumps(dict(title=tool["name"], service=tool["service"],
                    account="  ".join(value for value in [tool["connection"]["label"], tool["connection"]["account"]] if value),
                    arguments=args.get("arguments", {})), ensure_ascii=False),
                rule_key="connector:" + tool["toolId"] + ":" + args["connectionId"])
            if not decision.get("approved"):
                return json.dumps(dict(status="blocked", error=decision.get("message")), ensure_ascii=False)
            approval = dict(approved=True)
    result = call(args)
    if approval is not None:
        result["nativeApproval"] = approval
    return json.dumps(result, ensure_ascii=False)

def register(ctx):
    ctx.register_tool(name="nekodot_connector", toolset="nekodot-connectors", handler=_connector,
      schema={"name":"nekodot_connector", "description":"Use the Nekodot account's connected services through native approvals. list returns explicit account references; catalog finds services; authorize places a browser authorization card in the original chat then you must end this turn. search discovers relevant tools on demand; describe returns actual metadata; execute calls ONE discovered tool with a specified connectionId. Never guess an account: if multiple are suitable and the user did not identify one, use native clarify so the main Dot asks naturally. Do not pick the most recently connected account. Tool metadata determines read/write approval, not your declaration. Do not repeat an uncertain write, switch to browser access on failure, or request platform keys. All Bots and Nodes share the account connections. Main Dot summarizes your results rather than forwarding this report.",
      "parameters":{"type":"object","properties":{
        "operation":{"type":"string","enum":["list","catalog","authorize","search","describe","execute"]},
        "serviceId":{"type":"string"}, "query":{"type":"string"}, "cursor":{"type":"string"},
        "toolId":{"type":"string"}, "connectionId":{"type":"string"},
        "arguments":{"type":"object","additionalProperties":True}
      },"required":["operation"],"additionalProperties":False}})
`;

export async function installConnectorsPlugin(home: string) {
  const directory = join(home, 'plugins', 'nekodot-connectors');
  const path = join(directory, '__init__.py');
  const previous = await readFile(path, 'utf8').catch((error: NodeJS.ErrnoException) => {
    if (error.code !== 'ENOENT') throw error;
    return '';
  });
  if (previous === connectorsPlugin) return false;
  await mkdir(directory, { recursive: true, mode: 0o700 });
  await writeFile(
    join(directory, 'plugin.yaml'),
    'name: nekodot-connectors\nversion: 0.1.0\ndescription: Account service connections\n',
  );
  await writeFile(path, connectorsPlugin);
  return true;
}
