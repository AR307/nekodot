import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { join } from 'node:path';

/** Selects Hermes' own Gemini client for a named custom source, including proxies. */
export async function installGeminiProvider(
  home: string,
  provider: string,
  key: string,
  baseUrl: string,
) {
  const directory = join(home, 'plugins', 'model-providers', provider);
  const source = [
    'from providers import register_provider',
    'from providers.base import ProviderProfile',
    'from agent.transports import register_transport',
    'class GeminiTransport:',
    '    def __new__(cls):',
    '        from agent.transports.chat_completions import ChatCompletionsTransport',
    '        return ChatCompletionsTransport()',
    'register_transport("gemini_generate_content", GeminiTransport)',
    '',
    'class CustomGemini(ProviderProfile):',
    '    def seed_pool_credentials(self, *, suppressed_sources, explicitly_configured):',
    '        from hermes_cli.env_loader import get_secret_str',
    '        source = "env:" + self.env_vars[0]',
    '        key = get_secret_str(self.env_vars[0], "")',
    '        if source in suppressed_sources or not key:',
    '            return []',
    '        return [{"source": source, "access_token": key, "base_url": self.runtime_base_url(api_key=key, default="", env_url="")}]',
    '',
    '    def api_mode_for_model(self, model, *, api_key=None):',
    '        from hermes_cli.config import load_config',
    '        return load_config()["providers"][self.name]["api_mode"]',
    '',
    '    def runtime_base_url(self, *, api_key, default, env_url):',
    '        from hermes_cli.config import load_config',
    '        return load_config()["providers"][self.name]["base_url"]',
    '',
    '    def _native(self):',
    '        from hermes_cli.config import load_config',
    '        return load_config()["providers"][self.name]["api_mode"] == "gemini_generate_content"',
    '',
    '    def create_client(self, **kwargs):',
    '        if not self._native():',
    '            return None',
    '        from agent.gemini_native_adapter import GeminiNativeClient',
    '        from hermes_cli.config import load_config',
    '        kwargs["base_url"] = load_config()["providers"][self.name]["base_url"]',
    '        return GeminiNativeClient(**kwargs)',
    '',
    '    def build_extra_body(self, *, session_id=None, **context):',
    '        if not self._native():',
    '            return super().build_extra_body(session_id=session_id, **context)',
    '        from agent.transports.chat_completions import _build_gemini_thinking_config',
    '        thinking = _build_gemini_thinking_config(context.get("model", ""), context.get("reasoning_config"))',
    '        return {"thinking_config": thinking} if thinking else {}',
    '',
    'register_provider(CustomGemini(name=' +
      JSON.stringify(provider) +
      ', base_url=' +
      JSON.stringify(baseUrl) +
      ', env_vars=(' +
      JSON.stringify(key) +
      ',),',
    '    api_mode="gemini_generate_content", hidden=True, supports_model_listing=False))',
    '',
  ].join('\n');
  await mkdir(directory, { recursive: true });
  const path = join(directory, '__init__.py');
  const previous = await readFile(path, 'utf8').catch((error: NodeJS.ErrnoException) => {
    if (error.code !== 'ENOENT') throw error;
    return undefined;
  });
  if (source !== previous) await writeFile(path, source);
  await writeFile(
    join(directory, 'plugin.yaml'),
    'name: ' + provider + '\nkind: model-provider\nversion: 1.0.0\n',
  );
}
