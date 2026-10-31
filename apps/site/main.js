// nekodot site: avatars, language and theme switching, the feature stage and the live chat replay.
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

/* ---------- avatars: the same 40-unit geometry as the client's painter ---------- */
const shapes = ['dot', 'bear', 'bunny', 'puppy', 'mochi', 'flower', 'ghost', 'antenna'];
const colors = [
  '#E8603C',
  '#FF3B47',
  '#FF4FA3',
  '#B05FD0',
  '#8B75AF',
  '#5B7CE6',
  '#2E8BFF',
  '#19B5C9',
  '#2F9E8F',
  '#22C55E',
  '#77A979',
  '#F2C230',
  '#D9932B',
  '#A9683A',
  '#8C8376',
  '#5A5A60',
];

function luminance(hex) {
  const channel = (start) => {
    const value = parseInt(hex.slice(start, start + 2), 16) / 255;
    return value <= 0.03928 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4;
  };
  return 0.2126 * channel(1) + 0.7152 * channel(3) + 0.0722 * channel(5);
}

function avatarBody(shape, c) {
  const ears = (x, y, inner) =>
    `<g class="ear" style="--px:${x}px;--py:${y}px">${inner}</g>` +
    `<g transform="matrix(-1 0 0 1 40 0)"><g class="ear" style="--px:${x}px;--py:${y}px">${inner}</g></g>`;
  const soft = (points, round) =>
    `<polygon points="${points}" fill="${c}" stroke="${c}" stroke-width="${round}" stroke-linejoin="round"/>`;
  const circle = (x, y, r) => `<circle cx="${x}" cy="${y}" r="${r}" fill="${c}"/>`;
  const tilted = (x, y, rx, ry, angle) =>
    `<ellipse cx="${x}" cy="${y}" rx="${rx}" ry="${ry}" transform="rotate(${angle} ${x} ${y})" fill="${c}"/>`;
  switch (shape) {
    case 'bear':
      return {
        body: ears(13, 15, circle(9.5, 11.5, 5.8)) + circle(20, 23, 15),
        y: 23.5,
        gap: 5.5,
      };
    case 'bunny':
      return {
        body: ears(14.5, 17, tilted(13, 9, 3.8, 8.5, -8)) + circle(20, 25.5, 13.5),
        y: 26,
        gap: 5,
      };
    case 'puppy':
      return {
        body: ears(9, 13, tilted(6.6, 22, 4.2, 9, 10)) + circle(20, 21.5, 14.5),
        y: 22,
        gap: 5.2,
      };
    case 'mochi':
      return {
        body:
          ears(14, 13, soft('8.5,13 10,7 15.5,11', 2.6)) +
          `<rect x="3" y="11" width="34" height="27" rx="13.5" fill="${c}"/>`,
        y: 24,
        gap: 7,
      };
    case 'flower': {
      const petals = [0, 60, 120, 180, 240, 300]
        .map((a) =>
          circle(
            (20 + 10.2 * Math.cos((a * Math.PI) / 180)).toFixed(2),
            (20 + 10.2 * Math.sin((a * Math.PI) / 180)).toFixed(2),
            7.2,
          ),
        )
        .join('');
      return { body: `<g class="petals">${petals}</g>` + circle(20, 20, 11), y: 20, gap: 4.4 };
    }
    case 'ghost': {
      let path = 'M6 20A14 14 0 0 1 34 20L34 35';
      for (let hop = 0; hop < 6; hop++) {
        const from = 34 - (hop * 28) / 6;
        path += `Q${(from - 28 / 12).toFixed(2)} ${hop % 2 ? 31 : 39} ${(from - 28 / 6).toFixed(2)} 35`;
      }
      return { body: `<path class="ghost" d="${path}Z" fill="${c}"/>`, y: 19.5, gap: 5 };
    }
    case 'antenna':
      return {
        body:
          ears(
            15,
            12,
            `<line x1="15" y1="11" x2="11.5" y2="4.5" stroke="${c}" stroke-width="2.6" stroke-linecap="round"/>` +
              circle(11, 3.8, 2.8),
          ) + `<rect x="5.5" y="9.5" width="29" height="28" rx="11" fill="${c}"/>`,
        y: 23.5,
        gap: 5.6,
      };
    default:
      return {
        body: ears(15, 16, soft('7.6,16 9.6,6.4 15.4,11', 3)) + circle(20, 23, 15),
        y: 23.5,
        gap: 5.5,
      };
  }
}

/** Without a color the avatar is the brand mark: ink body, eyes in the page color. */
function avatar(shape, color, working = false) {
  const { body, y, gap } = avatarBody(shape, color ?? 'currentColor');
  const eyes = color ? (luminance(color) > 0.45 ? '#141414' : '#ffffff') : 'var(--bg)';
  return (
    `<svg class="avatar${working ? ' working' : ''}" viewBox="0 0 40 40" aria-hidden="true">${body}` +
    `<g class="track"><g class="lid" style="--ey:${y}px" fill="${eyes}">` +
    `<circle cx="${20 - gap}" cy="${y}" r="2.2"/><circle cx="${20 + gap}" cy="${y}" r="2.2"/>` +
    `</g></g></svg>`
  );
}

document.querySelectorAll('[data-avatar]').forEach((node) => {
  node.innerHTML = avatar(node.dataset.avatar, node.dataset.color);
});
document.querySelectorAll('.crew > span').forEach((node, index) => {
  node.style.setProperty('--i', index);
});

// Each feature step shows its own picture on narrow screens: a copy of the sticky stage's.
const stageItems = [...document.querySelectorAll('.stage-item')];
document.querySelectorAll('.step').forEach((step, index) => {
  step.querySelector('.step-media').appendChild(stageItems[index].cloneNode(true));
});

/* ---------- language ---------- */
const en = {
  navDemo: 'Demo',
  navFeatures: 'Features',
  navHow: 'How it works',
  navStart: 'Get started',
  themeToggle: 'Toggle theme',
  heroTitle: 'Your AI team,<br />on your own computer.',
  heroLead:
    'One bot, one specialty. Chat one-on-one, or bring them into a group and let them hand work to each other. They run on your own machine, so your data and keys stay with you.',
  downloadWindows: 'Download for Windows',
  downloadAndroid: 'Download for Android',
  altHero: 'nekodot on Windows: two bots relaying a weekly report in a group',
  demoTitle: 'Not just answers,<br />but what it is doing.',
  demoTabs: 'Demo scenes',
  botYan: 'Scout',
  botPao: 'Errand',
  groupName: 'Weekly report',
  sceneDm: 'Tools and approval',
  sceneGroup: 'Bot relay',
  sceneAsk: 'Stops to ask you',
  replay: 'Replay',
  composer: 'Message',
  duoWindows: 'Pure black and white. Only your bots have color.',
  duoAndroid: 'Frosted glass and a floating dock, for one hand.',
  altDm: 'nekodot on Windows: tool steps and an approval card',
  altPhone: 'nekodot on Android: bots and groups',
  teamTitle: '8 faces,<br />16 colors.',
  teamBody:
    'Give it a name and one line about what it does. Every bot is its own Hermes profile, and it says hello once created.',
  makerFace: 'Toggle the working animation',
  makerShapes: 'Faces',
  makerColors: 'Colors',
  f1Title: 'Every bot, its own model',
  f1Body:
    'Sign in with an authorized account, or add a custom API. Sources sit side by side, and each bot picks its own source and model.',
  altSources: 'Model sources: authorized services and custom APIs',
  f2Title: 'What it remembers, you can edit',
  f2Body:
    'Who it is, what it has learned and what it knows about you are native Hermes memory, edited in place. What it knows about you is shared across your account’s computers.',
  altMemory: 'Editing a bot’s native memory',
  f3Title: 'One catalog, for any bot',
  f3Body:
    'Browse Hermes skills and plugins and read the docs before installing. Toggle and configure per bot, or import from Git, a folder or a ZIP.',
  altSkills: 'The Skills and plugins catalog',
  f4Title: 'Open its screen and take over',
  f4Body:
    'On Linux servers each bot has its own browser and desktop. Watch by default; for captchas or sign-ins, take control, then hand it back.',
  smTitle: 'Errand · Screen',
  smControl: 'You are in control',
  smReturn: 'Hand back',
  smLogin: 'Sign in',
  smCaptcha: 'captcha',
  smCaption: 'Illustration · install the node with --with-computer',
  moreTitle: 'And also.',
  m1Title: 'Add as you go',
  m1Body: 'Messages sent mid-run join the current turn, so finished work is kept.',
  m2Title: 'Stop anytime',
  m2Body: 'One button stops the run; in a group it clears the relay too.',
  m3Title: 'Group relay',
  m3Body: '2–6 bots. @ someone to hand off, at most 6 turns per message.',
  m4Title: 'Pick up where you left',
  m4Body: 'Lose the network or switch devices; history and progress sync back.',
  m5Title: 'Library',
  m5Body: 'Delivered files are kept as copies: preview, download, jump back to the chat.',
  m6Title: 'Many computers',
  m6Body: 'One account, several computers, switch anytime.',
  m7Title: 'Node self-update',
  m7Body: 'Verifies the signature, switches when idle, rolls back if startup fails.',
  m8Title: '中文 / English',
  m8Body: 'Light and dark follow your system, and so does reduced motion.',
  howTitle: 'Your computer only connects out.<br />Not a single port to open.',
  n1Body: 'Keeps only sign-in and preferences',
  n2Body: 'Accounts, pairing and routing; no chat stored',
  n3Body: 'Your machine: chats, bot settings, delivered files',
  n4Body: 'One profile per bot: sessions, memory, skills',
  fact1: 'Full keys live only on your node; the app shows the last four characters.',
  fact2: 'Hermes stays unmodified, integrated only through its official CLI and API.',
  fact3:
    'Model requests go to the provider you choose. nekodot is not offline and not end-to-end encrypted.',
  startTitle: 'Three steps<br />to your first chat.',
  downloadNote:
    '0.2.0 developer preview. Windows 10 / 11 x64; the installer is not publisher-signed. Android 10+ arm64; the APK is signed. Physical Android devices and background notifications still need full acceptance.',
  s1Title: 'Install the app, sign up by email',
  s1Body: 'The app includes its interface and connects over HTTPS.',
  s2Title: 'Pair your server',
  s2Body:
    'Run the one-line command from the app on a Linux x64 server or WSL2. Signing up grants no access to anyone else’s node.',
  s3Title: 'Add a model, create a bot',
  s3Body: 'Sign in or add a custom API, then give it a name and one line about what it does.',
  footDeploy: 'Self-hosting',
  footDev: 'Development guide',
  footFine:
    'MIT License. Interface fonts Nunito and JetBrains Mono use the SIL Open Font License 1.1. Screenshots use demo data.',
};

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
    const next = `assets/shots/${image.dataset.shot}-${theme}.webp?v=0.2.0`;
    if (!image.src.endsWith(next)) image.src = next;
  });
  document.querySelector('meta[name="theme-color"]').content =
    theme === 'dark' ? '#000000' : '#ffffff';
}
document.getElementById('theme-toggle').addEventListener('click', () => {
  root.dataset.theme = currentTheme() === 'dark' ? 'light' : 'dark';
  savePreference('nekodot-site-theme', root.dataset.theme);
  applyTheme();
});
systemDark.addEventListener('change', applyTheme);

/* ---------- download: the visitor's own platform comes first ---------- */
if (/Android/i.test(navigator.userAgent)) {
  document.querySelectorAll('[data-downloads]').forEach((group) => {
    group.dataset.primary = 'android';
    const [windows, android] = [
      group.querySelector('[data-platform="windows"]'),
      group.querySelector('[data-platform="android"]'),
    ];
    const primary = windows.className;
    windows.className = android.className;
    android.className = primary;
  });
}

/* ---------- nav and sections ---------- */
const nav = document.querySelector('.nav');
function onScroll() {
  nav.classList.toggle('is-scrolled', window.scrollY > 8);
}
window.addEventListener('scroll', onScroll, { passive: true });

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
  sectionObserver.observe(document.querySelector(link.hash));
});

/* ---------- the team watches the pointer ---------- */
if (!reduceMotion && window.matchMedia('(pointer: fine)').matches) {
  let frame = 0;
  window.addEventListener(
    'pointermove',
    (event) => {
      if (frame) return;
      frame = requestAnimationFrame(() => {
        frame = 0;
        document.querySelectorAll('.crew .track, .maker-face .track').forEach((track) => {
          const box = track.ownerSVGElement.getBoundingClientRect();
          if (box.bottom < 0 || box.top > window.innerHeight) return;
          const dx = event.clientX - (box.left + box.width / 2);
          const dy = event.clientY - (box.top + box.height / 2);
          const distance = Math.hypot(dx, dy) || 1;
          const reach = Math.min(1.6, distance / 60);
          track.setAttribute(
            'transform',
            `translate(${((dx / distance) * reach).toFixed(2)} ${((dy / distance) * reach).toFixed(2)})`,
          );
        });
      });
    },
    { passive: true },
  );
}

/* ---------- avatar maker ---------- */
(() => {
  const face = document.getElementById('maker-face');
  const shapeRow = document.getElementById('maker-shapes');
  const colorRow = document.getElementById('maker-colors');
  let shape = 'dot';
  let color = '#E8603C';
  let working = false;

  function render() {
    face.innerHTML = avatar(shape, color, working);
    face.setAttribute('aria-pressed', String(working));
    shapeRow.querySelectorAll('button').forEach((button) => {
      button.innerHTML = avatar(button.dataset.value, color);
      button.setAttribute('aria-pressed', String(button.dataset.value === shape));
    });
    colorRow.querySelectorAll('button').forEach((button) => {
      button.setAttribute('aria-pressed', String(button.dataset.value === color));
    });
  }
  for (const value of shapes) {
    const button = document.createElement('button');
    button.type = 'button';
    button.dataset.value = value;
    button.setAttribute('aria-label', value);
    button.addEventListener('click', () => {
      shape = value;
      render();
    });
    shapeRow.appendChild(button);
  }
  for (const value of colors) {
    const button = document.createElement('button');
    button.type = 'button';
    button.dataset.value = value;
    button.style.setProperty('--c', value);
    button.setAttribute('aria-label', value);
    button.addEventListener('click', () => {
      color = value;
      render();
    });
    colorRow.appendChild(button);
  }
  face.addEventListener('click', () => {
    working = !working;
    render();
  });
  render();
})();

/* ---------- feature stage: the step in the middle of the screen owns the window ---------- */
(() => {
  const steps = [...document.querySelectorAll('.step')];
  const items = [...document.querySelectorAll('#stage .stage-item')];
  const activate = (index) => {
    steps.forEach((step, i) => step.classList.toggle('is-active', i === index));
    items.forEach((item, i) => item.classList.toggle('is-active', i === index));
  };
  const observer = new IntersectionObserver(
    (entries) => {
      for (const entry of entries)
        if (entry.isIntersecting) activate(Number(entry.target.dataset.step));
    },
    { rootMargin: '-48% 0px -48% 0px' },
  );
  steps.forEach((step) => observer.observe(step));
  activate(0);
})();

/* ---------- live chat replay ---------- */
const bots = {
  yan: {
    shape: 'bunny',
    color: '#2E8BFF',
    zh: '小研',
    en: 'Scout',
    handles: { zh: 'xiaoyan', en: 'scout' },
  },
  bi: {
    shape: 'dot',
    color: '#E8603C',
    zh: '笔笔',
    en: 'Quill',
    handles: { zh: 'bibi', en: 'quill' },
  },
  pao: {
    shape: 'puppy',
    color: '#2F9E8F',
    zh: '跑腿',
    en: 'Errand',
    handles: { zh: 'paotui', en: 'errand' },
  },
};
const face = (bot, working = false) => avatar(bot.shape, bot.color, working);

const copy = {
  zh: {
    dmAsk: '帮我找 3 篇今年关于 agent 记忆的综述，各用一句话总结。',
    dmNote: '先搜一下最近的综述，再挑引用最多的三篇。',
    dmPrompt: (name) => `${name}想在你的电脑上运行这条命令：`,
    choices: ['允许一次', '本会话允许', '总是允许', '拒绝'],
    allowed: '已允许一次',
    dmAnswer:
      '整理好了，三篇方向各不相同：\n1. 记忆机制：把 agent 记忆分成工作、情节和语义三层。\n2. 长期记忆评测：比较多种检索策略在长对话里的表现。\n3. 记忆与规划：记忆如何影响多步任务的成功率。',
    groupName: '周报小组',
    groupAsk: '这周的周报，@bibi 先起个草稿',
    groupDraft: '草稿好了：本周新版注册流程上线，活跃用户增长 12%，下周重点是支付页改版。\n\n',
    groupMention: '@xiaoyan 帮我核对一下第二句里的数据来源。',
    groupTool: '打开运营看板',
    groupCheck:
      '核对完了：12% 来自运营看板，口径是周活，不是日活。建议改成「周活跃用户增长 12%」。',
    askAsk: '帮我把下个月去成都的机票比个价。',
    askTool: '打开航班搜索',
    askQuestion: '你想哪天出发？',
    askOptions: ['第一个周五', '第二个周五', '都可以'],
    askAnswered: '第二个周五',
    askAnswer: '第二个周五最便宜的是早上 7:40 的直飞，比同日其他航班便宜不少。要我继续看返程吗？',
    thinking: '回复中',
    tool: '运行工具',
    waiting: '等你确认',
    waitingAnswer: '等你回答',
    seconds: (value) => `${value}s`,
  },
  en: {
    dmAsk: 'Find 3 survey papers on agent memory from this year and sum each up in one line.',
    dmNote: 'I’ll search recent surveys first, then pick the three most cited.',
    dmPrompt: (name) => `${name} wants to run this command on your computer:`,
    choices: ['Allow once', 'This session', 'Always', 'Deny'],
    allowed: 'Allowed once',
    dmAnswer:
      'Done. Three different angles:\n1. Mechanisms: splits agent memory into working, episodic and semantic layers.\n2. Long-term benchmarks: compares retrieval strategies across long conversations.\n3. Memory and planning: how memory affects success on multi-step tasks.',
    groupName: 'Weekly report',
    groupAsk: 'For this week’s report, @quill please start a draft',
    groupDraft:
      'Draft ready: the new sign-up flow shipped, active users grew 12%, and next week we focus on checkout.\n\n',
    groupMention: '@scout could you check the source of the number in the second sentence?',
    groupTool: 'Opening the ops dashboard',
    groupCheck:
      'Checked: the 12% comes from the dashboard and counts weekly, not daily, actives. Suggest “weekly active users grew 12%”.',
    askAsk: 'Compare flights to Chengdu for next month.',
    askTool: 'Opening flight search',
    askQuestion: 'Which day do you want to leave?',
    askOptions: ['First Friday', 'Second Friday', 'Either'],
    askAnswered: 'Second Friday',
    askAnswer:
      'The cheapest second-Friday option is the 7:40 direct flight, well below the rest of that day. Shall I look at returns?',
    thinking: 'Replying',
    tool: 'Running a tool',
    waiting: 'Needs your OK',
    waitingAnswer: 'Needs your answer',
    seconds: (value) => `${value}s`,
  },
};

const demo = (() => {
  const body = document.getElementById('dw-body');
  const avatarSlot = document.getElementById('dw-avatar');
  const name = document.getElementById('dw-name');
  const status = document.getElementById('dw-status');
  const send = document.getElementById('dw-send');
  const tabs = [...document.querySelectorAll('.app-side [data-scene]')];
  const order = ['dm', 'group', 'ask'];
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
  const escape = (value) =>
    value.replace(/[&<>]/g, (ch) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' })[ch]);

  function header(html, title, line = '') {
    avatarSlot.innerHTML = html;
    name.textContent = title;
    status.innerHTML = line;
  }
  const running = (value) => send.classList.toggle('running', value);
  function user(text) {
    lastBlock = null;
    body.appendChild(el(`<div class="m m-user">${escape(text)}</div>`));
  }
  /** A speaker's stack in a group; a private chat has no avatar column. */
  function stackFor(key, group) {
    if (!group) return body;
    if (lastBlock?.dataset.bot === key) return lastBlock.querySelector('.m-stack');
    lastBlock = body.appendChild(
      el(
        `<div class="m m-block" data-bot="${key}"><span class="m-face">${face(bots[key])}</span><div class="m-stack"><span class="m-author">${bots[key][lang]}</span></div></div>`,
      ),
    );
    return lastBlock.querySelector('.m-stack');
  }
  function tool(stack, label, preview) {
    return stack.appendChild(
      el(
        `<div class="m m-tool running"><b>${label}</b><span>${escape(preview)}</span><em></em></div>`,
      ),
    );
  }
  function toolDone(node, seconds) {
    node.classList.remove('running');
    node.querySelector('em').textContent = copy[lang].seconds(seconds);
  }
  async function stream(stack, text, id, mentions = []) {
    const node = stack.appendChild(el('<div class="m m-bubble"></div>'));
    const caret = '<span class="caret"></span>';
    const render = (value) => {
      let html = escape(value);
      for (const handle of mentions)
        html = html.replaceAll('@' + handle, `<span class="at">@${handle}</span>`);
      return html;
    };
    const step = reduceMotion ? text.length : 3;
    for (let index = 0; index <= text.length; index += step) {
      node.innerHTML = render(text.slice(0, index)) + caret;
      await wait(32, id);
    }
    node.innerHTML = render(text);
  }
  const thinkingDots = (stack) =>
    stack.appendChild(el('<span class="m thinking"><i></i><i></i><i></i></span>'));

  async function playDm(id) {
    const c = copy[lang];
    const bot = bots.yan;
    const title = bot[lang];
    header(face(bot), title);
    await wait(700, id);
    user(c.dmAsk);
    running(true);
    await wait(500, id);
    header(face(bot, true), title, c.thinking);
    const thinking = thinkingDots(body);
    await wait(1000, id);
    thinking.remove();
    body.appendChild(el(`<div class="m m-bubble">${c.dmNote}</div>`));
    await wait(500, id);
    header(face(bot, true), title, c.tool);
    const search = tool(body, 'web_search', '"agent memory survey 2026"');
    await wait(1200, id);
    toolDone(search, '0.9');
    const read = tool(body, 'read_url', 'arxiv.org/abs/2604.01234');
    await wait(1400, id);
    toolDone(read, '1.8');
    const run = tool(body, 'terminal', 'pip install arxiv');
    await wait(300, id);
    header(face(bot), title, c.waiting);
    const card = body.appendChild(
      el(
        `<div class="m m-card"><span>${c.dmPrompt(title)}</span><code>pip install arxiv</code><div class="m-actions"><span class="ink">${c.choices[0]}</span><span>${c.choices[1]}</span><span>${c.choices[2]}</span><span>${c.choices[3]}</span></div></div>`,
      ),
    );
    await wait(2300, id);
    card.querySelector('.ink').classList.add('pressed');
    await wait(220, id);
    card.querySelector('.m-actions').outerHTML = `<span class="m-result">${c.allowed}</span>`;
    header(face(bot, true), title, c.tool);
    await wait(1200, id);
    toolDone(run, '3.2');
    header(face(bot, true), title, c.thinking);
    await stream(body, c.dmAnswer, id);
    header(face(bot), title);
    running(false);
  }

  async function playGroup(id) {
    const c = copy[lang];
    const { yan, bi } = bots;
    const pair = `<span class="app-faces" style="display:block;width:100%;height:100%"><span>${face(yan)}</span><span>${face(bi)}</span></span>`;
    const chain = (count) =>
      `<span class="chain">${Array.from({ length: 6 }, (_, i) => `<i class="${i < count ? 'on' : ''}"></i>`).join('')}</span>`;
    const busy = (count, state) => header(pair, c.groupName, `${chain(count)}${state}`);
    header(pair, c.groupName);
    await wait(700, id);
    user(c.groupAsk);
    running(true);
    await wait(600, id);
    busy(1, c.thinking);
    let stack = stackFor('bi', true);
    await stream(stack, c.groupDraft + c.groupMention, id, [yan.handles[lang]]);
    await wait(900, id);
    busy(2, c.tool);
    stack = stackFor('yan', true);
    const look = tool(stack, 'browser', c.groupTool);
    await wait(1600, id);
    toolDone(look, '2.4');
    busy(2, c.thinking);
    await stream(stack, c.groupCheck, id);
    await wait(300, id);
    header(pair, c.groupName);
    running(false);
  }

  async function playAsk(id) {
    const c = copy[lang];
    const bot = bots.pao;
    const title = bot[lang];
    header(face(bot), title);
    await wait(700, id);
    user(c.askAsk);
    running(true);
    await wait(500, id);
    header(face(bot, true), title, c.tool);
    const look = tool(body, 'browser', c.askTool);
    await wait(1500, id);
    toolDone(look, '2.1');
    header(face(bot), title, c.waitingAnswer);
    const card = body.appendChild(
      el(
        `<div class="m m-card"><span>${c.askQuestion}</span><div class="m-actions">${c.askOptions.map((o, i) => `<span class="${i === 1 ? 'choice' : ''}">${o}</span>`).join('')}</div></div>`,
      ),
    );
    await wait(2200, id);
    const choice = card.querySelector('.choice');
    choice.classList.add('ink', 'pressed');
    await wait(260, id);
    card.querySelector('.m-actions').outerHTML = `<span class="m-result">${c.askAnswered}</span>`;
    header(face(bot, true), title, c.thinking);
    const thinking = thinkingDots(body);
    await wait(900, id);
    thinking.remove();
    await stream(body, c.askAnswer, id);
    header(face(bot), title);
    running(false);
  }

  const players = { dm: playDm, group: playGroup, ask: playAsk };
  async function play() {
    const id = ++token;
    body.innerHTML = '';
    lastBlock = null;
    running(false);
    tabs.forEach((tab) => tab.setAttribute('aria-selected', String(tab.dataset.scene === scene)));
    try {
      await players[scene](id);
      await wait(3600, id);
      scene = order[(order.indexOf(scene) + 1) % order.length];
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
  ).observe(document.querySelector('.app'));

  return {
    restart() {
      if (visible) void play();
    },
  };
})();

applyLanguage();
applyTheme();
onScroll();
