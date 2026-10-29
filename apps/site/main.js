// nekodot site: language and theme switching, scroll effects and the live chat replay.
const root = document.documentElement;
const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

// Blocked storage (cookies disabled) must not stop the page; preferences then last one visit.
function readPreference(key) {
  try {
    return localStorage.getItem(key);
  } catch {
    return null;
  }
}
function savePreference(key, value) {
  try {
    localStorage.setItem(key, value);
  } catch {
    // storage blocked
  }
}

const en = {
  navWhy: 'Why',
  navDemo: 'Demo',
  navFeatures: 'Features',
  navHow: 'How it works',
  navStart: 'Get started',
  themeToggle: 'Toggle theme',
  heroBadge: 'Developer preview · Powered by Hermes Agent',
  heroTitle: 'Your AI team,<br />on your own computer.',
  heroLead:
    'Build a team of bots with their own specialties. Chat one-on-one, or bring them into a group and let them hand work to each other. They run on your own computer or server, so your data and keys stay with you.',
  ctaGithub: 'View on GitHub',
  ctaStart: 'Start in 3 steps',
  metaModels: 'Any model',
  metaPorts: 'No open ports',
  metaSync: 'Synced everywhere',
  metaLang: '中文 / English',
  altHero: 'nekodot on desktop: two bots relaying a weekly report in a group',
  miniApprovalTitle: 'Needs your OK',
  allowOnce: 'Allow once',
  deny: 'Deny',
  handoff: 'Hand to',
  stripLabel: 'Works with your models and machines',
  stripCompat: 'OpenAI-compatible APIs',
  soon: 'soon',
  whyEyebrow: 'Why nekodot',
  whyTitle: 'As easy as an app,<br />yet entirely yours.',
  p1Title: 'Your model, your call',
  p1Body:
    'Use OpenRouter or any OpenAI-compatible endpoint, including models on your own platform. Every bot can run a different model.',
  p2Title: 'Data stays on your machine',
  p2Body:
    'Chats, bot settings and full API keys live on your own computer or server. It only connects out, so there are no ports to open.',
  p3Title: 'No config files',
  p3Body:
    'Paste one command to connect a computer. Models, bots, skills and plugins are all set up in the app, and every device sees the same progress.',
  p4Title: 'Standing on Hermes',
  p4Body:
    'Every bot is a native Hermes profile, so memory, skills and the tool loop come from Hermes. nekodot focuses on a friendly app and multi-bot teamwork.',
  demoEyebrow: 'Live demo',
  demoTitle: 'Watch them<br />get to work.',
  demoLead:
    'A replay recreated from the real interface: streaming replies, tool steps, pausing for your approval, then bots relaying work in a group.',
  demoTabs: 'Demo scenes',
  sceneDm: 'Private chat: tools & approval',
  sceneDmSub: 'See every step; it stops when it needs you',
  sceneGroup: 'Group chat: bot relay',
  sceneGroupSub: '@ someone to hand off, up to 6 turns',
  replay: 'Replay',
  stop: 'Stop',
  composer: 'Message…',
  featEyebrow: 'Features',
  featTitle: 'See every step,<br />stay in control.',
  f1Tag: 'Run visibility',
  f1Title: 'Not just answers, but what it is doing',
  f1a: '<b>See the work</b>: live text, tool starts and finishes, and approvals in one place.',
  f1b: '<b>Add as you go</b>: messages sent mid-run join the current turn, so finished work is kept.',
  f1c: '<b>Your call</b>: sensitive actions pause for you, and you can draft while it waits.',
  f1d: '<b>Stop anytime</b>: one button stops the run; refresh or switch devices and it stays in sync.',
  altDm: 'Tool cards and an approval card in a private chat',
  f2Tag: 'Group relay',
  f2Title: 'Hand a task to a team',
  f2Body:
    'Put 2–6 bots in a group with a lead. Without an @, the lead answers; @ someone and it goes to them in order. When a bot @mentions a teammate, the work relays on its own.',
  f2a: 'At most 6 bot turns per message, then it pauses and tells you.',
  f2b: 'A bot shares context between private and group chats, so it remembers the group discussion.',
  f2c: 'Different groups can work at once, and “Stop all” clears the relay queue.',
  altGroup: 'Group relay on a phone: one bot hands the check to another',
  relayCard: 'Relay turns 2 / 6',
  f3Tag: 'Memory',
  f3Title: 'Every bot builds its own experience',
  f3Body:
    'Open a bot to read and edit its native memory: who it is, what it has learned, and what it knows about you. One tap on “Refine” turns experience into better habits.',
  f3a: '<code>SOUL.md</code> · <code>MEMORY.md</code> · <code>USER.md</code>, edited in place.',
  f3b: 'Tasks scheduled in chat show their plan and run history here.',
  f3c: 'Files it delivers land in a library: preview, download or jump back to the chat.',
  altMemory: 'Native memory editing in bot details',
  f4Tag: 'Screen takeover',
  f4Title: 'Open its screen and take over',
  f4Body:
    'On Linux servers each bot gets its own browser and desktop. Watch read-only by default; for captchas, sign-ins or payments, take over with your mouse and keyboard, then hand it back.',
  f4a: 'Handing back only releases control; it never reruns the task.',
  f4b: 'Closing the viewer is separate from stopping the chat, and browser profiles persist.',
  smTitle: 'Errand’s screen',
  live: 'Live',
  smControl: 'You have control · Errand paused',
  smHint: 'Click to interact',
  smLogin: 'Sign in',
  smCaptcha: 'captcha',
  smMessage:
    'Sign-in needs a captcha. I filled in the username. Please enter the code, then hand it back and I will continue.',
  smKeyboard: 'Keyboard',
  smWatch: 'Watch only',
  smReturn: 'Hand back to Errand',
  smCaption: 'Illustration · requires installing the Linux node with --with-computer',
  f5Tag: 'Skills & plugins',
  f5Title: 'One catalog, for any bot',
  f5Body:
    'Browse the Hermes skill and plugin catalog with descriptions, dependencies and platforms. Install, toggle and configure per bot, or import your own from Git, a folder or a ZIP.',
  altSkills: 'The Skills catalog',
  allEyebrow: 'Everything',
  allTitle: 'Everything a team needs.',
  t1Title: 'A team of bots',
  t1Body: 'Name, avatar, role and model, all adjustable anytime, with history and memory kept.',
  t2Title: 'Private chat',
  t2Body: 'Streaming replies, tool steps and approvals; add to or stop a run.',
  t3Title: 'Group relay',
  t3Body: '2–6 bots, pick who answers with @, and bots hand work to each other.',
  t4Title: 'Memory & self-improvement',
  t4Body: 'Edit native memory and let Hermes refine experience in one tap.',
  t5Title: 'Scheduled tasks',
  t5Body: 'Schedule them in chat, review plans and runs in details.',
  t6Title: 'Library',
  t6Body: 'Every delivered file in one place: preview, download, jump back.',
  t7Title: 'Skills & plugins',
  t7Body: 'Install, enable and configure per bot; import from Git, folder or ZIP.',
  t8Title: 'Live screen & takeover',
  t8Body: 'Watch a Linux bot’s browser and desktop, and step in anytime.',
  t9Title: 'Many computers, every device',
  t9Body:
    'One account, several computers; a command palette to jump anywhere; Chinese and English, light and dark, and it respects “reduce motion”.',
  howEyebrow: 'How it works',
  howTitle: 'Your computer only connects out.<br />Not a single port to open.',
  n1Title: 'Browser / App',
  n1Body: 'Keeps only sign-in and preferences',
  n2Body: 'Accounts, pairing and routing; no chat stored',
  outbound: 'node dials out',
  n3Title: 'Your computer (Node)',
  n3Body: 'Chats, bot settings, delivered files',
  n4Body: 'One profile per bot: sessions, memory, skills',
  fact1Title: 'Keys stay on your node',
  fact1Body:
    'Full model keys live only on the node; the app only ever shows the last four characters.',
  fact2Title: 'Hermes, unmodified',
  fact2Body:
    'Integrated only through the official CLI and API, so Hermes upgrades need no changes.',
  fact3Title: 'To be clear',
  fact3Body:
    'Model requests go to the provider you choose. nekodot is not offline and not end-to-end encrypted.',
  startEyebrow: 'Get started',
  startTitle: 'Three steps<br />to your first chat.',
  startLead:
    'Download nekodot 0.1.0 and connect straight from the app. Bots run on your paired server; no local development setup is needed.',
  downloadWindows: 'Download Windows x64',
  downloadAndroid: 'Download Android APK',
  downloadNote:
    'Windows 10 / 11 x64 · Android 10+ arm64. The Windows installer is not publisher-signed; the Android APK is signed. See release notes for tested scope and pending device checks.',
  s1Title: 'Install the app and sign up',
  s1Body:
    'The app includes its interface and connects over HTTPS. No local web server or SSH required.',
  s2Title: 'Pair your server',
  s2Body:
    'Run the one-line setup command from the app on your Linux server. Signing up does not grant access to anyone else’s node.',
  s3Title: 'Connect a model, create a bot',
  s3Body: 'Paste an OpenRouter or compatible API key, give your bot a name and say what it does.',
  copy: 'Copy',
  copied: 'Copied',
  tComment1: 'Get the code and install dependencies (Node 24 · pnpm 10)',
  tComment2: 'Reach your Relay over SSH and open the app',
  docDeploy: 'Deployment guide',
  docQuick: 'Full quick start',
  roadEyebrow: 'Roadmap',
  roadTitle: 'What works today,<br />and what comes next.',
  r1: 'Private chat: streaming, tool steps, approvals, mid-run additions, stop',
  r2: 'Group chat: @ members, bot-to-bot relay, relay limit',
  r3: 'One-command computer setup, multi-device sync and recovery',
  r4: 'Bot details: native memory, scheduled tasks, library',
  r5: 'Skills and plugin center',
  r6: 'Live screen and takeover (Linux VPS)',
  r7: 'Brand-new interface design',
  r8: 'Windows / Android 0.1.0 preview installers',
  r9: 'PWA: add to home screen',
  r10: 'macOS and ARM nodes',
  ctaTitle: 'Build your first AI team.',
  ctaBody: 'Follow along on GitHub, share ideas, or deploy your own today.',
  footTag: 'Your AI team, on your own computer.',
  footDev: 'Development guide',
  footFine:
    'nekodot is MIT licensed. Interface fonts Nunito and JetBrains Mono use the SIL Open Font License 1.1. Screenshots use demo data.',
};

/* ---------- language ---------- */
const zh = {};
const textNodes = document.querySelectorAll('[data-i18n]');
textNodes.forEach((node) => {
  zh[node.dataset.i18n] ??= node.innerHTML;
});
document.querySelectorAll('[data-i18n-alt]').forEach((node) => {
  zh[node.dataset.i18nAlt] = node.getAttribute('alt');
});
document.querySelectorAll('[data-i18n-aria]').forEach((node) => {
  zh[node.dataset.i18nAria] = node.getAttribute('aria-label');
});
zh.copied = '已复制';
const titles = {
  zh: document.title,
  en: 'nekodot · Your AI team, on your own computer',
};

let lang =
  readPreference('nekodot-site-lang') ??
  (navigator.language.toLowerCase().startsWith('zh') ? 'zh' : 'en');
const t = (key) => (lang === 'en' ? en : zh)[key] ?? zh[key] ?? key;

function applyLanguage() {
  root.lang = lang === 'zh' ? 'zh-CN' : 'en';
  document.title = titles[lang];
  textNodes.forEach((node) => {
    node.innerHTML = t(node.dataset.i18n);
  });
  document.querySelectorAll('[data-i18n-alt]').forEach((node) => {
    node.setAttribute('alt', t(node.dataset.i18nAlt));
  });
  document.querySelectorAll('[data-i18n-aria]').forEach((node) => {
    node.setAttribute('aria-label', t(node.dataset.i18nAria));
  });
  document.getElementById('lang-toggle').textContent = lang === 'zh' ? 'EN' : '中文';
}

document.getElementById('lang-toggle').addEventListener('click', () => {
  lang = lang === 'zh' ? 'en' : 'zh';
  savePreference('nekodot-site-lang', lang);
  applyLanguage();
  demo.restart();
});

/* ---------- theme ---------- */
const systemDark = window.matchMedia('(prefers-color-scheme: dark)');
const currentTheme = () => root.dataset.theme ?? (systemDark.matches ? 'dark' : 'light');

function applyTheme() {
  const theme = currentTheme();
  document.querySelectorAll('img[data-shot]').forEach((image) => {
    const next = `assets/shots/${image.dataset.shot}-${theme}.webp`;
    if (!image.src.endsWith(next)) image.src = next;
  });
  document.querySelector('meta[name="theme-color"]').content =
    theme === 'dark' ? '#16130f' : '#faf7f2';
}
document.getElementById('theme-toggle').addEventListener('click', () => {
  root.dataset.theme = currentTheme() === 'dark' ? 'light' : 'dark';
  savePreference('nekodot-site-theme', root.dataset.theme);
  applyTheme();
});
systemDark.addEventListener('change', applyTheme);

/* ---------- nav, reveal, hero tilt ---------- */
const nav = document.querySelector('.nav');
const stage = document.getElementById('hero-stage');
function onScroll() {
  nav.classList.toggle('is-scrolled', window.scrollY > 8);
  if (!reduceMotion && stage) {
    const progress = Math.min(1, Math.max(0, window.scrollY / 520));
    stage.style.setProperty('--tilt', `${14 * (1 - progress)}deg`);
    stage.style.setProperty('--scale', String(0.94 + 0.06 * progress));
  }
}
window.addEventListener('scroll', onScroll, { passive: true });

const revealObserver = new IntersectionObserver(
  (entries) => {
    for (const entry of entries)
      if (entry.isIntersecting) {
        entry.target.classList.add('is-visible');
        revealObserver.unobserve(entry.target);
      }
  },
  { rootMargin: '0px 0px -8% 0px' },
);
document.querySelectorAll('.reveal').forEach((node) => {
  const siblings = [...node.parentElement.children].filter((child) =>
    child.classList.contains('reveal'),
  );
  node.style.setProperty('--delay', `${Math.min(siblings.indexOf(node), 5) * 70}ms`);
  revealObserver.observe(node);
});

const sectionLinks = [...document.querySelectorAll('.nav-links a')];
const sectionObserver = new IntersectionObserver(
  (entries) => {
    for (const entry of entries)
      if (entry.isIntersecting)
        sectionLinks.forEach((link) =>
          link.classList.toggle('is-active', link.hash === '#' + entry.target.id),
        );
  },
  { rootMargin: '-45% 0px -50% 0px' },
);
sectionLinks.forEach((link) => {
  const section = document.querySelector(link.hash);
  if (section) sectionObserver.observe(section);
});

/* ---------- copy ---------- */
document.querySelectorAll('[data-copy]').forEach((button) => {
  button.addEventListener('click', () => {
    const text = document.getElementById(button.dataset.copy).innerText;
    void navigator.clipboard.writeText(text).then(() => {
      const label = button.querySelector('span');
      label.textContent = t('copied');
      window.setTimeout(() => {
        label.textContent = t('copy');
      }, 1600);
    });
  });
});

/* ---------- live chat replay ---------- */
const bots = {
  yan: { color: '#5b7ce6', zh: '小研', en: 'Scout', handles: { zh: 'xiaoyan', en: 'scout' } },
  bi: { color: '#e8603c', zh: '笔笔', en: 'Quill', handles: { zh: 'bibi', en: 'quill' } },
};
const handle = (bot) => bot.handles[lang];
const icons = {
  search: '<circle cx="11" cy="11" r="7"/><path d="m20 20-4-4"/>',
  globe:
    '<circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3a14 14 0 0 1 0 18M12 3a14 14 0 0 0 0 18"/>',
  terminal: '<path d="m5 7 5 5-5 5M12 17h7"/>',
  check: '<path d="M5 12.5l4.5 4.5L19 7.5"/>',
  arrow: '<path d="M5 12h14m-6-6 6 6-6 6"/>',
};
const svg = (name) => `<svg viewBox="0 0 24 24" aria-hidden="true">${icons[name]}</svg>`;
const cat = (color, working = false) =>
  `<svg viewBox="0 0 40 40" class="${working ? 'working' : ''}" style="color:${color}" aria-hidden="true">` +
  `<polygon class="ear-l" points="7,15 10,3 18,10" fill="currentColor"/>` +
  `<polygon class="ear-r" points="33,15 30,3 22,10" fill="currentColor"/>` +
  `<circle cx="20" cy="23" r="15" fill="currentColor"/>` +
  `<ellipse cx="15" cy="23" rx="2" ry="2.6" fill="var(--cat-eye)"/>` +
  `<ellipse cx="25" cy="23" rx="2" ry="2.6" fill="var(--cat-eye)"/></svg>`;

const copy = {
  zh: {
    dmAsk: '帮我找 3 篇今年关于 agent 记忆的综述，各用一句话总结。',
    dmNote: '先搜一下最近的综述，再挑引用最多的三篇。',
    dmSearch: '"agent memory survey 2026"',
    dmRead: 'arxiv.org/list/cs.AI',
    dmPrompt: '小研想在你的电脑上运行这条命令：',
    approval: '需要你确认',
    allow: '允许一次',
    deny: '拒绝',
    allowed: '已允许一次',
    dmAnswer:
      '整理好了，三篇方向各不相同：\n1. 记忆机制综述：把 agent 记忆分成工作、情节和语义三层。\n2. 长期记忆评测：比较多种检索策略在长对话里的表现。\n3. 记忆与规划：讨论记忆如何影响多步任务的成功率。',
    groupName: '周报小组',
    groupAsk: '这周的周报，<b>@bibi</b> 先起个草稿',
    groupDraft: '草稿好了：本周新版注册流程上线，活跃用户增长 12%，下周重点是支付页改版。\n\n',
    groupMention: '@xiaoyan 帮我核对一下第二句里的数据来源。',
    groupTool: '打开运营看板',
    groupCheck:
      '核对完了：12% 来自运营看板，口径是周活，不是日活。建议改成「周活跃用户增长 12%」。',
    handTo: '交给',
    lead: '主答',
    members: '2 个成员',
    thinking: '正在回复',
    tool: '正在运行工具',
    waiting: '等你确认',
    seconds: (value) => `${value} 秒`,
    line: (name, state) => `${name}${state}`,
    waitingLine: (name) => `${name}在等你确认`,
    chain: (count) => `接力已进行 ${count} / 6 轮`,
    placeholder: (name) => `发消息给${name}…`,
    groupPlaceholder: '发消息，用 @ 指定谁来回答',
  },
  en: {
    dmAsk: 'Find 3 survey papers on agent memory from this year and sum each up in one line.',
    dmNote: 'I’ll search recent surveys first, then pick the three most cited.',
    dmSearch: '"agent memory survey 2026"',
    dmRead: 'arxiv.org/list/cs.AI',
    dmPrompt: 'Scout wants to run this command on your computer:',
    approval: 'Needs your OK',
    allow: 'Allow once',
    deny: 'Deny',
    allowed: 'Allowed once',
    dmAnswer:
      'Done. Three different angles:\n1. Memory mechanisms: splits agent memory into working, episodic and semantic layers.\n2. Long-term memory benchmarks: compares retrieval strategies across long conversations.\n3. Memory and planning: how memory affects success on multi-step tasks.',
    groupName: 'Weekly report',
    groupAsk: 'For this week’s report, <b>@quill</b> please start a draft',
    groupDraft:
      'Draft ready: the new sign-up flow shipped, active users grew 12%, and next week we focus on the checkout page.\n\n',
    groupMention: '@scout could you check the source of the number in the second sentence?',
    groupTool: 'Opening the ops dashboard',
    groupCheck:
      'Checked: the 12% comes from the dashboard and counts weekly, not daily, actives. Suggest “weekly active users grew 12%”.',
    handTo: 'Hand to',
    lead: 'Lead',
    members: '2 members',
    thinking: 'Replying',
    tool: 'Running a tool',
    waiting: 'Waiting for you',
    seconds: (value) => `${value}s`,
    line: (name, state) => `${name} · ${state}`,
    waitingLine: (name) => `${name} is waiting for you`,
    chain: (count) => `Relay turns ${count} / 6`,
    placeholder: (name) => `Message ${name}…`,
    groupPlaceholder: 'Message the group — @ to pick who answers',
  },
};

const demo = (() => {
  const body = document.getElementById('dw-body');
  const avatar = document.getElementById('dw-avatar');
  const name = document.getElementById('dw-name');
  const status = document.getElementById('dw-status');
  const banner = document.getElementById('dw-banner');
  const bannerText = document.getElementById('dw-banner-text');
  const placeholder = document.getElementById('dw-placeholder');
  const tabs = [...document.querySelectorAll('.demo-tabs [data-scene]')];
  let token = 0;
  let scene = 'dm';
  let visible = false;
  let lastBlock = null;

  const speed = reduceMotion ? 0.15 : 1;
  const wait = (ms, id) =>
    new Promise((resolve, reject) =>
      window.setTimeout(
        () => (id === token ? resolve() : reject(new Error('cancelled'))),
        ms * speed,
      ),
    );
  const el = (html) => {
    const holder = document.createElement('div');
    holder.innerHTML = html.trim();
    return holder.firstElementChild;
  };
  const add = (node) => body.appendChild(node);

  function header(html, title, line = '', waiting = false) {
    avatar.innerHTML = html;
    name.textContent = title;
    status.innerHTML = line;
    status.classList.toggle('is-waiting', waiting);
  }
  function setBanner(text, waiting = false) {
    banner.hidden = !text;
    banner.classList.toggle('is-waiting', waiting);
    bannerText.textContent = text;
  }
  function block(bot, group) {
    if (lastBlock?.dataset.bot === bot) return lastBlock.querySelector('.m-stack');
    lastBlock = add(
      el(
        `<div class="m m-bot" data-bot="${bot}" style="--tool:${bots[bot].color}">${cat(bots[bot].color)}<div class="m-stack">${
          group
            ? `<span class="m-author"><b>${bots[bot][lang]}</b> @${handle(bots[bot])}</span>`
            : ''
        }</div></div>`,
      ),
    );
    return lastBlock.querySelector('.m-stack');
  }
  function user(html) {
    lastBlock = null;
    add(el(`<div class="m m-user">${html}</div>`));
  }
  function tool(stack, icon, label, preview) {
    return stack.appendChild(
      el(
        `<div class="m m-tool running"><span class="m-tool-icon">${svg(icon)}</span><span class="m-tool-copy"><span>${label}</span><small>${preview}</small></span><span class="m-tool-state"><span class="spinner"></span></span></div>`,
      ),
    );
  }
  function toolDone(node, seconds) {
    node.classList.remove('running');
    node.querySelector('.m-tool-state').innerHTML = `${copy[lang].seconds(seconds)}${svg('check')}`;
  }
  async function stream(stack, text, id, mentions = []) {
    const node = stack.appendChild(el('<div class="m m-text"></div>'));
    const caret = '<span class="caret">▍</span>';
    const escape = (value) =>
      value.replace(/[&<>]/g, (ch) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' })[ch]);
    const render = (value) => {
      let html = escape(value);
      for (const handle of mentions)
        html = html.replaceAll('@' + handle, `<span class="mention">@${handle}</span>`);
      return html;
    };
    const step = reduceMotion ? text.length : 3;
    for (let index = 0; index <= text.length; index += step) {
      node.innerHTML = render(text.slice(0, index)) + caret;
      await wait(32, id);
    }
    node.innerHTML = render(text) + caret;
    return node;
  }
  const endStream = (node) => node.querySelector('.caret')?.remove();
  function dots(stack) {
    return stack.appendChild(el('<span class="dots"><i></i><i></i><i></i></span>'));
  }
  function chainPill(count) {
    body.querySelector('.m-chain')?.remove();
    const steps = Array.from(
      { length: 6 },
      (_, i) => `<i class="${i < count ? 'on' : ''}"></i>`,
    ).join('');
    add(el(`<div class="m m-chain"><span>${steps}</span>${copy[lang].chain(count)}</div>`));
  }

  async function playDm(id) {
    const c = copy[lang];
    const bot = bots.yan;
    const live = () => cat(bot.color, true);
    header(cat(bot.color), bot[lang], '@' + handle(bot));
    placeholder.textContent = c.placeholder(bot[lang]);
    await wait(700, id);
    user(c.dmAsk);
    await wait(600, id);
    header(live(), bot[lang], `<span class="dots"><i></i><i></i><i></i></span>${c.thinking}`);
    setBanner(c.line(bot[lang], c.thinking));
    const stack = block('yan');
    const thinking = dots(stack);
    await wait(1100, id);
    thinking.remove();
    stack.appendChild(el(`<p class="m m-note">${c.dmNote}</p>`));
    await wait(500, id);
    header(live(), bot[lang], `<span class="dots"><i></i><i></i><i></i></span>${c.tool}`);
    setBanner(c.line(bot[lang], c.tool));
    const search = tool(stack, 'search', 'web_search', c.dmSearch);
    await wait(1300, id);
    toolDone(search, '0.9');
    const read = tool(stack, 'globe', 'read_url', c.dmRead);
    await wait(1500, id);
    toolDone(read, '1.8');
    await wait(300, id);
    header(cat(bot.color), bot[lang], c.waiting, true);
    setBanner(c.waitingLine(bot[lang]), true);
    const card = stack.appendChild(
      el(
        `<div class="m m-approval"><strong>${c.approval}</strong><span>${c.dmPrompt}</span><code>pip install arxiv</code><div class="m-approval-actions"><span class="ink">${c.allow}</span><span>${c.deny}</span></div></div>`,
      ),
    );
    await wait(2200, id);
    card.querySelector('.ink').classList.add('pressed');
    await wait(220, id);
    card.classList.add('done');
    card.querySelector('.m-approval-actions').outerHTML =
      `<span class="m-result">${svg('check')}${c.allowed}</span>`;
    header(live(), bot[lang], `<span class="dots"><i></i><i></i><i></i></span>${c.tool}`);
    setBanner(c.line(bot[lang], c.tool));
    const run = tool(stack, 'terminal', 'terminal', 'pip install arxiv');
    await wait(1400, id);
    toolDone(run, '3.2');
    header(live(), bot[lang], `<span class="dots"><i></i><i></i><i></i></span>${c.thinking}`);
    setBanner(c.line(bot[lang], c.thinking));
    const answer = await stream(stack, c.dmAnswer, id);
    endStream(answer);
    header(cat(bot.color), bot[lang], '@' + handle(bot));
    setBanner('');
  }

  async function playGroup(id) {
    const c = copy[lang];
    const { yan, bi } = bots;
    const dotsGroup = `<span style="display:inline-flex;gap:0"><svg viewBox="0 0 40 40" style="width:24px;height:24px;color:${yan.color}"><circle cx="20" cy="20" r="17" fill="currentColor"/></svg><svg viewBox="0 0 40 40" style="width:24px;height:24px;margin-left:-9px;color:${bi.color}"><circle cx="20" cy="20" r="17" fill="currentColor" stroke="var(--bg)" stroke-width="4"/></svg></span>`;
    const idle = `${c.lead}: ${bi[lang]} · ${c.members}`;
    header(dotsGroup, c.groupName, idle);
    placeholder.textContent = c.groupPlaceholder;
    await wait(700, id);
    user(c.groupAsk);
    await wait(600, id);
    const busy = (bot, state) =>
      header(
        dotsGroup,
        c.groupName,
        `${c.lead}: ${bi[lang]} · <span class="dots"><i></i><i></i><i></i></span>${c.line(bot[lang], state)}`,
      );
    busy(bi, c.thinking);
    setBanner(c.line(bi[lang], c.thinking));
    chainPill(1);
    let stack = block('bi', true);
    body.appendChild(body.querySelector('.m-chain'));
    const draft = await stream(stack, c.groupDraft + c.groupMention, id, [handle(yan)]);
    endStream(draft);
    await wait(300, id);
    stack.appendChild(
      el(
        `<span class="m-handoff">${svg('arrow')}${c.handTo} @${handle(yan)}${cat(yan.color)}</span>`,
      ),
    );
    await wait(900, id);
    chainPill(2);
    busy(yan, c.tool);
    setBanner(c.line(yan[lang], c.tool));
    stack = block('yan', true);
    body.appendChild(body.querySelector('.m-chain'));
    const look = tool(stack, 'globe', 'browser', c.groupTool);
    await wait(1600, id);
    toolDone(look, '2.4');
    busy(yan, c.thinking);
    setBanner(c.line(yan[lang], c.thinking));
    const check = await stream(stack, c.groupCheck, id);
    body.appendChild(body.querySelector('.m-chain'));
    endStream(check);
    await wait(400, id);
    header(dotsGroup, c.groupName, idle);
    setBanner('');
  }

  async function play() {
    const id = ++token;
    body.innerHTML = '';
    lastBlock = null;
    setBanner('');
    tabs.forEach((tab) => tab.setAttribute('aria-selected', String(tab.dataset.scene === scene)));
    try {
      await (scene === 'dm' ? playDm(id) : playGroup(id));
      await wait(4200, id);
      scene = scene === 'dm' ? 'group' : 'dm';
      if (visible) void play();
    } catch {
      // A newer replay or a scene switch cancelled this one.
    }
  }

  tabs.forEach((tab) =>
    tab.addEventListener('click', () => {
      scene = tab.dataset.scene;
      void play();
    }),
  );
  document.getElementById('demo-replay').addEventListener('click', () => void play());
  new IntersectionObserver(
    ([entry]) => {
      const was = visible;
      visible = entry.isIntersecting;
      if (visible && !was) void play();
      if (!visible) token++;
    },
    { threshold: 0.35 },
  ).observe(document.querySelector('.demo-window'));

  return {
    restart() {
      if (visible) void play();
    },
  };
})();

applyLanguage();
applyTheme();
onScroll();
