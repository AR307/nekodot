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

/* ---------- opening: Bots hop out from behind the window; the name card fills the screen ---------- */
const intro = document.getElementById('intro');
const introStage = intro.querySelector('.intro-stage');
const introWindow = intro.querySelector('.intro-window');
const introFace = intro.querySelector('.intro-card-face');
const introBots = [...intro.querySelectorAll('.intro-bots > span')];
introBots.forEach((node, index) => {
  node.innerHTML = `<span class="bot-y"><span class="bot-body">${node.innerHTML}</span></span>`;
  node.style.setProperty('--i', index);
});

// Landing spots are fractions of the window's size, on or just past its edge;
// each Bot starts hidden behind the window, a little further in. Once the card
// rises, each settles round the name. All stay inside the stage.
function placeBots() {
  const width = introWindow.offsetWidth;
  const height = introWindow.offsetHeight;
  const faceWidth = introFace.offsetWidth;
  const faceHeight = introFace.offsetHeight;
  intro.style.setProperty('--cw', `${faceWidth}px`);
  intro.style.setProperty('--ch', `${faceHeight}px`);
  const roomX = introStage.offsetWidth / 2;
  const roomY = introStage.offsetHeight / 2;
  const base = Math.min(112, Math.max(52, width * 0.075));
  const inside = (value, limit) => Math.max(-limit, Math.min(limit, value));
  for (const node of introBots) {
    const [fx, fy, turn, scale] = node.dataset.to.split(',').map(Number);
    const size = base * scale;
    const limitX = roomX - size / 2 - 8;
    const limitY = roomY - size / 2 - 8;
    const x = inside(fx * width, limitX);
    const y = inside(fy * height, limitY);
    // Behind the window: pulled in from the landing spot by more than its size.
    const reach = Math.hypot(x, y) || 1;
    const pull = Math.min(1, (size * 1.3) / reach);
    // Beside the name when there is room; on a narrow screen, a row above it.
    const roomy = faceWidth / 2 + size * 1.2 < limitX;
    const side = Math.abs(fy) < 0.3 && roomy;
    const above = Math.abs(fy) < 0.3 && !roomy;
    const cx = above
      ? Math.sign(fx) * faceWidth * 0.24
      : side
        ? Math.sign(fx) * (faceWidth / 2 + size * 0.7)
        : (fx / 0.5) * (faceWidth / 2 - size * 0.2);
    const cy = above
      ? -(faceHeight / 2 + size * 1.5)
      : side
        ? fy * faceHeight
        : Math.sign(fy) * (faceHeight / 2 + size * 0.35);
    const set = (name, value) => node.style.setProperty(name, `${value.toFixed(1)}px`);
    set('--size', size);
    set('--x', x);
    set('--y', y);
    set('--sx', x * (1 - pull));
    set('--sy', y * (1 - pull));
    set('--jump', size * 0.9);
    set('--cx', inside(cx, limitX));
    set('--cy', inside(cy, limitY));
    node.style.setProperty('--r', `${turn}deg`);
  }
}
placeBots();
window.addEventListener('resize', placeBots, { passive: true });
// The card's size waits on the web fonts.
document.fonts?.ready.then(placeBots);

// --p runs from 0 when the stage pins to 1 when it lets go.
let introFrame = 0;
function trackIntro() {
  introFrame = 0;
  const pinned = document.querySelector('.nav').offsetHeight;
  const box = intro.getBoundingClientRect();
  const travel = box.height - introStage.offsetHeight;
  const progress = travel > 0 ? Math.max(0, Math.min(1, (pinned - box.top) / travel)) : 0;
  intro.style.setProperty('--p', progress.toFixed(4));
}
if (!reduceMotion) {
  window.addEventListener(
    'scroll',
    () => {
      if (!introFrame) introFrame = requestAnimationFrame(trackIntro);
    },
    { passive: true },
  );
  trackIntro();
  window.addEventListener('load', trackIntro);
  window.addEventListener('resize', trackIntro, { passive: true });
  // Tabbing into the card brings it fully into view.
  intro.querySelector('.intro-card').addEventListener('focusin', () => {
    const travel = intro.offsetHeight - introStage.offsetHeight;
    const pinned = document.querySelector('.nav').offsetHeight;
    if (Number(intro.style.getPropertyValue('--p')) < 0.9)
      window.scrollTo({ top: intro.offsetTop - pinned + travel * 0.92 });
  });
}

/* ---------- language ---------- */
const en = {
  navTeam: 'Groups',
  navLocal: 'On your PC',
  navMore: 'More',
  navStart: 'Get started',
  themeToggle: 'Toggle theme',
  heroTitle: 'A crew of bots that do the work,<br />on your own computer.',
  heroLead:
    'Research, weekly reports, bookkeeping, web forms: give each job to its own bot. They work with the files and the browser on that computer, and you hand out work, follow along and sign off from your desktop or phone.',
  downloadWindows: 'Download for Windows',
  downloadAndroid: 'Download for Android',
  altHero: 'nekodot on Windows: two bots handing a weekly report to each other in a group',
  altPhone: 'nekodot on Android: bots and groups',
  composer: 'Message',
  teamTitle: 'A few bots in one group,<br />passing the job along',
  teamBody:
    'Put two to six bots in a group, each with its own job. Ask Quill for the weekly report; when the draft is done it mentions @scout to check the numbers, and you just read the result. Want something changed halfway? Say so in the group.',
  teamP1: 'Mention a bot to hand it the work; bots mention each other too',
  teamP2: 'Only one bot works in a group at a time, so they never collide',
  teamP3: 'At most 6 hand-offs in a row, then it stops and waits for you',
  localTitle: 'Installed on your own computer',
  localBody:
    'When you add a computer on Windows, choose “This computer” and the app sets up everything it needs. No server to rent. Bots read and write the files on that computer directly.',
  w1Title: 'Your computer',
  w1Body: 'Chats, bot settings, delivered files and API keys all live here',
  w2Title: 'nekodot service',
  w2Body: 'Handles accounts and passes messages along; chats are not stored',
  w3Title: 'The app',
  w3Body: 'Remembers only that you are signed in, and preferences like language',
  localFine:
    'Model requests go to the model provider you choose, so nekodot does not run offline and has no end-to-end encryption. To keep bots online around the clock, install them on a Linux server instead.',
  controlTitle: 'Before it acts,<br />it asks',
  controlBody:
    'Before it runs a command or changes a file, it stops and lets you choose: allow once, allow for this session, always allow, or deny. Every tool it used, and how long it took, is listed in the chat.',
  controlP1: 'Thought of something halfway? Send it, and it carries on with your note',
  controlP2: 'Going the wrong way? Press stop; in a group, stop them all at once',
  controlP3: 'When it is unsure, it stops to ask you',
  phoneTitle: 'Away from your desk,<br />keep an eye on it from your phone',
  phoneBody:
    'The Android app connects to the same computer, so chats and progress match on both. When a bot replies, has a question or needs your OK, your phone gets a notification; open it to approve or deny.',
  botYan: 'Scout',
  waiting: 'Needs your OK',
  noticeBody: 'wants to run pip install arxiv on your computer',
  moreTitle: 'It also does these',
  smControl: 'You are in control',
  smReturn: 'Hand back',
  smLogin: 'Sign in',
  c1Title: 'Open its screen and step in',
  c1Body:
    'When Errand hits a captcha on a website, it calls you. Open its screen, press “Take over”, fill it in and hand it back.',
  c1Fine:
    'Screens are for bots on a Linux server. On Windows you can let one bot control this computer instead; it is off by default.',
  docTitle: 'Quill · About you',
  doc1: 'Wants the conclusion first, details after',
  doc2: 'Weekly reports go to the ops group chat',
  doc3: 'Numbers to one decimal place',
  doc4: 'No meetings on Friday afternoons',
  c2Title: 'What it remembers, you can edit',
  c2Body:
    'What it knows about you and what it has learned on the job are plain text you can open and change. What it knows about you syncs to the bots on all your computers.',
  sk1: 'Search papers by keyword',
  sk2: 'Read and write sheets, docs and calendars',
  sk3: 'Split, merge and extract PDFs',
  skInstalled: 'Installed',
  skInstall: 'Install',
  skFor: 'Installed for Scout',
  c3Title: 'Add a skill, get a new ability',
  c3Body:
    'Pick from the Hermes catalog of skills and plugins, read what each does first, then install it. You decide which bot gets it.',
  secretWhy: 'Quill needs it to chart the weekly report',
  secretSave: 'Keep for Quill to reuse',
  secretSend: 'Deliver encrypted',
  secretDone: 'Delivered, for Quill only',
  c4Title: 'Passwords go in an encrypted box',
  c4Body:
    'When a bot needs an API key or a password, it shows an encrypted input in the chat. Only the bot that asked can use it, and the chat never shows the value.',
  also: 'Also: scheduled tasks, a library of delivered files, several computers on one account, self-updating nodes, Chinese and English, light and dark.',
  openTitle: 'Open source,<br />built on <span class="nowrap">Hermes Agent</span>',
  openBody:
    'nekodot is open source under the MIT license. Every bot is a native Hermes Agent: memory, skills and tool calls are all handled by Hermes. nekodot does not modify Hermes; it adds the app, the connection and the teamwork between bots.',
  openP1:
    'Bring your own model: sign in with an account or add a custom API, and give each bot a different one',
  openP2: 'Hermes’s own settings can all be changed in the app, no config files to edit',
  openP3: 'Want to run the whole service yourself? The steps are on GitHub',
  startTitle: 'Three steps to start',
  downloadNote:
    'Release 0.3.1. Windows 10 / 11 x64; the installer is not yet publisher-signed. Android 10 and later, arm64; the APK is signed. No macOS or Linux desktop installers yet.',
  s1Title: 'Download the app and sign up with email',
  s1Body: 'Enter the code we send you, and you are in.',
  s2Title: 'Pick a computer for your bots',
  s2Body:
    'On Windows, choose “This computer” and the app sets it up. To keep them online all day, run the one-line command the app gives you on a Linux server.',
  s3Title: 'Add a model and create your first bot',
  s3Body: 'Give it a name and one line about its job, and it says hello.',
  footDeploy: 'Self-hosting',
  footDev: 'Development',
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
  en: 'nekodot · A crew of bots that do the work, on your own computer',
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
  // Typed lines reveal one character per step.
  document.querySelectorAll('.type').forEach((node) => {
    node.style.setProperty('--n', [...node.textContent.trim()].length);
  });
}

document.getElementById('lang-toggle').addEventListener('click', () => {
  lang = lang === 'zh' ? 'en' : 'zh';
  savePreference('nekodot-site-lang', lang);
  applyLanguage();
  replays.forEach((chat) => chat.restart());
});

/* ---------- theme ---------- */
const systemDark = window.matchMedia('(prefers-color-scheme: dark)');
const currentTheme = () => root.dataset.theme ?? (systemDark.matches ? 'dark' : 'light');

function applyTheme() {
  const theme = currentTheme();
  document.querySelectorAll('img[data-shot]').forEach((image) => {
    const next = `assets/shots/${image.dataset.shot}-${theme}.webp?v=0.3.1-20261105`;
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
        document.querySelectorAll('.intro-bots .track').forEach((track) => {
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

/* ---------- live chat replays: small working copies of the client's chat ---------- */
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
  zhang: {
    shape: 'dot',
    color: '#D9932B',
    zh: '记账',
    en: 'Ledger',
    handles: { zh: 'jizhang', en: 'ledger' },
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
    localAsk: '把 D:\\报销\\10月 里的发票汇总一下，按类别算总数。',
    localNote: '先看看文件夹里有什么。',
    localFolder: 'D:\\报销\\10月',
    localRead: 'D:\\报销\\10月\\发票清单.csv',
    localWrite: 'D:\\报销\\10月汇总.csv',
    localAnswer:
      '汇总好了，一共 14 张，合计 ¥2,386：\n交通 ¥612，餐饮 ¥1,174，办公用品 ¥600。\n表格存在 D:\\报销\\10月汇总.csv。',
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
    localAsk: 'Total up the receipts in D:\\Expenses\\October by category.',
    localNote: 'Let me see what is in the folder first.',
    localFolder: 'D:\\Expenses\\October',
    localRead: 'D:\\Expenses\\October\\receipts.csv',
    localWrite: 'D:\\Expenses\\October-summary.csv',
    localAnswer:
      'Done: 14 receipts, $2,386 in total.\nTransport $612, meals $1,174, office supplies $600.\nSaved to D:\\Expenses\\October-summary.csv.',
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

/** Plays its scenes in turn while the window is on screen, and stops when it leaves. */
function replay(root) {
  const body = root.querySelector('.app-body');
  const avatarSlot = root.querySelector('.pill-face');
  const name = root.querySelector('.pill strong');
  const status = root.querySelector('.pill small');
  const send = root.querySelector('.app-send');
  const order = root.dataset.scenes.split(' ');
  let token = 0;
  let scene = order[0];
  let visible = false;
  let playing = false;
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

  async function playLocal(id) {
    const c = copy[lang];
    const bot = bots.zhang;
    const title = bot[lang];
    header(face(bot), title);
    await wait(700, id);
    user(c.localAsk);
    running(true);
    await wait(500, id);
    header(face(bot, true), title, c.thinking);
    const thinking = thinkingDots(body);
    await wait(900, id);
    thinking.remove();
    body.appendChild(el(`<div class="m m-bubble">${c.localNote}</div>`));
    await wait(400, id);
    header(face(bot, true), title, c.tool);
    const list = tool(body, 'search_files', c.localFolder);
    await wait(900, id);
    toolDone(list, '0.3');
    const read = tool(body, 'read_file', c.localRead);
    await wait(1100, id);
    toolDone(read, '0.4');
    const write = tool(body, 'write_file', c.localWrite);
    await wait(1000, id);
    toolDone(write, '0.2');
    header(face(bot, true), title, c.thinking);
    await stream(body, c.localAnswer, id);
    header(face(bot), title);
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

  const players = { dm: playDm, group: playGroup, local: playLocal, ask: playAsk };
  // A scene runs to its end even if the window scrolls away; the next one
  // starts only while it is on screen.
  async function play() {
    const id = ++token;
    playing = true;
    body.innerHTML = '';
    lastBlock = null;
    running(false);
    try {
      await players[scene](id);
      await wait(4200, id);
      scene = order[(order.indexOf(scene) + 1) % order.length];
      playing = false;
      if (visible) void play();
    } catch {
      // A newer replay (a language switch) took over.
    }
  }

  new IntersectionObserver(
    ([entry]) => {
      visible = entry.isIntersecting;
      if (visible && !playing) void play();
    },
    { threshold: 0.35 },
  ).observe(root);

  return {
    restart() {
      if (visible) void play();
    },
  };
}
const replays = [...document.querySelectorAll('.chat[data-scenes]')].map(replay);

/* ---------- small illustrations start the first time they come into view ---------- */
const playObserver = new IntersectionObserver(
  (entries) => {
    for (const entry of entries)
      if (entry.isIntersecting && !reduceMotion) {
        entry.target.classList.add('is-playing');
        playObserver.unobserve(entry.target);
      }
  },
  { threshold: 0.4 },
);
document.querySelectorAll('.play').forEach((node) => playObserver.observe(node));

applyLanguage();
applyTheme();
onScroll();
