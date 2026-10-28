'use strict';

/* ---------- Settings ---------- */

const SETTINGS_KEY = 'lc.settings';
const DEFAULT_SETTINGS = {
  lang: navigator.language || 'en-US',
  size: 32,
  wakeLock: true,
  autoSummarize: true,
  apiKey: '',
  model: 'claude-opus-5-5',
};

function loadSettings() {
  try {
    return { ...DEFAULT_SETTINGS, ...JSON.parse(localStorage.getItem(SETTINGS_KEY) || '{}') };
  } catch {
    return { ...DEFAULT_SETTINGS };
  }
}

function saveSettings() {
  try {
    localStorage.setItem(SETTINGS_KEY, JSON.stringify(settings));
  } catch { /* storage unavailable; settings last for this visit only */ }
}

const settings = loadSettings();

const LANGUAGES = [
  ['en-US', 'English (US)'], ['en-GB', 'English (UK)'], ['en-AU', 'English (Australia)'],
  ['en-CA', 'English (Canada)'], ['en-IN', 'English (India)'], ['es-ES', 'Español (España)'],
  ['es-MX', 'Español (México)'], ['fr-FR', 'Français'], ['de-DE', 'Deutsch'], ['it-IT', 'Italiano'],
  ['pt-BR', 'Português (Brasil)'], ['pt-PT', 'Português (Portugal)'], ['nl-NL', 'Nederlands'],
  ['sv-SE', 'Svenska'], ['pl-PL', 'Polski'], ['ru-RU', 'Русский'], ['uk-UA', 'Українська'],
  ['tr-TR', 'Türkçe'], ['ar-SA', 'العربية'], ['he-IL', 'עברית'], ['hi-IN', 'हिन्दी'],
  ['zh-CN', '中文 (普通话)'], ['zh-TW', '中文 (台灣)'], ['ja-JP', '日本語'], ['ko-KR', '한국어'],
];

/* ---------- Storage (IndexedDB) ---------- */

const DB_NAME = 'live-captions';
const STORE = 'sessions';

function openDb() {
  return new Promise((resolve, reject) => {
    const req = indexedDB.open(DB_NAME, 1);
    req.onupgradeneeded = () => {
      const db = req.result;
      if (!db.objectStoreNames.contains(STORE)) {
        db.createObjectStore(STORE, { keyPath: 'id' }).createIndex('startedAt', 'startedAt');
      }
    };
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
}

const dbPromise = openDb();

async function dbTx(mode, fn) {
  const db = await dbPromise;
  return new Promise((resolve, reject) => {
    const tx = db.transaction(STORE, mode);
    const result = fn(tx.objectStore(STORE));
    tx.oncomplete = () => resolve(result && 'result' in result ? result.result : undefined);
    tx.onerror = () => reject(tx.error);
  });
}

const putSession = (s) => dbTx('readwrite', (st) => st.put(s));
const getSession = (id) => dbTx('readonly', (st) => st.get(id));
const deleteSession = (id) => dbTx('readwrite', (st) => st.delete(id));
const listSessions = async () =>
  (await dbTx('readonly', (st) => st.getAll())).sort((a, b) => b.startedAt - a.startedAt);

/* ---------- Helpers ---------- */

const $ = (id) => document.getElementById(id);

function escapeHtml(s) {
  return s.replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}

function fmtTime(ms) {
  return new Date(ms).toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });
}

function fmtDateTime(ms) {
  return new Date(ms).toLocaleString([], { dateStyle: 'medium', timeStyle: 'short' });
}

function fmtDuration(ms) {
  const mins = Math.round(ms / 60000);
  if (mins < 1) return 'under a minute';
  if (mins < 60) return `${mins} min`;
  return `${Math.floor(mins / 60)} h ${mins % 60} min`;
}

function transcriptText(session, withTimes = true) {
  return session.segments
    .map((s) => (withTimes ? `[${fmtTime(s.t)}] ${s.text}` : s.text))
    .join('\n');
}

function wordCount(session) {
  return session.segments.reduce((n, s) => n + s.text.split(/\s+/).filter(Boolean).length, 0);
}

// Minimal Markdown renderer for summaries: headings, bullets, bold. Input is escaped first.
function renderMarkdown(md) {
  const lines = escapeHtml(md).split('\n');
  let html = '';
  let inList = false;
  for (const raw of lines) {
    const line = raw.replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>');
    const bullet = line.match(/^\s*[-*•]\s+(.*)$/);
    if (bullet) {
      if (!inList) { html += '<ul>'; inList = true; }
      html += `<li>${bullet[1]}</li>`;
      continue;
    }
    if (inList) { html += '</ul>'; inList = false; }
    const heading = line.match(/^#{1,6}\s+(.*)$/);
    if (heading) html += `<h4>${heading[1]}</h4>`;
    else if (line.trim()) html += `<p>${line}</p>`;
  }
  if (inList) html += '</ul>';
  return html;
}

/* ---------- Summaries ---------- */

const SUMMARY_SYSTEM = `You summarize transcripts for a person with hearing loss who used live captions to follow a conversation, meeting, lecture, or appointment.

The transcript came from automatic speech recognition: it has no speaker labels, may merge several voices, and contains recognition errors. Infer the intended words where the context makes them clear.

Write the summary in the transcript's language using this Markdown structure, leaving out any section with nothing to put in it:

## Overview
Two to four sentences on what the conversation was about.

## Key points
Bullets for the main things said or decided.

## Action items & details to remember
Bullets for tasks, dates, times, names, numbers, places, and instructions.

## Possibly misheard
Bullets for passages that look garbled where the meaning is uncertain, with your best guess.

Keep it short and plain. Do not invent anything that isn't supported by the transcript.`;

async function summarizeWithClaude(session) {
  const res = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'x-api-key': settings.apiKey,
      'anthropic-version': '2026-10-21',
      'anthropic-dangerous-direct-browser-access': 'true',
      ...(settings.model === 'claude-haiku-5-5' ? {} : { 'anthropic-beta': 'server-side-fallback-2026-07-01' }),
    },
    body: JSON.stringify({
      model: settings.model,
      max_tokens: 16000,
      ...(settings.model === 'claude-haiku-5-5' ? {} : { fallbacks: 'default' }),
      output_config: { effort: 'medium' },
      system: SUMMARY_SYSTEM,
      messages: [{
        role: 'user',
        content: `Recorded ${fmtDateTime(session.startedAt)}, lasting ${fmtDuration(session.endedAt - session.startedAt)}.\n\n<transcript>\n${transcriptText(session)}\n</transcript>`,
      }],
    }),
  });

  const data = await res.json().catch(() => ({}));
  if (!res.ok) {
    const msg = data.error?.message || `HTTP ${res.status}`;
    if (res.status === 401) throw new Error('The API key was rejected. Check it in Settings.');
    if (res.status === 429) throw new Error('Rate limited by the API. Try again in a minute.');
    throw new Error(msg);
  }
  if (data.stop_reason === 'refusal') throw new Error('The model declined to summarize this transcript.');

  const text = (data.content || []).filter((b) => b.type === 'text').map((b) => b.text).join('\n').trim();
  if (!text) throw new Error('The model returned an empty summary.');
  return text;
}

const STOPWORDS = new Set(('a an the and or but if then so of to in on at for with from by as is are was were be been ' +
  'being it its this that these those i you he she we they me him her us them my your his our their what which who ' +
  'whom do does did have has had not no yes just like um uh okay ok yeah oh well really very can could would should ' +
  'will shall may might there here about into out up down over all any some get got go going know think say said').split(' '));

// Offline fallback: pick the most representative sentences by word frequency.
function summarizeLocally(session) {
  const text = transcriptText(session, false);
  const sentences = text.split(/(?<=[.!?])\s+|\n+/).map((s) => s.trim()).filter((s) => s.split(/\s+/).length >= 4);
  const words = wordCount(session);
  const header = `## Overview\nBasic on-device summary (${words} words over ${fmtDuration(session.endedAt - session.startedAt)}). ` +
    'Add an Anthropic API key in Settings for a better AI summary.\n';
  if (sentences.length <= 5) {
    return header + (sentences.length ? `\n## Key points\n${sentences.map((s) => `- ${s}`).join('\n')}` : '');
  }

  const freq = new Map();
  for (const w of text.toLowerCase().match(/[\p{L}\p{N}']+/gu) || []) {
    if (!STOPWORDS.has(w) && w.length > 2) freq.set(w, (freq.get(w) || 0) + 1);
  }
  const scored = sentences.map((s, i) => {
    const toks = s.toLowerCase().match(/[\p{L}\p{N}']+/gu) || [];
    const score = toks.reduce((n, w) => n + (freq.get(w) || 0), 0) / Math.sqrt(toks.length || 1);
    return { s, i, score };
  });
  const n = Math.min(8, Math.max(3, Math.round(sentences.length / 10)));
  const top = scored.sort((a, b) => b.score - a.score).slice(0, n).sort((a, b) => a.i - b.i);
  const topics = [...freq.entries()].sort((a, b) => b[1] - a[1]).slice(0, 8).map(([w]) => w);

  return header +
    `\n## Frequent topics\n- ${topics.join(', ')}\n` +
    `\n## Key points\n${top.map((x) => `- ${x.s}`).join('\n')}`;
}

async function summarizeSession(session) {
  if (!session.segments.length) {
    session.summary = 'Nothing was captured in this session.';
    session.summarySource = 'none';
  } else if (settings.apiKey) {
    try {
      session.summary = await summarizeWithClaude(session);
      session.summarySource = 'claude';
    } catch (err) {
      session.summary = summarizeLocally(session) + `\n\n## Note\nAI summary failed: ${err.message}`;
      session.summarySource = 'local';
    }
  } else {
    session.summary = summarizeLocally(session);
    session.summarySource = 'local';
  }
  await putSession(session);
  return session;
}

/* ---------- Speech recognition ---------- */

const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition;

let recognition = null;
let session = null;         // the session being recorded
let listening = false;      // user wants captions running
let interimEl = null;
let wakeLock = null;
let saveTimer = null;
let restartTimer = null;
let followLatest = true;

const captionsEl = $('captions');
const statusEl = $('status');
const toggleBtn = $('btn-toggle');

function setStatus(text, live = false) {
  statusEl.textContent = text;
  statusEl.classList.toggle('listening', live);
}

function scrollToLatest() {
  if (followLatest) captionsEl.scrollTop = captionsEl.scrollHeight;
}

captionsEl.addEventListener('scroll', () => {
  const atBottom = captionsEl.scrollHeight - captionsEl.scrollTop - captionsEl.clientHeight < 40;
  followLatest = atBottom;
  $('jump-latest').hidden = atBottom || !listening;
});

$('jump-latest').addEventListener('click', () => {
  followLatest = true;
  scrollToLatest();
  $('jump-latest').hidden = true;
});

function addFinal(text) {
  text = text.trim();
  if (!text) return;
  const seg = { t: Date.now(), text };
  session.segments.push(seg);
  const p = document.createElement('p');
  p.textContent = text;
  // Show a time marker when there has been a pause of over a minute.
  const prev = session.segments[session.segments.length - 2];
  if (!prev || seg.t - prev.t > 60000) {
    const ts = document.createElement('span');
    ts.className = 'ts';
    ts.textContent = fmtTime(seg.t);
    p.prepend(ts);
  }
  captionsEl.insertBefore(p, interimEl);
  scheduleSave();
}

function setInterim(text) {
  interimEl.textContent = text;
  scrollToLatest();
}

function scheduleSave() {
  clearTimeout(saveTimer);
  saveTimer = setTimeout(() => {
    session.endedAt = Date.now();
    putSession(session).catch(() => {});
  }, 3000);
}

function createRecognition() {
  const r = new SpeechRecognition();
  r.continuous = true;
  r.interimResults = true;
  r.lang = settings.lang;
  r.maxAlternatives = 1;

  r.onstart = () => setStatus('Listening…', true);

  r.onresult = (e) => {
    let interim = '';
    for (let i = e.resultIndex; i < e.results.length; i++) {
      const res = e.results[i];
      if (res.isFinal) addFinal(res[0].transcript);
      else interim += res[0].transcript;
    }
    setInterim(interim);
  };

  r.onerror = (e) => {
    if (e.error === 'no-speech' || e.error === 'aborted') return; // normal; onend restarts
    if (e.error === 'not-allowed' || e.error === 'service-not-allowed') {
      setStatus('Microphone permission was denied. Allow microphone access for this site, then press Start.');
      stopListening();
    } else if (e.error === 'audio-capture') {
      setStatus('No microphone found. Connect a microphone or headset and press Start.');
      stopListening();
    } else if (e.error === 'network') {
      setStatus('Speech service unreachable. Check your internet connection — retrying…');
    } else if (e.error === 'language-not-supported') {
      setStatus('This language isn\'t supported here. Pick another in Settings.');
      stopListening();
    } else {
      setStatus(`Recognition error: ${e.error}. Retrying…`);
    }
  };

  // Browsers end recognition after silence or a time limit; restart while the user wants captions.
  r.onend = () => {
    if (!listening) return;
    if (interimEl.textContent) addFinal(interimEl.textContent);
    setInterim('');
    clearTimeout(restartTimer);
    restartTimer = setTimeout(() => {
      if (!listening) return;
      try { r.start(); } catch { /* already started */ }
    }, 250);
  };

  return r;
}

async function requestWakeLock() {
  if (!settings.wakeLock || !('wakeLock' in navigator)) return;
  try {
    wakeLock = await navigator.wakeLock.request('screen');
  } catch { /* not granted; ignore */ }
}

document.addEventListener('visibilitychange', () => {
  if (document.visibilityState === 'visible' && listening) requestWakeLock();
});

function startListening() {
  if (!SpeechRecognition) return;
  session = {
    id: (crypto.randomUUID && crypto.randomUUID()) || String(Date.now()),
    startedAt: Date.now(),
    endedAt: Date.now(),
    lang: settings.lang,
    segments: [],
    summary: '',
    summarySource: '',
  };
  captionsEl.innerHTML = '';
  interimEl = document.createElement('p');
  interimEl.className = 'interim';
  captionsEl.appendChild(interimEl);
  followLatest = true;

  listening = true;
  recognition = createRecognition();
  try {
    recognition.start();
  } catch (err) {
    setStatus(`Couldn't start: ${err.message}`);
    listening = false;
    return;
  }
  toggleBtn.textContent = 'Stop';
  toggleBtn.classList.add('recording');
  setStatus('Starting microphone…');
  requestWakeLock();
}

async function stopListening() {
  if (!listening) return;
  listening = false;
  clearTimeout(restartTimer);
  clearTimeout(saveTimer);
  try { recognition.stop(); } catch { /* ignore */ }
  if (interimEl && interimEl.textContent) addFinal(interimEl.textContent);
  if (interimEl) setInterim('');
  if (wakeLock) { wakeLock.release().catch(() => {}); wakeLock = null; }

  toggleBtn.textContent = 'Start';
  toggleBtn.classList.remove('recording');
  $('jump-latest').hidden = true;

  const finished = session;
  finished.endedAt = Date.now();
  if (!finished.segments.length) {
    setStatus('Stopped. Nothing was captured, so nothing was saved.');
    return;
  }
  finished.title = defaultTitle(finished);
  await putSession(finished);

  if (settings.autoSummarize) {
    setStatus('Saved. Writing summary…');
    await summarizeSession(finished);
    setStatus('Saved and summarized. Open the Saved tab to read it.');
  } else {
    setStatus('Saved. Open the Saved tab to read or summarize it.');
  }
  if (activeView === 'history') renderHistory();
}

function defaultTitle(s) {
  const first = s.segments[0]?.text || '';
  const snippet = first.split(/\s+/).slice(0, 7).join(' ');
  return snippet ? `${snippet}${first.split(/\s+/).length > 7 ? '…' : ''}` : 'Untitled session';
}

toggleBtn.addEventListener('click', () => (listening ? stopListening() : startListening()));

// Save what we have if the page is closed mid-session.
window.addEventListener('pagehide', () => {
  if (listening && session) {
    session.endedAt = Date.now();
    session.title = defaultTitle(session);
    putSession(session).catch(() => {});
  }
});

/* ---------- Text size ---------- */

function applySize() {
  document.documentElement.style.setProperty('--caption-size', `${settings.size}px`);
  $('set-size').value = settings.size;
  $('set-size-val').textContent = `${settings.size}px`;
}

function changeSize(delta) {
  settings.size = Math.min(72, Math.max(18, settings.size + delta));
  applySize();
  saveSettings();
  scrollToLatest();
}

$('btn-smaller').addEventListener('click', () => changeSize(-4));
$('btn-larger').addEventListener('click', () => changeSize(4));

/* ---------- Views ---------- */

let activeView = 'live';

function showView(name) {
  activeView = name;
  document.querySelectorAll('.tab').forEach((t) => {
    const on = t.dataset.view === name;
    t.classList.toggle('active', on);
    t.setAttribute('aria-selected', String(on));
  });
  document.querySelectorAll('.view').forEach((v) => v.classList.toggle('active', v.id === `view-${name}`));
  if (name === 'history') renderHistory();
}

document.querySelectorAll('.tab').forEach((t) => t.addEventListener('click', () => showView(t.dataset.view)));

/* ---------- History ---------- */

let currentDetail = null;

async function renderHistory() {
  $('session-detail').hidden = true;
  const list = $('history-list');
  list.hidden = false;
  const sessions = await listSessions();
  if (!sessions.length) {
    list.innerHTML = '<p class="empty">No saved transcripts yet. Start a live session and press Stop to save it.</p>';
    return;
  }
  list.innerHTML = '';
  for (const s of sessions) {
    const btn = document.createElement('button');
    btn.className = 'history-item';
    const inProgress = listening && session && s.id === session.id;
    btn.innerHTML = `<strong>${escapeHtml(s.title || defaultTitle(s))}</strong>
      <span class="meta">${fmtDateTime(s.startedAt)} · ${fmtDuration(s.endedAt - s.startedAt)} · ${wordCount(s)} words${inProgress ? ' · recording now' : ''}</span>`;
    btn.addEventListener('click', () => openDetail(s.id));
    list.appendChild(btn);
  }
}

async function openDetail(id) {
  const s = await getSession(id);
  if (!s) return renderHistory();
  currentDetail = s;
  $('history-list').hidden = true;
  $('session-detail').hidden = false;
  $('detail-title').textContent = s.title || defaultTitle(s);
  $('detail-meta').textContent =
    `${fmtDateTime(s.startedAt)} · ${fmtDuration(s.endedAt - s.startedAt)} · ${wordCount(s)} words`;
  renderSummary(s);
  $('detail-transcript').innerHTML = s.segments
    .map((seg) => `<p><span class="ts">${fmtTime(seg.t)}</span>${escapeHtml(seg.text)}</p>`)
    .join('');
}

function renderSummary(s) {
  const el = $('detail-summary');
  if (!s.summary) {
    el.innerHTML = '<p class="meta">No summary yet. Press “Summarize again” to create one.</p>';
    return;
  }
  const source = s.summarySource === 'claude' ? '<p class="meta">Summary written by Claude.</p>' : '';
  el.innerHTML = renderMarkdown(s.summary) + source;
}

$('btn-back').addEventListener('click', renderHistory);

$('btn-summarize').addEventListener('click', async () => {
  if (!currentDetail) return;
  const btn = $('btn-summarize');
  btn.disabled = true;
  btn.textContent = 'Summarizing…';
  $('detail-summary').innerHTML = '<p class="meta">Writing summary…</p>';
  try {
    await summarizeSession(currentDetail);
    renderSummary(currentDetail);
  } finally {
    btn.disabled = false;
    btn.textContent = 'Summarize again';
  }
});

function exportText(s) {
  return `${s.title || defaultTitle(s)}\n${fmtDateTime(s.startedAt)} (${fmtDuration(s.endedAt - s.startedAt)})\n\n` +
    (s.summary ? `SUMMARY\n${s.summary}\n\n` : '') +
    `TRANSCRIPT\n${transcriptText(s)}\n`;
}

$('btn-copy').addEventListener('click', async () => {
  if (!currentDetail) return;
  try {
    await navigator.clipboard.writeText(exportText(currentDetail));
    $('btn-copy').textContent = 'Copied!';
  } catch {
    $('btn-copy').textContent = 'Copy failed';
  }
  setTimeout(() => ($('btn-copy').textContent = 'Copy'), 1500);
});

$('btn-download').addEventListener('click', () => {
  if (!currentDetail) return;
  const blob = new Blob([exportText(currentDetail)], { type: 'text/plain' });
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob);
  const d = new Date(currentDetail.startedAt);
  a.download = `transcript-${d.toISOString().slice(0, 16).replace(/[:T]/g, '-')}.txt`;
  a.click();
  setTimeout(() => URL.revokeObjectURL(a.href), 1000);
});

$('btn-delete').addEventListener('click', async () => {
  if (!currentDetail) return;
  if (!confirm('Delete this transcript? This cannot be undone.')) return;
  await deleteSession(currentDetail.id);
  currentDetail = null;
  renderHistory();
});

/* ---------- Settings form ---------- */

function initSettingsForm() {
  const langSel = $('set-lang');
  const langs = LANGUAGES.some(([code]) => code === settings.lang)
    ? LANGUAGES
    : [[settings.lang, settings.lang], ...LANGUAGES];
  langSel.innerHTML = langs.map(([code, name]) => `<option value="${code}">${escapeHtml(name)}</option>`).join('');
  langSel.value = settings.lang;
  $('set-wakelock').checked = settings.wakeLock;
  $('set-autosum').checked = settings.autoSummarize;
  $('set-key').value = settings.apiKey;
  $('set-model').value = settings.model;
  applySize();

  const flash = () => {
    saveSettings();
    $('saved-msg').textContent = 'Settings saved.';
    setTimeout(() => ($('saved-msg').textContent = ''), 1500);
  };
  langSel.addEventListener('change', () => {
    settings.lang = langSel.value;
    if (recognition) recognition.lang = settings.lang; // applies on the next automatic restart
    flash();
  });
  $('set-size').addEventListener('input', (e) => { settings.size = Number(e.target.value); applySize(); flash(); });
  $('set-wakelock').addEventListener('change', (e) => { settings.wakeLock = e.target.checked; flash(); });
  $('set-autosum').addEventListener('change', (e) => { settings.autoSummarize = e.target.checked; flash(); });
  $('set-key').addEventListener('change', (e) => { settings.apiKey = e.target.value.trim(); flash(); });
  $('set-model').addEventListener('change', (e) => { settings.model = e.target.value; flash(); });
}

/* ---------- Boot ---------- */

initSettingsForm();

if (!SpeechRecognition) {
  $('unsupported').hidden = false;
  toggleBtn.disabled = true;
  setStatus('');
}

if ('serviceWorker' in navigator && location.protocol !== 'file:') {
  navigator.serviceWorker.register('sw.js').catch(() => {});
}
