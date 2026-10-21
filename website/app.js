/* Petal website. Release metadata lives in this one object: update it after each build. */
const RELEASE = { version: "0.1.0", file: "https://github.com/LucaLivigni/Petal/releases/download/v0.1.0/Petal-0.1.0.dmg", size: "11 MB", sha256: "f1b59a24898d6bc995dda921965290bd84d67aad8d69d8eeab4b88cf3575f1fe", requires: "macOS 15 or later · Apple silicon", notarized: false };

(() => {
  "use strict";

  const $ = (sel, root = document) => root.querySelector(sel);
  const $$ = (sel, root = document) => Array.from(root.querySelectorAll(sel));
  const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
  const NS = "http://www.w3.org/2000/svg";

  /* ---------- Release metadata ---------- */
  const fileName = RELEASE.file.split("/").pop();
  $$("[data-download]").forEach((a) => { a.href = RELEASE.file; });
  $$("[data-release]").forEach((el) => {
    const key = el.dataset.release;
    if (key === "label") el.textContent = `Version ${RELEASE.version} · ${RELEASE.requires}`;
    else if (key === "filename") el.textContent = fileName;
    else if (RELEASE[key] != null) el.textContent = RELEASE[key];
  });

  // Until a release is notarized, say honestly what the first launch looks like.
  $$("[data-unnotarized]").forEach((el) => { el.hidden = RELEASE.notarized === true; });

  const copyBtn = $("[data-copy]");
  if (copyBtn) {
    const hasHash = /^[0-9a-f]{64}$/i.test(RELEASE.sha256);
    if (!hasHash) { copyBtn.disabled = true; copyBtn.title = "The checksum will be published with the release."; }
    copyBtn.addEventListener("click", async () => {
      try { await navigator.clipboard.writeText(RELEASE.sha256); }
      catch {
        const t = document.createElement("textarea");
        t.value = RELEASE.sha256; t.style.position = "fixed"; t.style.opacity = "0";
        document.body.appendChild(t); t.select();
        try { document.execCommand("copy"); } catch { /* nothing else to try */ }
        t.remove();
      }
      copyBtn.textContent = "Copied";
      setTimeout(() => { copyBtn.textContent = "Copy"; }, 1600);
    });
  }

  /* ---------- Navigation edge ---------- */
  const sentinel = $("#top-sentinel"), nav = $(".nav");
  if (sentinel && nav && "IntersectionObserver" in window) {
    new IntersectionObserver(([e]) => nav.classList.toggle("is-scrolled", !e.isIntersecting)).observe(sentinel);
  }

  /* ---------- Accent picker ---------- */
  const root = document.documentElement;
  const swatches = $$(".swatch");
  const accentName = $("#accent-name");
  function setAccent(name, label) {
    root.dataset.accent = name;
    swatches.forEach((s) => s.setAttribute("aria-checked", String(s.dataset.accent === name)));
    if (accentName) accentName.textContent = label;
  }
  swatches.forEach((s, i) => {
    s.addEventListener("click", () => setAccent(s.dataset.accent, s.getAttribute("aria-label")));
    s.addEventListener("keydown", (e) => {
      const d = { ArrowRight: 1, ArrowDown: 1, ArrowLeft: -1, ArrowUp: -1 }[e.key];
      if (!d) return;
      e.preventDefault();
      const n = swatches[(i + d + swatches.length) % swatches.length];
      n.focus(); n.click();
    });
  });

  /* ---------- Simulated desktop ---------- */
  const screen = $("#screen");
  if (!screen) return;

  const rm = () => reduceMotion.matches;
  const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const clamp = (v, lo, hi) => Math.min(Math.max(v, lo), Math.max(lo, hi));
  const live = $("#live");
  const say = (msg) => { live.textContent = ""; setTimeout(() => { live.textContent = msg; }, 40); };
  const fmt = (mb) => (mb < 1 ? `${Math.max(1, Math.round(mb * 1024))} KB` : mb >= 10 ? `${Math.round(mb)} MB` : `${(Math.round(mb * 10) / 10).toFixed(1)} MB`);

  /* ----- One table: kinds -> wheels -> items. Labels and hints follow the app. ----- */
  const LAB = { jpg: "JPG", png: "PNG", webp: "WebP", heic: "HEIC", tiff: "TIFF", avif: "AVIF", bmp: "BMP", gif: "GIF", pdf: "PDF", ico: "ICO", icns: "ICNS",
    docx: "DOCX", md: "MD", epub: "EPUB", txt: "TXT", pptx: "PPTX", xlsx: "XLSX", html: "HTML", rtf: "RTF", odt: "ODT", csv: "CSV", tsv: "TSV", json: "JSON", ods: "ODS",
    mp4: "MP4", webm: "WebM", mkv: "MKV", avi: "AVI", wmv: "WMV", wav: "WAV", mp3: "MP3", m4a: "M4A", flac: "FLAC", aiff: "AIFF", ogg: "OGG", opus: "Opus", wma: "WMA", caf: "CAF",
    zip: "ZIP", tar: "TAR", "tar.gz": "TAR.GZ", mov: "MOV", svg: "SVG" };
  const HINT = { jpg: "Photos", png: "Lossless", heic: "Efficient", webp: "Web", avif: "Smallest", tiff: "Archival", gif: "Animated", bmp: "Legacy", pdf: "Document", ico: "Icon", icns: "App icon",
    mp4: "Universal", webm: "Web video", mkv: "Container", avi: "Legacy", wmv: "Windows video", wav: "Uncompressed", mp3: "Universal audio", m4a: "AAC audio", flac: "Lossless audio",
    aiff: "Uncompressed", ogg: "Vorbis", opus: "Voice & music", wma: "Windows audio", caf: "Core Audio", docx: "Word", md: "Markdown", epub: "E-book", txt: "Plain text", pptx: "Slides",
    xlsx: "Excel", html: "Web page", rtf: "Rich text", odt: "OpenDocument", csv: "Spreadsheet", tsv: "Tab separated", json: "Structured data", ods: "OpenDocument", tar: "Archive", "tar.gz": "Unix archive", zip: "Archive" };
  const cv = (ext, f, hint) => ({ type: "convert", id: "to-" + ext, ext, f, l: [LAB[ext]], t: LAB[ext], h: hint != null ? hint : HINT[ext] || "" });
  const tf = (id, l, h, o) => ({ type: "file", id, l, t: l.join(" "), h, ...o });
  const tt = (id, l, h, msg) => ({ type: "toast", id, l, t: l.join(" "), h, msg });
  const archive = (ext, f) => ({ type: "archive", id: "pack-" + ext, ext, f, l: [LAB[ext]], t: LAB[ext], h: HINT[ext] });
  const act = (id, l, t, h) => ({ type: "action", id, l, t, h });

  const T = {
    edit: tt("edit", ["Edit"], "Crop and adjust", "Opens the editor window"),
    bg: tt("bg", ["Background"], "Change the background", "Opens the editor window"),
    compress: tf("compress", ["Compress"], "Smaller file", { suffix: "compressed", f: 0.4, saving: true }),
    half: tf("resize-half", ["Resize ½"], "50% of the size", { suffix: "resized", f: 0.3, scale: 0.5 }),
    fit: tf("fit-1920", ["Fit 1920"], "Longest side 1920 px", { suffix: "resized", f: 0.55, fit: 1920 }),
    cut: tf("cutout", ["Cut out"], "Remove background", { suffix: "cutout", ext: "png", f: 1.8, art: "cutout" }),
    ocr: tt("ocr", ["Copy", "text"], "Recognise text", "Text copied"),
    rotL: tf("rotate-left", ["Rotate", "left"], "", { suffix: "rotated", f: 1, turn: true }),
    rotR: tf("rotate-right", ["Rotate", "right"], "", { suffix: "rotated", f: 1, turn: true }),
    flip: tf("flip", ["Flip"], "Mirror horizontally", { suffix: "flipped", f: 1 }),
    bw: tf("bw", ["Black &", "white"], "", { suffix: "bw", f: 0.8 }),
    strip: tf("strip", ["Strip", "metadata"], "Remove EXIF & location", { suffix: "clean", f: 0.99 }),
    pcompress: tf("compress", ["Compress"], "Smaller file", { suffix: "compressed", f: 0.6, saving: true }),
    split: tf("split", ["Split", "pages"], "One file per page", { suffix: "pages", folder: true, f: 1 }),
    prot: tf("rotate", ["Rotate"], "Quarter turn right", { suffix: "rotated", f: 1 }),
    pcopy: tt("copy-text", ["Copy", "text"], "Selectable text", "Text copied"),
    vtrim: tt("trim", ["Trim"], "Cut to length", "Opens the trim window"),
    vcompress: tf("compress", ["Compress"], "720p H.264", { suffix: "compressed", f: 0.38, saving: true, tag: "compress" }),
    vaudio: tf("extract-audio", ["Extract", "audio"], "M4A", { ext: "m4a", f: 0.013 }),
    mute: tf("mute", ["Mute"], "Remove the sound", { suffix: "muted", f: 0.98 }),
    vgif: tf("make-gif", ["Make", "GIF"], "First 30 s", { ext: "gif", f: 0.09, noDur: true }),
    acompress: tf("compress", ["Compress"], "AAC 96 kbps", { suffix: "compressed", ext: "m4a", f: 0.3, saving: true }),
    zlist: tt("contents", ["Copy", "contents"], "File list", "File list copied"),
    zsum: tt("checksum", ["Checksum"], "SHA‑256", "SHA-256 copied"),
    zsize: tt("size", ["Size"], "Total on disk", (f) => `Total on disk: ${fmt(f.mb)}`),
    fzip: tf("zip", ["Zip"], "Compress to ZIP", { ext: "zip", f: 0.9 }),
  };
  const ACTIONS = [
    act("airdrop", ["AirDrop"], "AirDrop", "Send nearby"), act("copy", ["Copy"], "Copy", "To clipboard"), act("copypath", ["Copy", "path"], "Copy path", ""),
    act("move", ["Move to…"], "Move to…", "Choose a folder"), act("copyto", ["Copy to…"], "Copy to…", "Choose a folder"), act("terminal", ["Terminal"], "Terminal", "Open here"),
    act("float", ["Float"], "Float", "Keep on screen"), act("reveal", ["Show"], "Show", "In Finder"),
  ];
  const WHEELS = {
    image: { convert: [cv("jpg", 0.34), cv("png", 2.9), cv("webp", 0.3), cv("heic", 0.5), cv("tiff", 7), cv("avif", 0.18), cv("bmp", 11), cv("gif", 1.4), cv("pdf", 0.55)],
      tools: [T.edit, T.bg, T.compress, T.half, T.fit, T.cut, T.ocr, T.rotL, T.rotR, T.flip, T.bw, T.strip] },
    svg: { convert: [cv("png", 3), cv("jpg", 2), cv("webp", 1.5), cv("pdf", 2), cv("ico", 1.2), cv("icns", 6), cv("tiff", 10)] },
    pdf: { convert: [cv("docx", 0.6), cv("md", 0.02), cv("epub", 0.5), cv("txt", 0.01), cv("pptx", 1.2), cv("xlsx", 0.5), cv("jpg", 0.9), cv("png", 2.4), cv("tiff", 3.5)],
      tools: [T.pcompress, T.split, T.prot, T.pcopy] },
    doc: { convert: [cv("pdf", 3.2), cv("md", 0.5), cv("epub", 1.4), cv("html", 1.1), cv("rtf", 1.8), cv("odt", 0.9), cv("txt", 0.2), cv("docx", 1)] },
    sheet: { convert: [cv("csv", 0.4), cv("tsv", 0.4), cv("json", 0.8), cv("ods", 0.9), cv("pdf", 2.5), cv("html", 1.2), cv("xlsx", 1)] },
    video: { convert: [cv("mp4", 0.55), cv("webm", 0.35), cv("mkv", 0.98), cv("avi", 1.6), cv("wmv", 0.9), cv("gif", 0.17), cv("wav", 0.14, "Extract audio"), cv("mp3", 0.02, "Extract audio")],
      tools: [T.vtrim, T.vcompress, T.vaudio, T.mute, T.vgif] },
    audio: { convert: [cv("m4a", 0.1), cv("mp3", 0.1), cv("flac", 0.55), cv("aiff", 1), cv("ogg", 0.09), cv("opus", 0.06), cv("wma", 0.1), cv("caf", 1)], tools: [T.vtrim, T.acompress] },
    zip: { convert: [{ type: "folder", id: "extract", l: ["Extract"], t: "Extract", h: "Unpack here" }, cv("tar", 1.02), cv("tar.gz", 0.99)], tools: [T.zlist, T.zsum, T.zsize] },
    folder: { convert: [], tools: [T.zsize, T.fzip] },
    multi: { convert: [archive("zip", 0.92), archive("tar", 1.02), archive("tar.gz", 0.9)], tools: [] },
  };
  const EXT = { image: ["heic", "jpg", "jpeg", "png", "webp", "tiff", "avif", "bmp", "gif", "ico", "icns"], svg: ["svg"], pdf: ["pdf"], doc: ["docx", "md", "epub", "html", "rtf", "odt", "txt"],
    sheet: ["xlsx", "csv", "tsv", "json", "ods"], video: ["mov", "mp4", "webm", "mkv", "avi", "wmv"], audio: ["wav", "mp3", "m4a", "flac", "aiff", "ogg", "opus", "wma", "caf"], zip: ["zip", "tar", "tar.gz"] };
  const wheelOf = (f) => (f.multi ? "multi" : f.folder ? "folder" : Object.keys(EXT).find((k) => EXT[k].includes(f.ext)) || "doc");
  const listFor = (f, mode) => (mode === "actions" ? ACTIONS : ((WHEELS[wheelOf(f)] || {})[mode] || []).filter((it) => it.type !== "convert" || it.ext !== f.ext));

  /* ----- Icons: drawn here, shown everywhere (desktop, mail, cards, Finder) ----- */
  const FONT = "-apple-system,system-ui,sans-serif";
  const svgOpen = '<svg viewBox="0 0 64 64" aria-hidden="true" focusable="false">';
  const PAGE = "M14 4h26l14 14v38a4 4 0 0 1-4 4H14a4 4 0 0 1-4-4V8a4 4 0 0 1 4-4z";
  const page = (band, label, deco) => `${svgOpen}<path d="${PAGE}" fill="#fff"/><path d="M40 4v10a4 4 0 0 0 4 4h10z" fill="#dde0e6"/>${deco}<path d="M10 41h44v15a4 4 0 0 1-4 4H14a4 4 0 0 1-4-4z" fill="${band}"/><text x="32" y="53" text-anchor="middle" font-family="${FONT}" font-size="${label.length > 4 ? 7 : 9}" font-weight="700" fill="#fff">${label}</text><path d="${PAGE}" fill="none" stroke="rgba(0,0,0,.16)"/></svg>`;
  const LINES = '<rect x="16" y="22" width="22" height="3.4" rx="1.7" fill="#bfc5d0"/><rect x="16" y="29" width="32" height="3" rx="1.5" fill="#dfe2e8"/><rect x="16" y="35" width="26" height="3" rx="1.5" fill="#dfe2e8"/>';
  const GRID = Array.from({ length: 9 }, (_, i) => `<rect x="${16 + (i % 3) * 10.6}" y="${22 + Math.floor(i / 3) * 5.8}" width="9.2" height="4.4" rx="1" fill="${i < 3 ? "#9bd9b7" : "#d6efe0"}"/>`).join("");
  const ZIPPER = Array.from({ length: 8 }, (_, i) => `<rect x="${i % 2 ? 32 : 27.6}" y="${5 + i * 4.2}" width="4.4" height="2.6" rx=".8" fill="#8b909b"/>`).join("") + '<rect x="27" y="35" width="10" height="7" rx="2.4" fill="#6a707c"/>';
  const ART = {
    photo: '<rect x="7" y="14" width="50" height="36" fill="url(#g-sky)"/><circle cx="43" cy="25" r="5.5" fill="#fff3d6"/><path d="M7 42c8-9 15-10 21-5 6-6 15-9 29-1v14H7z" fill="#e8742a"/><path d="M7 46c10-5 22-3 30-1 8 2 14 1 20-2v7H7z" fill="#b94a1c"/>',
    shot: '<rect x="7" y="14" width="50" height="36" fill="#1e2a45"/><rect x="7" y="14" width="50" height="6" fill="#2e3d63"/><circle cx="11" cy="17" r="1.2" fill="#ff6a5f"/><circle cx="15" cy="17" r="1.2" fill="#ffc04d"/><circle cx="19" cy="17" r="1.2" fill="#4ede7a"/><rect x="7" y="20" width="12" height="30" fill="#26355a"/><rect x="23" y="25" width="28" height="3" rx="1.5" fill="#6f84b8"/><rect x="23" y="31" width="20" height="3" rx="1.5" fill="#4b5f93"/><rect x="23" y="38" width="16" height="9" rx="2" fill="#4aa3ff"/>',
    logo: '<rect x="7" y="14" width="50" height="36" fill="#f6f3ff"/><circle cx="27" cy="32" r="10" fill="#7a4ee0"/><rect x="31" y="22" width="20" height="20" rx="5" fill="#ff8a1f" fill-opacity=".92" transform="rotate(14 41 32)"/>',
    cutout: '<rect x="7" y="14" width="50" height="36" fill="url(#p-check)"/><circle cx="43" cy="25" r="5.5" fill="#ff9f57"/><path d="M7 42c8-9 15-10 21-5 6-6 15-9 29-1v14H7z" fill="#e8742a"/><path d="M7 46c10-5 22-3 30-1 8 2 14 1 20-2v7H7z" fill="#b94a1c"/>',
  };
  const photo = (art) => `${svgOpen}<rect x="4" y="11" width="56" height="42" rx="6" fill="#fff"/><g clip-path="url(#c-photo)">${ART[art] || ART.photo}</g><rect x="4.5" y="11.5" width="55" height="41" rx="5.5" fill="none" stroke="rgba(0,0,0,.16)"/></svg>`;
  const VIDEO = `${svgOpen}<rect x="4" y="12" width="56" height="40" rx="6" fill="url(#g-vid)"/><path d="M4 44c12-10 22-6 30-2 10-5 18-3 26 2v2a6 6 0 0 1-6 6H10a6 6 0 0 1-6-6z" fill="#fff" fill-opacity=".08"/><circle cx="32" cy="32" r="10.5" fill="#fff" fill-opacity=".9"/><path d="M29 27l9 5-9 5z" fill="#1d1d1f"/></svg>`;
  const AUDIO = `${svgOpen}<rect x="8" y="8" width="48" height="48" rx="11" fill="url(#g-aud)"/>${[10, 22, 32, 18, 26, 12].map((h, i) => `<rect x="${15 + i * 6.8}" y="${32 - h / 2}" width="3.6" height="${h}" rx="1.8" fill="#fff" fill-opacity=".94"/>`).join("")}</svg>`;
  const FOLDER = `${svgOpen}<path d="M6 16a4 4 0 0 1 4-4h14l5 5h25a4 4 0 0 1 4 4v28a4 4 0 0 1-4 4H10a4 4 0 0 1-4-4z" fill="#4c9fee"/><path d="M6 24a4 4 0 0 1 4-4h44a4 4 0 0 1 4 4v24a4 4 0 0 1-4 4H10a4 4 0 0 1-4-4z" fill="url(#g-fold)"/></svg>`;
  function iconSVG(f) {
    const k = wheelOf(f);
    if (k === "folder") return FOLDER;
    if (k === "multi") return page("#6e7787", "ITEMS", LINES);
    if (k === "image") return photo(f.art || "photo");
    if (k === "svg") return photo("logo");
    if (k === "video") return VIDEO;
    if (k === "audio") return AUDIO;
    if (k === "pdf") return page("#e5453b", "PDF", LINES);
    if (k === "sheet") return page("#1f9d5b", f.ext.toUpperCase(), GRID);
    if (k === "zip") return page("#8b909b", f.ext === "tar.gz" ? "TAR.GZ" : f.ext.toUpperCase(), ZIPPER);
    return page(f.ext === "docx" ? "#2d6fe0" : "#6e7787", f.ext.toUpperCase(), LINES);
  }
  const hasBadge = (f) => ["image", "svg", "video", "audio"].includes(wheelOf(f));
  const iconHTML = (f) => `<span class="icon">${iconSVG(f)}${hasBadge(f) ? `<span class="badge">${esc(f.ext === "svg" ? "SVG" : f.ext.toUpperCase())}</span>` : ""}</span>`;

  /* ----- Files: free placement, like icons on a real desktop. Positions are fractions of the desktop. ----- */
  const SEED = [
    { id: "holiday", base: "holiday", ext: "heic", mb: 3.2, dims: [4032, 3024], art: "photo", p: { d: [0.095, 0.205], c: [0.17, 0.2] } },
    { id: "screenshot", base: "screenshot", ext: "png", mb: 1.6, dims: [2560, 1440], art: "shot", hideNarrow: true, p: { d: [0.285, 0.145] } },
    { id: "logo", base: "logo", ext: "svg", mb: 0.012, hideNarrow: true, p: { d: [0.455, 0.285] } },
    { id: "report", base: "report", ext: "pdf", mb: 1.4, pages: 12, p: { d: [0.065, 0.455], c: [0.52, 0.14] } },
    { id: "notes", base: "notes", ext: "docx", mb: 0.084, hideNarrow: true, p: { d: [0.235, 0.385] } },
    { id: "budget", base: "budget", ext: "xlsx", mb: 0.209, p: { d: [0.415, 0.52], c: [0.83, 0.31] } },
    { id: "weekend", base: "weekend", ext: "mov", mb: 84, dur: "1:12", p: { d: [0.14, 0.675], c: [0.28, 0.63] } },
    { id: "voice", base: "voice-memo", ext: "wav", mb: 18, dur: "2:04", p: { d: [0.335, 0.725], c: [0.7, 0.75] } },
    { id: "project", base: "project", ext: "zip", mb: 6.8, hideNarrow: true, p: { d: [0.545, 0.175] } },
  ];
  const nameOf = (f) => (f.folder || f.multi ? f.base : `${f.base}.${f.ext}`);
  const metaOf = (f) => {
    const s = fmt(f.mb);
    if (f.multi) return `${f.files.length} items · ${s}`;
    if (f.folder) return "Folder";
    if (f.pages) return `${f.pages} page${f.pages > 1 ? "s" : ""} · ${s}`;
    if (f.dur) return `${f.dur} · ${s}`;
    if (f.dims) return `${s} · ${f.dims[0]} × ${f.dims[1]}`;
    return s;
  };

  const filesEl = $("#files");
  let files = [], uid = 0, fz = 1;
  let sel = new Set();
  const elOf = new Map();
  const byId = (id) => files.find((f) => f.id === id);
  const mqCompact = window.matchMedia("(max-width: 780px)");
  const shown = (f) => !(mqCompact.matches && f.hideNarrow);
  const mk = () => (mqCompact.matches ? "c" : "d");
  const posOf = (f) => f.p[mk()] || f.p.d;
  const menubarH = () => $(".menubar").offsetHeight;
  const appdock = $("#appdock"), adBar = $("#ad-bar");
  /* Where the dock starts, in screen coordinates (nothing floats or lands below it). */
  const floorY = () => { const sr = screen.getBoundingClientRect(); return adBar.offsetParent ? adBar.getBoundingClientRect().top - sr.top - 6 : sr.height; };
  const centerOf = (f) => { const r = filesEl.getBoundingClientRect(), p = posOf(f); return { x: p[0] * r.width, y: p[1] * r.height }; };
  function applyPos(f) {
    const el = elOf.get(f.id), p = posOf(f);
    el.style.setProperty("--fx", `${(p[0] * 100).toFixed(3)}%`); el.style.setProperty("--fy", `${(p[1] * 100).toFixed(3)}%`);
  }
  function layoutAll() { files.forEach((f) => { elOf.get(f.id).classList.toggle("narrow-hide", !shown(f)); applyPos(f); }); }
  /* The visible half-width of an icon: the wider of its picture and its name. */
  const halfW = (el) => Math.max($(".icon", el).offsetWidth, $(".label", el).offsetWidth) / 2 + 3;
  /* Where an icon centre may go: inside the desktop, below the menu bar, above the dock. */
  function bounds(hw, hh) {
    const fr = filesEl.getBoundingClientRect(), sr = screen.getBoundingClientRect();
    const top = mqCompact.matches ? 4 : menubarH() + 6;
    const bottom = mqCompact.matches ? fr.height - 4 : floorY() - (fr.top - sr.top);
    return { minX: hw + 4, maxX: Math.max(hw + 4, fr.width - hw - 4), minY: top + hh, maxY: Math.max(top + hh, bottom - hh) };
  }
  function setCenter(f, x, y, hw, hh) {
    const fr = filesEl.getBoundingClientRect(), b = bounds(hw, hh);
    const cx = clamp(x, b.minX, b.maxX), cy = clamp(y, b.minY, b.maxY);
    f.p[mk()] = [cx / fr.width, cy / fr.height];
    applyPos(f);
    return { x: cx, y: cy };
  }
  const visibleWins = () => $$(".mail, .win").filter((w) => !w.hidden && !w.classList.contains("is-closing"));
  /* Nearest free spot around a file: a spiral in pixels, away from other icons and open windows. */
  function freeSpot(src, hw, hh) {
    const fr = filesEl.getBoundingClientRect(), b = bounds(hw, hh), s = centerOf(src);
    const others = files.filter(shown).map(centerOf);
    const wr = visibleWins().map((w) => w.getBoundingClientRect());
    const clash = (x, y) => {
      let n = others.filter((o) => Math.abs(o.x - x) < hw * 1.9 && Math.abs(o.y - y) < hh * 1.7).length;
      n += wr.filter((r) => x + hw > r.left - fr.left && x - hw < r.right - fr.left && y + hh > r.top - fr.top && y - hh < r.bottom - fr.top).length * 2;
      return n;
    };
    const angles = [0, 35, -35, 70, -70, 110, -110, 150, -150, 180].map((a) => (a * Math.PI) / 180);
    let best = null;
    for (let ring = 0; ring < 16; ring++) {
      const r = hw * 2.05 + ring * hh * 0.45;
      for (const a of angles) {
        const x = clamp(s.x + r * Math.cos(a), b.minX, b.maxX), y = clamp(s.y + r * Math.sin(a), b.minY, b.maxY), n = clash(x, y);
        if (n === 0) return { x, y };
        if (!best || n < best.n) best = { x, y, n };
      }
    }
    return best;
  }
  function makeEl(f) {
    const b = document.createElement("button");
    b.type = "button"; b.className = "file"; b.dataset.id = f.id;
    b.setAttribute("aria-label", `${nameOf(f)}, ${metaOf(f)}. Press Enter to open the wheel.`);
    b.innerHTML = `${iconHTML(f)}<span class="label">${esc(nameOf(f)).replace(/([.\-_])/g, "$1<wbr>")}</span>`;
    elOf.set(f.id, b); filesEl.appendChild(b);
    return b;
  }
  /* A new file appears at once, next to the one it came from. */
  function addFile(f, near) {
    f.p = { d: [0.5, 0.5] };
    files.push(f);
    const el = makeEl(f);
    const c = freeSpot(near, halfW(el), el.offsetHeight / 2);
    const fr = filesEl.getBoundingClientRect();
    f.p[mk()] = [c.x / fr.width, c.y / fr.height];
    if (mk() === "d") f.p.c = f.p.d.slice(); else f.p.d = f.p.c.slice();
    applyPos(f); el.style.zIndex = ++fz;
    el.classList.add("is-pop", "is-new"); setTimeout(() => el.classList.remove("is-pop"), 400); setTimeout(() => el.classList.remove("is-new"), 3600);
    return el;
  }
  /* Selection, like the Finder: click selects, empty desktop deselects, shift or command toggles, a rubber band selects many. */
  function setSel(ids) {
    sel = new Set(ids);
    elOf.forEach((el, k) => el.classList.toggle("is-selected", sel.has(k)));
    attachBtn.disabled = sel.size === 0;
  }
  const selFiles = () => files.filter((f) => sel.has(f.id) && shown(f));
  filesEl.addEventListener("focusin", (e) => { const el = e.target.closest(".file"); if (el && !sel.has(el.dataset.id)) setSel([el.dataset.id]); });
  mqCompact.addEventListener("change", layoutAll);
  /* A set of files held together: its own wheel offers archives and actions. */
  function subjectOf(group) {
    if (group.length < 2) return group[0];
    return { id: "multi", multi: true, files: group, base: `${group.length} items`, ext: "", mb: group.reduce((s, x) => s + x.mb, 0), root: "multi" };
  }

  /* ----- Naming, sizes and results ("name.ext", "name compressed.ext", never overwrite: "name 2.ext") ----- */
  const uniq = (base, ext, folder) => {
    const mk = (n) => { const b = n > 1 ? `${base} ${n}` : base; return folder ? b : `${b}.${ext}`; };
    let n = 1;
    while (files.some((f) => nameOf(f) === mk(n))) n++;
    return n > 1 ? `${base} ${n}` : base;
  };
  function plan(src, it) {
    const folder = it.type === "folder" || it.folder === true;
    const ext = folder ? "" : it.ext || src.ext;
    const baseRaw = src.multi ? "Archive" : it.type === "file" && it.suffix ? `${src.base} ${it.suffix}` : src.base;
    const mb = src.mb * (it.f || 1.04);
    const p = { base: uniq(baseRaw, ext, folder), ext, folder, mb, root: src.root || src.id, tag: it.tag };
    const imgExt = EXT.image.includes(ext);
    if (imgExt && src.dims) {
      let [w, h] = src.dims;
      if (it.scale) { w = Math.round(w * it.scale); h = Math.round(h * it.scale); }
      if (it.fit) { const k = Math.min(1, it.fit / Math.max(w, h)); w = Math.round(w * k); h = Math.round(h * k); }
      p.dims = it.turn ? [h, w] : [w, h];
    }
    if (imgExt || ext === "svg") p.art = it.art || src.art;
    if (ext === "pdf") p.pages = src.pages || 1;
    if ((EXT.video.includes(ext) || EXT.audio.includes(ext)) && src.dur) p.dur = src.dur;
    if (ext === "gif" && it.noDur) delete p.dur;
    p.detail = folder ? "Folder" : it.saving ? `Saved ${Math.round((1 - mb / src.mb) * 100)}% (${fmt(src.mb)} → ${fmt(mb)})` : `${LAB[ext] || ext.toUpperCase()} · ${fmt(mb)}`;
    p.name = folder ? p.base : `${p.base}.${ext}`;
    return p;
  }
  const outText = (src, it) => (it.type === "convert" || it.type === "file" || it.type === "folder" || it.type === "archive" ? plan(src, it).name : it.type === "toast" ? "Copies to clipboard" : it.h || it.t);

  /* ----- Wheel geometry: annular sectors with rounded corners and parallel gaps, 400 x 400 box ----- */
  const C = 200, R_IN = 82, R_OUT = 197, GAP = 6, RC = 11, LABEL_SIZE = 16;
  const f2 = (n) => n.toFixed(2);
  function sectorPath(phi, half) {
    const g = GAP / 2;
    const rot = ([x, y]) => [C + x * Math.cos(phi) - y * Math.sin(phi), C + x * Math.sin(phi) + y * Math.cos(phi)];
    const edge = (sign) => {
      const e = sign * half, u = [Math.cos(e), Math.sin(e)];
      const n = sign < 0 ? [-u[1], u[0]] : [u[1], -u[0]];
      const P = (s, t) => [s * u[0] + t * n[0], s * u[1] + t * n[1]];
      const so = Math.sqrt((R_OUT - RC) ** 2 - (g + RC) ** 2), si = Math.sqrt((R_IN + RC) ** 2 - (g + RC) ** 2);
      const co = P(so, g + RC), ci = P(si, g + RC);
      const ko = R_OUT / (R_OUT - RC), ki = R_IN / (R_IN + RC);
      return { lo: rot(P(so, g)), li: rot(P(si, g)), ao: rot([co[0] * ko, co[1] * ko]), ai: rot([ci[0] * ki, ci[1] * ki]) };
    };
    const a = edge(-1), b = edge(1), p = (q) => `${f2(q[0])} ${f2(q[1])}`;
    return `M${p(a.ao)}A${R_OUT} ${R_OUT} 0 0 1 ${p(b.ao)}A${RC} ${RC} 0 0 1 ${p(b.lo)}L${p(b.li)}A${RC} ${RC} 0 0 1 ${p(b.ai)}` +
      `A${R_IN} ${R_IN} 0 0 0 ${p(a.ai)}A${RC} ${RC} 0 0 1 ${p(a.li)}L${p(a.lo)}A${RC} ${RC} 0 0 1 ${p(a.ao)}Z`;
  }
  const GEOM = {};
  function geom(n) {
    if (GEOM[n]) return GEOM[n];
    const half = Math.PI / n, phis = Array.from({ length: n }, (_, i) => -Math.PI / 2 + (i * 2 * Math.PI) / n);
    const paths = phis.map((p) => sectorPath(p, half));
    const svg = `<svg xmlns="${NS}" viewBox="0 0 400 400">${paths.map((d) => `<path d="${d}"/>`).join("")}</svg>`;
    return (GEOM[n] = { phis, paths, ring: `url("data:image/svg+xml,${encodeURIComponent(svg)}")` });
  }
  const svgEl = (tag, attrs = {}) => { const el = document.createElementNS(NS, tag); for (const k in attrs) el.setAttribute(k, attrs[k]); return el; };

  /* ----- The wheel ----- */
  const wbox = $("#wbox"), wheelEl = $("#wheel"), layer = $("#wedges"), wheelSvg = $("#wheel-svg");
  const coreEl = $("#core"), coreFit = $("#core-fit"), coreTitle = $("#core-title"), coreSub = $("#core-sub");
  const wcIcon = $("#wc-icon"), wcName = $("#wc-name"), wcMeta = $("#wc-meta"), wcLabel = $("#wc-label"), wcRes = $("#wc-res"), wcOut = $("#wc-out");
  const modesEl = $("#modes"), modeBtns = $$(".mode"), tip = $("#wheel-tip");
  const MODE_TITLE = { convert: "Convert", tools: "Tools", actions: "Actions" };
  const W = { open: false, file: null, mode: "convert", page: 0, items: [], active: -1, busy: false, via: "pointer", moreTimer: 0, moreLock: false };
  let wedges = [];

  /* Centre label: the circle never changes size; the text shrinks until it sits inside it. */
  function fitCore() {
    coreEl.style.setProperty("--core-scale", "1");
    const d = coreEl.clientWidth;
    if (!d) return;
    const fits = () => coreFit.scrollHeight <= d * 0.58 && coreTitle.scrollWidth <= coreTitle.clientWidth + 1 && coreSub.scrollWidth <= coreSub.clientWidth + 1;
    let scale = 1;
    while (!fits() && scale > 0.5) { scale = Math.round((scale - 0.04) * 100) / 100; coreEl.style.setProperty("--core-scale", String(scale)); }
  }
  function setCore(title, sub) { coreTitle.textContent = title; coreSub.textContent = sub; fitCore(); }
  if ("ResizeObserver" in window) new ResizeObserver(() => fitCore()).observe(coreEl);

  function showIdle() {
    setCore(MODE_TITLE[W.mode], "Drop on a wedge");
    wcLabel.textContent = W.mode === "actions" ? "Does" : "Saves as";
    wcRes.textContent = W.mode === "actions" ? "Pick an action" : "Pick a wedge";
    wcOut.classList.add("is-idle"); wcOut.classList.remove("is-done");
  }
  function setActive(i) {
    if (i === W.active) return;
    clearTimeout(W.moreTimer);
    if (W.active >= 0 && wedges[W.active]) wedges[W.active].classList.remove("on");
    W.active = i;
    const it = W.items[i];
    if (!it || W.busy) { if (!W.busy) showIdle(); return; }
    wedges[i].classList.add("on"); tip.classList.add("is-quiet");
    setCore(it.t, it.h || "");
    if (it.type === "more") { wcLabel.textContent = "Shows"; wcRes.textContent = "More choices"; }
    else { wcLabel.textContent = it.type === "convert" || it.type === "file" || it.type === "folder" || it.type === "archive" ? "Saves as" : "Does"; wcRes.textContent = outText(W.file, it); }
    wcOut.classList.remove("is-idle", "is-done");
    if (it.type === "more") { if (W.moreLock) return; W.moreTimer = setTimeout(() => flipPage(), 500); } else W.moreLock = false;
  }
  function flipPage() {
    W.page += 1; W.moreLock = true;
    buildWheel(true);
  }

  function buildWheel(animate) {
    const f = W.file;
    // pills: a wheel with nothing on it is disabled
    modeBtns.forEach((b) => { b.disabled = listFor(f, b.dataset.mode).length === 0; });
    if (modeBtns.find((b) => b.dataset.mode === W.mode).disabled) W.mode = (modeBtns.find((b) => !b.disabled) || modeBtns[0]).dataset.mode;
    modeBtns.forEach((b) => b.setAttribute("aria-pressed", String(b.dataset.mode === W.mode)));
    $$(".ck").forEach((k) => k.classList.toggle("is-current", k.dataset.mode === W.mode));

    const list = listFor(f, W.mode);
    let items = list;
    if (list.length > 8) {
      const per = 7, pages = Math.ceil(list.length / per);
      W.page %= pages;
      items = list.slice(W.page * per, W.page * per + per);
      items.push({ type: "more", id: "more", l: ["More"], t: "More", h: `Page ${((W.page + 1) % pages) + 1} of ${pages}` });
    } else W.page = 0;
    W.items = items; W.active = -1;
    const g = geom(items.length), n = items.length;
    wheelEl.style.setProperty("--ring", g.ring);
    wheelSvg.setAttribute("aria-label", `${MODE_TITLE[W.mode]} wheel for ${nameOf(f)}`);
    layer.replaceChildren(); wedges = [];
    items.forEach((it, i) => {
      const phi = g.phis[i], rm2 = (R_IN + R_OUT) / 2 + 1;
      const el = svgEl("g", { class: "wedge", role: "button", tabindex: "-1", "aria-label": `${it.t}${it.h ? ", " + it.h : ""}` });
      el.dataset.i = i;
      el.append(svgEl("path", { class: "w-base", d: g.paths[i] }), svgEl("path", { class: "w-hl", d: g.paths[i] }));
      // One size for every label on every wheel, whatever its length (two-line labels use the same size).
      const size = LABEL_SIZE;
      ["w-t", "w-t on"].forEach((cls) => {
        const x = f2(C + rm2 * Math.cos(phi)), t = svgEl("text", { class: cls, x, y: f2(C + rm2 * Math.sin(phi)), "font-size": size });
        it.l.forEach((line, k) => {
          const s = svgEl("tspan", { x, dy: k === 0 ? `${(0.35 - (it.l.length - 1) * 0.55).toFixed(2)}em` : "1.1em" });
          s.textContent = line; t.appendChild(s);
        });
        el.appendChild(t);
      });
      layer.appendChild(el); wedges.push(el);
    });
    wedges[0].setAttribute("tabindex", "0");
    showIdle();
    wcIcon.innerHTML = iconHTML(f); wcName.textContent = nameOf(f); wcMeta.textContent = metaOf(f);
    if (animate && !rm()) wedges.forEach((el, i) => el.animate([{ opacity: 0, transform: "scale(.84)" }, { opacity: 1, transform: "scale(1)" }], { duration: 420, delay: i * 26, easing: "cubic-bezier(.2,.9,.25,1)", fill: "backwards" }));
  }

  function placeBox(cx, cy) {
    const sr = screen.getBoundingClientRect(), wp = wheelEl.offsetWidth, r = wp / 2, top = $(".menubar").offsetHeight + 8;
    const half = Math.max(wp, $("#wcard").offsetWidth) / 2, extras = $(".wbox-in").offsetHeight - wp, floor = Math.min(sr.height, floorY()) - 6 - (dock.classList.contains("is-on") ? dock.offsetHeight + 18 : 0);
    cx = clamp(cx, half + 4, sr.width - half - 4);
    // The card and the pills sit under the ring; near the bottom of the screen they flip above it so the ring stays under the pointer.
    const flip = cy + r + extras > floor - 4 && cy - r - extras > top;
    cy = flip ? clamp(cy, top + extras + r, floor - r - 4) : clamp(cy, top + r, floor - extras - r - 4);
    wbox.classList.toggle("flip", flip);
    wbox.style.setProperty("--x", `${cx - wp / 2}px`); wbox.style.setProperty("--y", `${cy - r}px`);
  }
  function openWheel(point, via, file, mode = "convert") {
    clearTimeout(closeT);
    W.file = file; W.via = via; W.busy = false; W.page = 0; W.moreLock = false;
    wheelEl.classList.remove("is-busy"); wbox.classList.remove("is-quick");
    W.mode = mode; tip.classList.remove("is-quiet");
    buildWheel(false);
    const inner = $(".wbox-in");
    inner.style.transition = "none"; placeBox(point.x, point.y); void inner.offsetWidth; inner.style.transition = "";
    W.open = true; wbox.classList.add("is-open"); screen.classList.add("wheel-open");
    if (!rm()) wedges.forEach((el, i) => el.animate([{ opacity: 0, transform: "scale(.84)" }, { opacity: 1, transform: "scale(1)" }], { duration: 420, delay: i * 22, easing: "cubic-bezier(.2,.9,.25,1)", fill: "backwards" }));
    if (via === "key") wedges[0].focus({ preventScroll: true });
  }
  let closeT = 0;
  function closeWheel(restoreFocus, quick) {
    if (!W.open) return;
    W.open = false; clearTimeout(W.moreTimer);
    if (quick) { wbox.classList.add("is-quick"); setTimeout(() => wbox.classList.remove("is-quick"), 220); }
    wbox.classList.remove("is-open"); screen.classList.remove("wheel-open");
    const ff = W.file && (W.file.multi ? W.file.files[0] : W.file); if (restoreFocus && ff && elOf.get(ff.id)) elOf.get(ff.id).focus({ preventScroll: true });
    closeT = setTimeout(() => { if (!W.open) { if (W.active >= 0 && wedges[W.active]) wedges[W.active].classList.remove("on"); W.active = -1; } }, 400);
  }
  function setMode(m) {
    const btn = modeBtns.find((b) => b.dataset.mode === m);
    if (!W.open || W.busy || !btn || btn.disabled || W.mode === m) return;
    W.mode = m; W.page = 0; W.moreLock = false;
    buildWheel(true);
    if (D && D.active) { const w = hit(D.px, D.py); setActive(w); }
  }
  modeBtns.forEach((b) => b.addEventListener("click", () => { if (D && D.active) return; setMode(b.dataset.mode); if (W.via === "key") wedges[0] && wedges[0].focus({ preventScroll: true }); }));

  /* Pointer geometry (client coordinates) */
  function hit(x, y) {
    const r = wheelEl.getBoundingClientRect(), s = r.width / 400;
    const dx = x - (r.left + r.width / 2), dy = y - (r.top + r.height / 2), d = Math.hypot(dx, dy), n = W.items.length;
    if (!n || d < R_IN * s * 0.88 || d > (R_OUT + 10) * s) return -1;
    let a = Math.atan2(dy, dx) + Math.PI / 2;
    a = (((a + Math.PI / n) % (2 * Math.PI)) + 2 * Math.PI) % (2 * Math.PI);
    return Math.floor(a / ((2 * Math.PI) / n)) % n;
  }
  const farFromWheel = (x, y, k = 1.22) => { const r = wheelEl.getBoundingClientRect(); return Math.hypot(x - (r.left + r.width / 2), y - (r.top + r.height / 2)) > (r.width / 2) * k; };
  const inRect = (r, x, y) => x >= r.left && x <= r.right && y >= r.top && y <= r.bottom;

  /* Mouse hover and click when the wheel is open without a drag (keyboard or tap) */
  layer.addEventListener("pointerover", (e) => { if (D) return; const w = e.target.closest(".wedge"); if (w && !W.busy) setActive(+w.dataset.i); });
  layer.addEventListener("pointerleave", () => { if (!D && !W.busy) setActive(-1); });
  layer.addEventListener("focusin", (e) => { const w = e.target.closest(".wedge"); if (w && !D && !W.busy) setActive(+w.dataset.i); });
  layer.addEventListener("click", (e) => { const w = e.target.closest(".wedge"); if (w) runItem(W.items[+w.dataset.i], { via: "click" }); });
  layer.addEventListener("keydown", (e) => {
    const w = e.target.closest(".wedge"); if (!w) return;
    const i = +w.dataset.i, n = wedges.length;
    const d = { ArrowRight: 1, ArrowDown: 1, ArrowLeft: -1, ArrowUp: -1 }[e.key];
    const go = (j) => { wedges.forEach((x) => x.setAttribute("tabindex", "-1")); wedges[j].setAttribute("tabindex", "0"); wedges[j].focus({ preventScroll: true }); };
    if (d) { e.preventDefault(); go((i + d + n) % n); }
    else if (e.key === "Home") { e.preventDefault(); go(0); } else if (e.key === "End") { e.preventDefault(); go(n - 1); }
    else if (e.key === "Enter" || e.key === " ") { e.preventDefault(); runItem(W.items[i], { via: "key" }); }
  });

  /* ----- Dragging: move icons, rubber-band, convert, attach, trash ----- */
  let D = null, suppressClick = false, tap = null, fz2 = 1;
  const mailEl = $("#mail"), dropEl = $("#m-drop"), trashEl = $("#dk-trash"), overlay = $("#overlay"), bandEl = $("#band");
  const sLocal = (e) => { const r = screen.getBoundingClientRect(); return { x: e.clientX - r.left, y: e.clientY - r.top }; };
  const trashRect = () => trashEl.getBoundingClientRect();
  const nearDock = (x, y) => { if (!adBar.offsetParent) return false; const r = adBar.getBoundingClientRect(); return x >= r.left - 24 && x <= r.right + 24 && y >= r.top - 44 && y <= r.bottom + 12; };
  const overDock = (x, y) => { if (!adBar.offsetParent) return false; return inRect(adBar.getBoundingClientRect(), x, y); };
  const overTrash = (x, y) => { if (!adBar.offsetParent) return false; const r = trashRect(); return x >= r.left - 8 && x <= r.right + 8 && y >= r.top - 12 && y <= r.bottom + 8; };
  const overWindow = (x, y) => visibleWins().some((w) => inRect(w.getBoundingClientRect(), x, y));
  const overAttach = (x, y) => !mailEl.hidden && !mailEl.classList.contains("is-closing") && !mailEl.classList.contains("is-min") && inRect(dropEl.getBoundingClientRect(), x, y);

  filesEl.addEventListener("pointerdown", (e) => {
    const el = e.target.closest(".file");
    if (!el || e.button > 0 || W.busy || D) return;
    const f = byId(el.dataset.id);
    const mod = e.shiftKey || e.metaKey;
    if (mod) { const ids = new Set(sel); if (ids.has(f.id)) ids.delete(f.id); else ids.add(f.id); setSel([...ids]); if (!sel.has(f.id)) return; }
    else if (!sel.has(f.id)) setSel([f.id]);
    if (W.open) closeWheel(false);
    let group = selFiles(); if (!group.some((g) => g.id === f.id)) group = [f];
    el.style.zIndex = ++fz;
    try { el.setPointerCapture(e.pointerId); } catch { /* not capturable */ }
    D = { prim: f, el, group, id: e.pointerId, sx: e.clientX, sy: e.clientY, px: e.clientX, py: e.clientY, active: false, dismissed: false, tapSel: !mod && group.length > 1 };
  });
  filesEl.addEventListener("pointermove", (e) => {
    if (!D || e.pointerId !== D.id) return;
    D.px = e.clientX; D.py = e.clientY;
    if (!D.active) {
      if (Math.hypot(e.clientX - D.sx, e.clientY - D.sy) < 8) return;
      startDrag();
    }
    const dx = e.clientX - D.sx, dy = e.clientY - D.sy;
    D.items.forEach((it) => { it.ghost.style.transform = `translate3d(${it.ox + dx}px,${it.oy + dy}px,0)`; });
    updateTargets(e.clientX, e.clientY);
  });
  filesEl.addEventListener("pointerup", (e) => {
    if (!D || e.pointerId !== D.id) return;
    if (!D.active) { if (D.tapSel) setSel([D.prim.id]); D = null; return; }
    endDrag(e.clientX, e.clientY, false);
  });
  filesEl.addEventListener("pointercancel", (e) => { if (D && e.pointerId === D.id) { if (D.active) endDrag(e.clientX, e.clientY, true); else D = null; } });
  filesEl.addEventListener("lostpointercapture", (e) => { if (D && e.pointerId === D.id && D.active && !D.ending) endDrag(D.px, D.py, true); });
  filesEl.addEventListener("click", (e) => {
    const el = e.target.closest(".file"); if (!el) return;
    if (suppressClick) { suppressClick = false; return; }
    if (e.detail === 0 && !W.busy) { // keyboard activation: open the wheel centred on the file (or on the selected group)
      const f = byId(el.dataset.id), sr = screen.getBoundingClientRect(), r = el.getBoundingClientRect();
      const group = sel.has(f.id) && selFiles().length > 1 ? selFiles() : [f];
      const p = { x: r.left - sr.left + r.width / 2, y: r.top - sr.top + r.height / 2 };
      openWheel(p, "key", subjectOf(group));
      lastPoint = p;
    }
  });
  let lastPoint = { x: 200, y: 200 };
  screen.addEventListener("contextmenu", (e) => e.preventDefault());

  function startDrag() {
    D.active = true; D.keyed = false;
    const sr = screen.getBoundingClientRect();
    D.items = D.group.map((f) => {
      const el = elOf.get(f.id), r = el.getBoundingClientRect(), c = centerOf(f);
      const ghost = el.cloneNode(true);
      ghost.className = "file ghost"; ghost.removeAttribute("data-id"); ghost.removeAttribute("aria-label"); ghost.tabIndex = -1; ghost.setAttribute("aria-hidden", "true");
      ghost.style.width = `${r.width}px`; ghost.style.zIndex = 12;
      ghost.style.transform = `translate3d(${r.left - sr.left}px,${r.top - sr.top}px,0)`;
      overlay.appendChild(ghost); el.classList.add("is-dragging");
      return { f, el, ghost, ox: r.left - sr.left, oy: r.top - sr.top, w: r.width, h: r.height, hw: halfW(el), cx0: c.x, cy0: c.y };
    });
    D.ghost = D.items.find((it) => it.f === D.prim).ghost; D.w = D.items.find((it) => it.f === D.prim).w;
    D.f = subjectOf(D.group);
    screen.classList.add("is-dragging");
    const p = { x: D.px - sr.left, y: D.py - sr.top };
    lastPoint = p;
    showCoach("key", p);
    say("Hold the file, then tap Shift, Command or Control to choose a wheel.");
  }
  function updateTargets(x, y) {
    lastPoint = { x: x - screen.getBoundingClientRect().left, y: y - screen.getBoundingClientRect().top };
    if (W.open && !W.busy) {
      if (!farFromWheel(x, y, 0.98)) D.armed = true;
      if (D.armed && farFromWheel(x, y)) { D.dismissed = true; closeWheel(false); setActive(-1); }
      else setActive(hit(x, y));
    }
    const attachOver = !W.open && overAttach(x, y), trashOver = !W.open && overTrash(x, y);
    mailEl.classList.toggle("is-target", attachOver);
    trashEl.classList.toggle("is-target", trashOver);
    magnify(!W.open && nearDock(x, y) ? x : null, trashOver);
    coach.classList.toggle("is-away", attachOver || trashOver);
    if (coachMode === "follow") placeCoach(lastPoint);
  }
  function endDrag(x, y, cancelled) {
    const d = D; if (!d.active) { D = null; return; }
    d.ending = true; D = null; suppressClick = true; setTimeout(() => { suppressClick = false; }, 60);
    screen.classList.remove("is-dragging"); mailEl.classList.remove("is-target"); trashEl.classList.remove("is-target"); magnify(null);
    hideCoach(); dock.classList.remove("is-on"); screen.classList.remove("has-dock");
    try { d.el.releasePointerCapture(d.id); } catch { /* already released */ }
    const wasOpen = W.open;
    const idx = !cancelled && wasOpen && !W.busy ? hit(x, y) : -1;
    const sr = screen.getBoundingClientRect();
    if (!cancelled && idx >= 0 && W.items[idx]) {
      if (W.items[idx].type === "more") { snapBack(d); flipPage(); return; }
      fadeGhosts(d);
      runItem(W.items[idx], { via: "drop", point: { x: x - sr.left, y: y - sr.top } });
      return;
    }
    // Everything below happens on the bare desktop: the wheel is closed, nothing converts.
    const insideWheel = wasOpen && !farFromWheel(x, y, 1);
    if (wasOpen) { closeWheel(false); setActive(-1); }
    if (cancelled || insideWheel) { snapBack(d); return; }
    if (overAttach(x, y)) { d.items.forEach((it) => it.el.classList.remove("is-dragging")); flyGhosts(d, dropEl.getBoundingClientRect()); d.group.forEach(attach); return; }
    if (overTrash(x, y)) { flyGhosts(d, trashRect()); puff(trashRect()); trashFiles(d.group); return; }
    if (overDock(x, y) || overWindow(x, y)) { snapBack(d); return; }
    dropMove(d, x, y);
    if (!d.keyed && !learned) { const c = centerOf(d.prim), fr = filesEl.getBoundingClientRect(), s = screen.getBoundingClientRect(); tooSoon({ x: c.x + fr.left - s.left, y: c.y + fr.top - s.top }); }
  }
  /* Letting go on empty desktop: the icons stay where they were dropped (clamped), with a small spring. */
  function dropMove(d, x, y) {
    const dx = x - d.sx, dy = y - d.sy, fr = filesEl.getBoundingClientRect(), sr = screen.getBoundingClientRect(), offx = fr.left - sr.left, offy = fr.top - sr.top;
    d.items.forEach((it) => {
      const c = setCenter(it.f, it.cx0 + dx, it.cy0 + dy, it.hw, it.h / 2);
      it.el.style.zIndex = ++fz;
      const tx = c.x - it.w / 2 + offx, ty = c.y - it.h / 2 + offy, cx = it.ox + dx, cy = it.oy + dy;
      const done = () => { it.ghost.remove(); it.el.classList.remove("is-dragging"); it.el.classList.add("is-settle"); setTimeout(() => it.el.classList.remove("is-settle"), 260); };
      if (rm() || Math.hypot(tx - cx, ty - cy) < 2) { done(); return; }
      const a = it.ghost.animate([{ transform: it.ghost.style.transform }, { transform: `translate3d(${tx}px,${ty}px,0)` }], { duration: 220, easing: "cubic-bezier(.25,1.2,.35,1)", fill: "forwards" });
      a.onfinish = done;
    });
    say(d.group.length > 1 ? `Moved ${d.group.length} items` : `Moved ${nameOf(d.prim)}`);
  }
  function snapBack(d) {
    d.items.forEach((it) => {
      const done = () => { it.ghost.remove(); it.el.classList.remove("is-dragging"); };
      if (rm()) { done(); return; }
      const a = it.ghost.animate([{ transform: it.ghost.style.transform }, { transform: `translate3d(${it.ox}px,${it.oy}px,0)` }], { duration: 460, easing: "cubic-bezier(.25,1.18,.35,1)", fill: "forwards" });
      a.onfinish = done;
    });
  }
  /* Dropped on a wedge: the ghost just gets out of the way, nothing waits. */
  function fadeGhosts(d) {
    d.items.forEach((it) => {
      it.el.classList.remove("is-dragging");
      if (rm()) { it.ghost.remove(); return; }
      it.ghost.animate([{ opacity: 1, scale: 1 }, { opacity: 0, scale: 0.86 }], { duration: 110, easing: "ease-out", fill: "forwards" }).onfinish = () => it.ghost.remove();
    });
  }
  function flyGhosts(d, rect) {
    const sr = screen.getBoundingClientRect();
    d.items.forEach((it) => {
      if (rm()) { it.ghost.remove(); return; }
      const tx = rect.left - sr.left + rect.width / 2 - it.w / 2, ty = rect.top - sr.top + rect.height / 2 - it.h / 2;
      it.ghost.animate([{ transform: it.ghost.style.transform, opacity: 1 }, { transform: `translate3d(${tx}px,${ty}px,0) scale(.25)`, opacity: 0 }], { duration: 240, easing: "cubic-bezier(.4,0,.6,1)", fill: "forwards" }).onfinish = () => it.ghost.remove();
    });
  }
  function puff(rect) {
    if (rm()) return;
    const sr = screen.getBoundingClientRect(), box = document.createElement("div");
    box.className = "puff"; box.style.cssText = `position:absolute;left:${rect.left - sr.left + rect.width / 2}px;top:${rect.top - sr.top + rect.height / 2}px;z-index:13;pointer-events:none`;
    for (let i = 0; i < 9; i++) {
      const a = (i / 9) * Math.PI * 2, dot = document.createElement("i");
      dot.animate([{ transform: "translate(-50%,-50%) scale(.7)", opacity: 0.95 }, { transform: `translate(${Math.cos(a) * 38 - 4}px,${Math.sin(a) * 30 - 18}px) scale(.1)`, opacity: 0 }], { duration: 560, delay: 120, easing: "cubic-bezier(.2,.7,.3,1)", fill: "both" });
      box.appendChild(dot);
    }
    overlay.appendChild(box); setTimeout(() => box.remove(), 800);
  }
  function trashFiles(group) {
    group.forEach((f) => {
      const el = elOf.get(f.id); if (el) el.remove();
      elOf.delete(f.id); files = files.filter((x) => x !== f); sel.delete(f.id);
      $$(`[data-fid="${f.id}"]`).forEach((t) => t.remove());
    });
    setSel([...sel]);
    toast(group.length > 1 ? `${group.length} items moved to the Trash` : `${nameOf(group[0])} moved to the Trash`);
    refreshScenario();
  }

  /* Rubber band: drag on the empty desktop to select several icons. */
  let B = null;
  screen.addEventListener("pointerdown", (e) => {
    if (e.button > 0 || D || e.pointerType === "touch") return;
    if (e.target.closest(".file, .mail, .win, .rcard, .wbox, .float-tile, .coach, .dock, .appdock, .menubar, .toast, .wins > *")) return;
    if (mqCompact.matches && !e.target.closest(".files")) return;
    B = { id: e.pointerId, x0: e.clientX, y0: e.clientY, base: e.shiftKey || e.metaKey ? new Set(sel) : new Set(), moved: false };
    if (!B.base.size) setSel([]);
    try { screen.setPointerCapture(e.pointerId); } catch { /* not capturable */ }
  });
  screen.addEventListener("pointermove", (e) => {
    if (!B || e.pointerId !== B.id) return;
    if (!B.moved) { if (Math.hypot(e.clientX - B.x0, e.clientY - B.y0) < 4) return; B.moved = true; bandEl.hidden = false; }
    const sr = screen.getBoundingClientRect();
    const x1 = Math.min(B.x0, e.clientX), y1 = Math.min(B.y0, e.clientY), x2 = Math.max(B.x0, e.clientX), y2 = Math.max(B.y0, e.clientY);
    bandEl.style.transform = `translate3d(${x1 - sr.left}px,${y1 - sr.top}px,0)`; bandEl.style.width = `${x2 - x1}px`; bandEl.style.height = `${y2 - y1}px`;
    const ids = new Set(B.base);
    files.filter(shown).forEach((f) => { const r = elOf.get(f.id).getBoundingClientRect(); if (r.right > x1 && r.left < x2 && r.bottom > y1 && r.top < y2) ids.add(f.id); });
    setSel([...ids]);
  });
  const endBand = (e) => { if (!B || e.pointerId !== B.id) return; B = null; bandEl.hidden = true; try { screen.releasePointerCapture(e.pointerId); } catch { /* released */ } };
  screen.addEventListener("pointerup", endBand); screen.addEventListener("pointercancel", endBand);

  /* ----- Live coach: "drag, tap a key, drop" ----- */
  const coach = $("#coach"), dock = $("#dock"), coTitle = $("#co-title"), coSub = $("#co-sub"), coSteps = $$("#co-steps li");
  const mqCoarse = window.matchMedia("(pointer: coarse)");
  const coarse = () => mqCoarse.matches || (navigator.maxTouchPoints > 1 && mqCompact.matches);
  const KEYS = { Shift: "convert", Meta: "tools", Control: "actions" };
  let learned = false, coachMode = "off", coachT = 0, coSubT = 0;
  const coSubText = () => "Keep holding the file";
  function showCoach(stage, p) {
    clearTimeout(coachT); clearTimeout(coSubT);
    coach.dataset.stage = stage;
    coach.classList.toggle("is-compact", learned && stage === "key");
    coach.classList.toggle("is-coarse", coarse());
    coTitle.textContent = stage === "late" ? "You let go too soon" : "Now tap a key";
    coSub.textContent = stage === "late" ? "Hold the file, then tap ⇧, ⌘ or ⌃." : coSubText();
    coSteps.forEach((li, i) => { li.classList.toggle("is-done", i === 0); li.classList.toggle("is-now", i === 1); });
    $$(".ck.is-hit, .ck.is-current").forEach((k) => k.classList.remove("is-hit", "is-current"));
    coachMode = stage === "key" ? "follow" : "still";
    coach.classList.remove("is-away"); placeCoach(p);
    coach.classList.add("is-on");
    if (stage === "key" && coarse()) { dock.classList.toggle("is-compact", learned); dock.classList.add("is-on"); screen.classList.add("has-dock"); }
  }
  function hideCoach() { coachMode = "off"; coach.classList.remove("is-on"); }
  function placeCoach(p) {
    const sr = screen.getBoundingClientRect(), w = coach.offsetWidth, h = coach.offsetHeight, top = menubarH() + 8;
    const gap = (D && D.w ? D.w / 2 : 44) + 14, bottom = Math.min(sr.height - 8, floorY()) - (dock.classList.contains("is-on") ? dock.offsetHeight + 10 : 0);
    let x = p.x + gap, y = p.y - h / 2;
    if (x + w > sr.width - 8) x = p.x - gap - w;
    if (x < 8) { // no room beside the file: sit above or below it
      x = clamp(p.x - w / 2, 8, sr.width - w - 8);
      y = p.y - gap - h < top ? p.y + gap : p.y - gap - h;
    }
    coach.style.setProperty("--x", `${clamp(x, 8, sr.width - w - 8)}px`);
    coach.style.setProperty("--y", `${clamp(y, top, bottom - h)}px`);
  }
  function tooSoon(p) {
    showCoach("late", p);
    say("You let go too soon. Hold the file, then tap Shift, Command or Control.");
    coachT = setTimeout(hideCoach, 3200);
  }
  const flashKey = (mode) => {
    $$(`.ck[data-mode="${mode}"]`).forEach((k) => { k.classList.add("is-hit"); setTimeout(() => k.classList.remove("is-hit"), 750); });
  };
  function coachNote(msg) {
    clearTimeout(coSubT); coSub.textContent = msg; say(msg);
    coSubT = setTimeout(() => { coSub.textContent = coSubText(); }, 2200);
  }
  /* A key (real, or pressed on screen with a second finger) while a file is held opens that wheel at the pointer. */
  function pressKey(mode) {
    if (!D || !D.active || W.busy) return;
    flashKey(mode);
    if (W.open) { setMode(mode); return; }
    const list = listFor(D.f, mode);
    if (!list.length) { coachNote(`${D.f.multi ? "Several files" : (LAB[D.f.ext] || D.f.ext.toUpperCase()) + " files"} have no ${MODE_TITLE[mode]} wheel`); return; }
    const r = screen.getBoundingClientRect();
    D.keyed = true; D.dismissed = false; D.armed = false;
    openWheel({ x: D.px - r.left, y: D.py - r.top }, "pointer", D.f, mode);
    coachMode = "off"; setTimeout(() => { if (D && D.keyed) hideCoach(); }, 380);
    say(`${MODE_TITLE[mode]} wheel. Move onto a wedge, then let go.`);
  }
  $$(".ck").forEach((k) => {
    k.addEventListener("pointerdown", (e) => { e.stopPropagation(); e.preventDefault(); pressKey(k.dataset.mode); });
    k.addEventListener("click", (e) => e.stopPropagation());
  });
  [coach, dock].forEach((el) => el.addEventListener("pointerdown", (e) => e.stopPropagation()));
  const demoEl = $(".demo"); let overDemo = false;
  demoEl.addEventListener("pointerenter", () => { overDemo = true; });
  demoEl.addEventListener("pointerleave", () => { overDemo = false; });
  let nudgeAt = 0;
  function nudge() {
    if (performance.now() - nudgeAt < 1600) return;
    nudgeAt = performance.now();
    $$(".sc-key").forEach((k) => { k.classList.remove("nudge"); void k.offsetWidth; k.classList.add("nudge"); });
    toast("Start dragging a file first");
  }
  document.addEventListener("contextmenu", (e) => { if (D && D.active) e.preventDefault(); }, true);
  document.addEventListener("keydown", (e) => {
    if (e.key === "Escape") {
      if (D && D.active) { endDrag(D.px, D.py, true); return; }
      if (W.open && !W.busy) { closeWheel(true); return; }
      closeTopWindow(); return;
    }
    if (e.repeat) return;
    const mode = KEYS[e.key];
    const combo = (e.key !== "Shift" && e.shiftKey) || (e.key !== "Meta" && e.metaKey) || (e.key !== "Control" && e.ctrlKey) || e.altKey;
    if (!mode || combo) { tap = null; return; }
    if (D && D.active) { pressKey(mode); tap = null; return; }
    tap = e.key;
  }, true);
  document.addEventListener("keyup", (e) => {
    const mode = KEYS[e.key];
    if (tap && e.key === tap && mode) {
      if (W.open && !W.busy) setMode(mode);                                   // keyboard-opened wheel: tap to switch
      else if (!W.open && (overDemo || demoEl.contains(document.activeElement))) nudge(); // no file in hand yet
    }
    tap = null;
  }, true);

  /* ----- Running a wedge: the result is there immediately ----- */
  const toastEl = $("#toast"); let toastT = 0;
  function toast(msg) {
    clearTimeout(toastT); toastEl.hidden = false; toastEl.textContent = msg;
    toastEl.style.animation = "none"; void toastEl.offsetWidth; toastEl.style.animation = "";
    toastT = setTimeout(() => { toastEl.hidden = true; }, 2800); say(msg);
  }
  function runItem(it, ctx) {
    if (!it || W.busy) return;
    if (it.type === "more") { flipPage(); return; }
    const file = W.file, idx = W.items.indexOf(it);
    clearTimeout(W.moreTimer);
    if (W.active !== idx) setActive(idx);
    W.busy = true; wheelEl.classList.add("is-busy");
    const point = ctx.point || lastPoint;
    closeWheel(ctx.via === "key", true);
    setTimeout(() => { W.busy = false; wheelEl.classList.remove("is-busy"); }, 160);
    if (it.type === "action") return perform(it, file, point);
    if (it.type === "toast") { toast(typeof it.msg === "function" ? it.msg(file) : it.msg); return; }
    const p = plan(file, it);
    const nf = { id: "f" + ++uid, base: p.base, ext: p.ext, folder: p.folder, mb: p.mb, dims: p.dims, pages: p.pages, dur: p.dur, art: p.art, root: p.root, tag: p.tag, detail: p.detail, created: true, srcId: file.id };
    addFile(nf, file.multi ? file.files[0] : file);
    learned = true;
    say(`Saved ${nameOf(nf)} next to ${nameOf(file.multi ? file.files[0] : file)}`);
    showCard(nf, point);
    refreshScenario();
  }

  /* Result card, like the app's: thumbnail, name, detail, and a Show button */
  const rcard = $("#rcard"); let rcT = 0;
  function showCard(f, point) {
    clearTimeout(rcT);
    rcard.innerHTML = `<span class="rc-icon">${iconHTML(f)}</span><span class="rc-t"><span class="rc-n">${esc(nameOf(f))}</span><span class="rc-d">${esc(f.detail)}</span></span><button class="rc-show" type="button">Show</button>`;
    const sr = screen.getBoundingClientRect();
    rcard.hidden = false;
    const w = rcard.offsetWidth, h = rcard.offsetHeight;
    rcard.style.setProperty("--x", `${clamp(point.x - w / 2, 8, sr.width - w - 8)}px`);
    rcard.style.setProperty("--y", `${clamp(point.y + 28, menubarH() + 6, Math.min(sr.height, floorY()) - h - 6)}px`);
    rcard.classList.remove("rc-in"); void rcard.offsetWidth; rcard.classList.add("rc-in");
    $(".rc-show", rcard).addEventListener("click", () => { hideCard(); openFinder([f]); });
    const arm = (ms) => { clearTimeout(rcT); rcT = setTimeout(hideCard, ms); };
    arm(5200);
    rcard.onpointerenter = () => clearTimeout(rcT); rcard.onpointerleave = () => arm(2200);
    rcard.onfocusin = () => clearTimeout(rcT); rcard.onfocusout = () => arm(2200);
  }
  const hideCard = () => { rcard.hidden = true; };

  /* ----- Windows: draggable by the title bar, raised on click, traffic lights ----- */
  const wins = { mail: mailEl, finder: $("#win-finder"), term: $("#win-term"), air: $("#win-air") };
  const winList = Object.values(wins);
  let zTop = 10, winTimers = [];
  const isOpen = (w) => !w.hidden && !w.classList.contains("is-closing");
  function syncDock() {
    $$(".dk-i").forEach((b) => { const w = { mail: wins.mail, finder: wins.finder, terminal: wins.term }[b.dataset.app]; b.classList.toggle("is-open", !!w && isOpen(w)); });
  }
  function front(w) {
    if (mqCompact.matches) return;
    winList.forEach((x) => x.classList.remove("is-front"));
    w.style.zIndex = ++zTop; w.classList.add("is-front");
  }
  function closeWindow(w) {
    if (w.hidden || w.classList.contains("is-closing")) return;
    if (w === wins.mail && mqCompact.matches) return;
    if (w === wins.air) winTimers.forEach(clearTimeout);
    mailEl.classList.remove("is-target");
    if (rm()) { w.hidden = true; syncDock(); return; }
    w.classList.add("is-closing");
    setTimeout(() => { w.hidden = true; w.classList.remove("is-closing"); syncDock(); }, 190);
    syncDock();
  }
  function openWindow(w) {
    w.hidden = false; w.classList.remove("is-closing", "is-min");
    w.style.animation = "none"; void w.offsetWidth; w.style.animation = "";
    front(w); syncDock();
  }
  function closeTopWindow() {
    const open = [wins.finder, wins.term, wins.air].filter(isOpen).sort((a, b) => (+b.style.zIndex || 0) - (+a.style.zIndex || 0));
    if (open[0]) closeWindow(open[0]);
  }
  function closeWins() { winTimers.forEach(clearTimeout); winTimers = []; [wins.finder, wins.term, wins.air].forEach((w) => { w.hidden = true; w.classList.remove("is-closing", "is-min"); }); }
  $("#wins").addEventListener("click", (e) => {
    const w = e.target.closest(".mail, .win"); if (!w) return;
    if (e.target.closest(".tl-close, .w-x")) closeWindow(w);
    else if (e.target.closest(".tl-min")) { w.classList.toggle("is-min"); front(w); }
  });
  let WD = null;
  $("#wins").addEventListener("pointerdown", (e) => {
    const w = e.target.closest(".mail, .win"); if (!w) return;
    front(w);
    const h = e.target.closest(".m-bar, .w-bar, .a-head");
    if (!h || e.target.closest("button") || mqCompact.matches || e.button > 0) return;
    const r = w.getBoundingClientRect();
    WD = { w, id: e.pointerId, x0: e.clientX, y0: e.clientY, wx: parseFloat(w.style.getPropertyValue("--wx")) || 0, wy: parseFloat(w.style.getPropertyValue("--wy")) || 0, r, sr: screen.getBoundingClientRect() };
    try { h.setPointerCapture(e.pointerId); } catch { /* not capturable */ }
    screen.classList.add("is-moving"); e.preventDefault();
  });
  document.addEventListener("pointermove", (e) => {
    if (!WD || e.pointerId !== WD.id) return;
    const { r, sr } = WD, keep = 90;
    const dx = clamp(e.clientX - WD.x0, sr.left + keep - r.right, sr.right - keep - r.left);
    const dy = clamp(e.clientY - WD.y0, sr.top + menubarH() - r.top, sr.bottom - 40 - r.top);
    WD.w.style.setProperty("--wx", `${WD.wx + dx}px`); WD.w.style.setProperty("--wy", `${WD.wy + dy}px`);
  });
  const endWD = (e) => { if (WD && e.pointerId === WD.id) { WD = null; screen.classList.remove("is-moving"); } };
  document.addEventListener("pointerup", endWD); document.addEventListener("pointercancel", endWD);

  /* ----- Dock: magnification, bounce, and the Trash ----- */
  const dkItems = $$(".dk-i");
  function magnify(x, trash) {
    const base = adBar.getBoundingClientRect().left;
    dkItems.forEach((it) => {
      let s = 1;
      if (trash && it === trashEl) s = 1.5;
      else if (x != null) { const c = base + it.offsetLeft + it.offsetWidth / 2, d = Math.abs(x - c) / (it.offsetWidth * 1.5); s = 1 + 0.52 * Math.exp(-d * d * 2.4); }
      it.style.setProperty("--s", s.toFixed(3));
    });
  }
  adBar.addEventListener("pointermove", (e) => { if (e.pointerType !== "touch" && !D) magnify(e.clientX, false); });
  adBar.addEventListener("pointerleave", () => { if (!D) magnify(null, false); });
  dkItems.forEach((b) => b.addEventListener("click", () => {
    b.classList.remove("is-bounce"); void b.offsetWidth; b.classList.add("is-bounce"); setTimeout(() => b.classList.remove("is-bounce"), 650);
    const app = b.dataset.app;
    if (app === "mail") { if (mailEl.hidden) { openWindow(mailEl); say("Mail draft opened"); } else { mailEl.classList.remove("is-min"); front(mailEl); } }
    else if (app === "terminal") openTerminal(null);
    else if (app === "finder") openFinder(selFiles());
    else if (app === "trash") toast("Drop a file on the Trash to remove it");
  }));

  /* ----- Actions ----- */
  const idsOf = (f) => (f.multi ? f.files.map((x) => x.id) : [f.id]);
  function perform(it, f, point) {
    const n = nameOf(f);
    switch (it.id) {
      case "airdrop": return openAirDrop(f);
      case "copy": return toast(`Copied ${n}`);
      case "copypath": { const path = f.multi ? f.files.map((x) => `~/Desktop/${nameOf(x)}`).join("\n") : `~/Desktop/${n}`; try { navigator.clipboard.writeText(path); } catch { /* clipboard unavailable */ } return toast(f.multi ? `Copied ${f.files.length} paths` : `Copied ${path}`); }
      case "move": return toast("Opens a folder picker on your Mac");
      case "copyto": return toast("Opens a folder picker on your Mac");
      case "terminal": return openTerminal(f);
      case "float": return floatFile(f);
      case "reveal": return openFinder(f.multi ? f.files : [f]);
    }
  }
  function openFinder(list) {
    const w = wins.finder, ul = $("#fi-list"), hitIds = new Set((list || []).map((x) => x.id));
    openWindow(w);
    const rows = files.slice().sort((a, b) => nameOf(a).localeCompare(nameOf(b)));
    ul.innerHTML = rows.map((x) => `<li data-id="${x.id}" class="${hitIds.has(x.id) ? "is-hit" : ""}">${iconHTML(x)}<span class="fi-n">${esc(nameOf(x))}</span><span class="fi-s">${esc(x.folder ? "Folder" : fmt(x.mb))}</span></li>`).join("");
    const hitEl = $(".is-hit", ul); if (hitEl) ul.scrollTop = Math.max(0, hitEl.offsetTop - ul.clientHeight / 2 + hitEl.offsetHeight / 2);
    say(hitIds.size ? `Finder is showing ${list.map(nameOf).join(", ")}` : "Finder, Desktop");
    return w;
  }
  let termRun = 0;
  async function openTerminal(f) {
    const w = wins.term; openWindow(w);
    const body = $("#t-body"), host = "you@Mac";
    const target = f ? (f.multi ? f.files.map(nameOf).map((n) => `"${n}"`).join(" ") : `"${nameOf(f)}"`) : null;
    const cmds = ["cd ~/Desktop"].concat(target ? [`ls ${target}`] : []);
    let text = `<span class="t-dim">Last login: Tue 9:41 on ttys001</span>\n${host} ~ % `;
    const draw = (t) => { body.innerHTML = `${t}<span class="t-caret"></span>`; };
    draw(text);
    const key = ++termRun;
    for (let c = 0; c < cmds.length; c++) {
      for (const ch of cmds[c]) { if (key !== termRun || w.hidden) return; text += esc(ch); draw(text); if (!rm()) await sleep(48); }
      if (c === 0) text += `\n${host} Desktop % `; else text += `\n${esc(target.replace(/"/g, ""))}\n${host} Desktop % `;
      draw(text); if (!rm()) await sleep(280);
    }
    say("Terminal opened in the Desktop folder");
  }
  function openAirDrop(f) {
    const w = wins.air, st = $("#a-state");
    winTimers.forEach(clearTimeout); winTimers = [];
    openWindow(w);
    $("#a-file").innerHTML = `${iconHTML(f)}<span>${esc(nameOf(f))}</span>`;
    st.textContent = "Waiting"; st.classList.remove("ok");
    winTimers.push(setTimeout(() => { st.textContent = "Sending…"; }, 900), setTimeout(() => { st.textContent = "Sent"; st.classList.add("ok"); say(`${nameOf(f)} sent to Anna’s iPhone`); }, 2200), setTimeout(() => closeWindow(w), 4600));
  }
  function floatFile(f) {
    const box = $("#floats");
    (f.multi ? f.files : [f]).forEach((x) => {
      if ($(`[data-fid="${x.id}"]`, box)) return;
      const t = document.createElement("div");
      t.className = "float-tile"; t.dataset.fid = x.id;
      t.innerHTML = `${iconHTML(x)}<span>${esc(nameOf(x))}</span><button type="button" aria-label="Stop floating ${esc(nameOf(x))}">×</button>`;
      $("button", t).addEventListener("click", () => t.remove());
      box.appendChild(t);
    });
    say(`${nameOf(f)} is floating on screen`);
  }

  /* ----- Mail draft ----- */
  let mailFiles = [];
  const chips = $("#m-chips"), attachBtn = $("#attach-sel");
  function attach(f) {
    if (mailFiles.some((x) => x.id === f.id)) { toast(`${nameOf(f)} is already attached`); return; }
    mailFiles.push(f);
    const li = document.createElement("li");
    li.className = "m-chip"; li.dataset.id = f.id;
    li.innerHTML = `${iconHTML(f)}<span class="m-chip-t"><span class="m-chip-n">${esc(nameOf(f))}</span><span class="m-chip-s">${esc(fmt(f.mb))}</span></span><button type="button" aria-label="Remove ${esc(nameOf(f))}">×</button>`;
    $("button", li).addEventListener("click", () => { mailFiles = mailFiles.filter((x) => x.id !== f.id); li.remove(); mailHead(); refreshScenario(); });
    chips.appendChild(li); mailHead();
    say(`Attached ${nameOf(f)} to the draft`);
    refreshScenario();
  }
  function mailHead() {
    const n = mailFiles.length, total = mailFiles.reduce((s, x) => s + x.mb, 0);
    $("#m-sub").textContent = n ? `${n} attachment${n > 1 ? "s" : ""} · ${fmt(total)}` : "New message";
  }
  attachBtn.addEventListener("click", () => { selFiles().forEach(attach); });

  /* ----- The scenario checklist ----- */
  const sc = $("#scenario"), steps = $$("#checklist li");
  let wasComplete = false, prog = { jpg: null, small: null };
  function setStep(i, done, detail) {
    steps[i].classList.toggle("is-done", !!done);
    $(".sc-detail", steps[i]).textContent = done ? detail : "";
  }
  function refreshScenario() {
    if (!prog.jpg) prog.jpg = files.find((f) => f.created && f.root === "holiday" && f.ext === "jpg") || null;
    if (!prog.small) prog.small = files.find((f) => f.created && f.root === "weekend" && f.tag === "compress") || null;
    const jpg = prog.jpg, small = prog.small;
    const att = mailFiles.find((f) => f.created && f.root === "holiday" && f.ext === "jpg");
    setStep(0, jpg, jpg ? `${nameOf(jpg)} · ${fmt(jpg.mb)}${jpg.mb < 2 ? ", under 2 MB" : ""}` : "");
    setStep(1, att, att ? `${nameOf(att)} is attached to the draft` : "");
    setStep(2, small, small ? small.detail : "");
    const all = !!(jpg && att && small);
    sc.classList.toggle("is-complete", all);
    $(".sc-success", sc).setAttribute("aria-hidden", String(!all));
    $$(".sc-success a, .sc-success button", sc).forEach((el) => { el.tabIndex = all ? 0 : -1; });
    if (all && !wasComplete) say("All three steps are done. That’s Petal: no app window, no upload.");
    wasComplete = all;
  }

  /* ----- Reset ----- */
  function resetDemo() {
    closeWheel(false); hideCard(); toastEl.hidden = true; $("#floats").replaceChildren(); closeWins(); bandEl.hidden = true;
    winList.forEach((w) => { w.style.removeProperty("--wx"); w.style.removeProperty("--wy"); w.style.zIndex = ""; w.classList.remove("is-front", "is-min", "is-closing"); });
    mailEl.hidden = false; zTop = 10;
    learned = false; hideCoach(); dock.classList.remove("is-on"); screen.classList.remove("has-dock");
    mailFiles = []; chips.replaceChildren(); mailHead(); prog = { jpg: null, small: null };
    filesEl.replaceChildren(); elOf.clear(); files = []; uid = 0; fz = 1; sel = new Set(); attachBtn.disabled = true;
    SEED.forEach((s) => { const f = { ...s, root: s.id, p: { d: s.p.d.slice(), c: (s.p.c || s.p.d).slice() } }; files.push(f); makeEl(f); });
    layoutAll(); refreshScenario(); syncDock(); magnify(null, false);
    say("Desktop reset");
  }
  $$("[data-reset]").forEach((b) => b.addEventListener("click", () => { resetDemo(); const first = elOf.get("holiday"); if (first) first.focus({ preventScroll: true }); }));

  resetDemo(); say("");
  W.mode = "convert";
})();
