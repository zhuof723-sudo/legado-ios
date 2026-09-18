/* 纸阅 —— 最小可用 EPUB 阅读器原型
 * 技术栈：epub.js（解析/分页/主题） + IndexedDB（书库与进度） + 原生 DOM
 * 模块：偏好存储 / 书架 / 导入 / 阅读器 / 目录 / 样式面板
 */
(function () {
  "use strict";

  /* 环境补丁在 envfix.js 里（先于 epub.js 加载），此处只复用其日志 */
  var LOG = window.__readerLog;
  var log = window.__zyLog;

  var ePub = window.ePub;

  /* ---------- 偏好存储（localStorage 不可用时退化为内存） ---------- */
  var memStore = {};
  var prefs = {
    get: function (k, d) {
      try { var v = localStorage.getItem("zy." + k); return v === null ? d : v; }
      catch (e) { return k in memStore ? memStore[k] : d; }
    },
    set: function (k, v) {
      try { localStorage.setItem("zy." + k, v); } catch (e) { memStore[k] = v; }
    }
  };

  /* ---------- IndexedDB 封装 ---------- */
  var DB_NAME = "zhiyue-reader", STORE = "books", IDX_STORE = "indexes";
  function openDB() {
    return new Promise(function (resolve, reject) {
      var req = indexedDB.open(DB_NAME, 2);
      req.onupgradeneeded = function () {
        var db = req.result;
        if (!db.objectStoreNames.contains(STORE)) db.createObjectStore(STORE, { keyPath: "id" });
        if (!db.objectStoreNames.contains(IDX_STORE)) db.createObjectStore(IDX_STORE, { keyPath: "id" });
      };
      req.onsuccess = function () { resolve(req.result); };
      req.onerror = function () { reject(req.error); };
    });
  }
  function store(name, mode) {
    return openDB().then(function (db) { return db.transaction(name, mode).objectStore(name); });
  }
  function toPromise(req) {
    return new Promise(function (resolve, reject) {
      req.onsuccess = function () { resolve(req.result); };
      req.onerror = function () { reject(req.error); };
    });
  }
  var db = {
    all:   function () { return store(STORE, "readonly").then(function (s) { return toPromise(s.getAll()); }); },
    get:   function (id) { return store(STORE, "readonly").then(function (s) { return toPromise(s.get(id)); }); },
    put:   function (rec) { return store(STORE, "readwrite").then(function (s) { return toPromise(s.put(rec)); }); },
    del:   function (id) { return store(STORE, "readwrite").then(function (s) { return toPromise(s.delete(id)); }); },
    count: function () { return store(STORE, "readonly").then(function (s) { return toPromise(s.count()); }); }
  };
  var dbIdx = {
    get: function (id) { return store(IDX_STORE, "readonly").then(function (s) { return toPromise(s.get(id)); }); },
    put: function (rec) { return store(IDX_STORE, "readwrite").then(function (s) { return toPromise(s.put(rec)); }); }
  };

  /* ---------- 状态与工具 ---------- */
  var book = null, rendition = null, current = null, saveTimer = null;
  var EXT_BOOKS = []; /* shell 解包的外部书（books.json） */

  function $(id) { return document.getElementById(id); }
  function escapeHTML(s) {
    return String(s == null ? "" : s).replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
    });
  }
  function toast(msg) {
    var t = $("toast");
    t.textContent = msg;
    t.classList.remove("hidden");
    clearTimeout(toast._t);
    toast._t = setTimeout(function () { t.classList.add("hidden"); }, 2200);
  }

  /* ---------- 主题与字号 ---------- */
  var THEMES = {
    light: { body: { color: "#1d1d1f", background: "#ffffff" } },
    sepia: { body: { color: "#5a4b34", background: "#f8f1e2" } },
    dark:  { body: { color: "#d6d6da", background: "#1c1c1e" } }
  };
  function applyTheme(name) {
    if (!THEMES[name]) name = "light";
    document.body.setAttribute("data-theme", name);
    prefs.set("theme", name);
    if (rendition) { try { rendition.themes.select(name); } catch (e) {} }
    var chips = document.querySelectorAll(".theme-chip");
    for (var i = 0; i < chips.length; i++) {
      chips[i].classList.toggle("active", chips[i].getAttribute("data-theme") === name);
    }
  }
  function applyFontSize(pct) {
    pct = Math.min(220, Math.max(70, Math.round(pct) || 100));
    prefs.set("fontSize", pct);
    $("fontVal").textContent = pct + "%";
    if (rendition) { try { rendition.themes.fontSize(pct + "%"); } catch (e) {} }
  }

  /* ---------- 外部书（大书由 shell 解包，页面按文件读取） ---------- */
  async function loadExternalBooks() {
    try {
      var r = await fetch("books.json?t=" + Date.now());
      var arr = await r.json();
      if (Array.isArray(arr)) EXT_BOOKS = arr;
    } catch (e) { /* 没有外部书 */ }
  }
  function extHidden() {
    try { return JSON.parse(prefs.get("extHidden", "[]")) || []; } catch (e) { return []; }
  }
  function extProgress(id) {
    try { return JSON.parse(prefs.get("ext." + id, "{}")) || {}; } catch (e) { return {}; }
  }

  /* ---------- 书架 ---------- */
  function coverHTML(rec) {
    if (rec.coverPath) return '<img class="cover-img" src="' + rec.coverPath + '" alt=""/>';
    if (rec.cover) return '<img class="cover-img" src="' + rec.cover + '" alt=""/>';
    var ch = (rec.title || "书").trim().charAt(0) || "书";
    return '<div class="cover-ph">' + escapeHTML(ch) + "</div>";
  }
  async function renderLibrary() {
    var grid = $("bookGrid");
    var records = [];
    try { records = await db.all(); } catch (e) { toast("本机存储不可用"); }
    /* 合并 shell 解包的外部书 */
    var hidden = extHidden();
    EXT_BOOKS.forEach(function (e) {
      if (hidden.indexOf(e.id) >= 0) return;
      var p = extProgress(e.id);
      records.push({
        id: e.id, ext: true,
        title: e.title, author: e.author,
        coverPath: e.cover || null,
        cfi: p.cfi || null,
        percent: p.percent || 0,
        addedAt: e.addedAt || 0,
        updatedAt: e.addedAt || 0
      });
    });
    /* 排序：recent 最近阅读 | added 添加时间 | title 书名 */
    var mode = prefs.get("libSort", "recent");
    if (mode === "title") {
      records.sort(function (a, b) { return String(a.title || "").localeCompare(String(b.title || ""), "zh"); });
    } else if (mode === "added") {
      records.sort(function (a, b) { return (b.addedAt || 0) - (a.addedAt || 0); });
    } else {
      records.sort(function (a, b) { return (b.updatedAt || b.addedAt || 0) - (a.updatedAt || a.addedAt || 0); });
    }
    var asList = prefs.get("libView", "grid") === "list";
    grid.classList.toggle("as-list", asList);
    grid.innerHTML = "";
    $("libEmpty").classList.toggle("hidden", records.length > 0);
    records.forEach(function (rec) {
      var pct = Math.max(0, Math.min(100, rec.percent || 0));
      var el = document.createElement("div");
      var delSelector = ".card-del";
      if (asList) {
        el.className = "li-row";
        delSelector = ".li-del";
        el.innerHTML =
          '<div class="li-cover">' + coverHTML(rec) + "</div>" +
          '<div class="li-meta">' +
            '<div class="li-title">' + escapeHTML(rec.title) + "</div>" +
            '<div class="li-sub">' + escapeHTML(rec.author || "未知作者") + " · 已读 " + pct + "%</div>" +
            '<div class="li-progress"><i style="width:' + pct + '%"></i></div>' +
          "</div>" +
          '<button class="li-del">✕</button>';
      } else {
        el.className = "book-card";
        el.innerHTML =
          '<div class="cover-wrap">' + coverHTML(rec) +
            '<button class="card-del" title="移除">✕</button>' +
          "</div>" +
          '<div class="book-meta">' +
            '<div class="book-title">' + escapeHTML(rec.title) + "</div>" +
            '<div class="book-author">' + escapeHTML(rec.author || "") + "</div>" +
            '<div class="card-progress"><i style="width:' + pct + '%"></i></div>' +
          "</div>";
      }
      el.addEventListener("click", function () { openBook(rec.id); });
      el.querySelector(delSelector).addEventListener("click", async function (e) {
        e.stopPropagation();
        if (!confirm("从书架移除《" + rec.title + "》？")) return;
        if (rec.ext) {
          var hidden = extHidden();
          if (hidden.indexOf(rec.id) < 0) hidden.push(rec.id);
          prefs.set("extHidden", JSON.stringify(hidden));
          renderLibrary();
        } else {
          await db.del(rec.id);
          renderLibrary();
        }
      });
      grid.appendChild(el);
    });
  }

  /* ---------- 书架排序/视图面板 ---------- */
  function syncLibSheet() {
    var mode = prefs.get("libSort", "recent");
    var view = prefs.get("libView", "grid");
    Array.prototype.forEach.call(document.querySelectorAll("#sortOpts .opt"), function (o) {
      o.classList.toggle("active", o.getAttribute("data-sort") === mode);
    });
    Array.prototype.forEach.call(document.querySelectorAll("#viewOpts .opt"), function (o) {
      o.classList.toggle("active", o.getAttribute("data-view") === view);
    });
  }

  /* ---------- 导入 ---------- */
  /* TXT 直导：编码探测 → 章节切分 → 内存里合成 EPUB（走 JSZip） */
  var TXT_CHAPTER_RE = /^\s{0,4}(第[0-9零〇一二三四五六七八九十百千万]+[章节卷回部集话幕][^\n]{0,32}|序章|楔子|引子|尾声|终章|后记|番外[^\n]{0,24}|Chapter\s+\d+[^\n]{0,40})\s*$/i;

  function decodeTxt(buf) {
    var encs = ["utf-8", "gb18030", "big5"];
    for (var i = 0; i < encs.length; i++) {
      try { return new TextDecoder(encs[i], { fatal: true }).decode(buf); } catch (e) {}
    }
    return new TextDecoder("utf-8").decode(buf);
  }

  function splitTxtChapters(text) {
    text = String(text).replace(/\r\n/g, "\n").replace(/\r/g, "\n");
    var lines = text.split("\n");
    var chapters = [], cur = { t: "卷首", p: [] };
    lines.forEach(function (ln) {
      var s = ln.trim();
      if (s && s.length <= 40 && TXT_CHAPTER_RE.test(s) && cur.p.length) {
        chapters.push(cur);
        cur = { t: s, p: [] };
      } else if (s) {
        cur.p.push(s);
      }
    });
    if (cur.p.length) chapters.push(cur);
    chapters = chapters.filter(function (c) { return c.p.length; });
    if (chapters.length < 3) {
      var paras = [];
      chapters.forEach(function (c) { paras = paras.concat(c.p); });
      chapters = [];
      var curp = [], acc = 0;
      paras.forEach(function (p) {
        curp.push(p); acc += p.length;
        if (acc >= 8000) {
          chapters.push({ t: "第 " + (chapters.length + 1) + " 部分", p: curp });
          curp = []; acc = 0;
        }
      });
      if (curp.length) chapters.push({ t: "第 " + (chapters.length + 1) + " 部分", p: curp });
    }
    return chapters;
  }

  function txtCoverSvg(title, author) {
    var n = Math.max(1, title.length);
    var fs = n <= 2 ? 150 : (n <= 4 ? 110 : (n <= 8 ? 80 : 62));
    var esc2 = function (s) { return String(s).replace(/[&<>"]/g, function (c) { return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]; }); };
    return '<?xml version="1.0" encoding="utf-8"?>' +
      '<svg xmlns="http://www.w3.org/2000/svg" width="600" height="900" viewBox="0 0 600 900">' +
      '<defs><linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">' +
      '<stop offset="0" stop-color="#31435f"/><stop offset="1" stop-color="#141b2b"/></linearGradient></defs>' +
      '<rect width="600" height="900" fill="url(#bg)"/>' +
      '<circle cx="450" cy="210" r="84" fill="#e8c268" opacity="0.9"/>' +
      '<circle cx="420" cy="190" r="9" fill="#d4a53f"/>' +
      '<text x="80" y="470" font-family="Songti SC, STSong, serif" font-size="' + fs + '" fill="#f5efe4">' + esc2(title) + '</text>' +
      '<rect x="92" y="520" width="150" height="7" fill="#e8c268"/>' +
      '<text x="92" y="575" font-family="Songti SC, STSong, serif" font-size="28" fill="#f5efe4" opacity="0.8">TXT 转制</text>' +
      '<text x="92" y="640" font-family="Songti SC, STSong, serif" font-size="26" fill="#f5efe4" opacity="0.65">' + esc2(author || "") + '</text>' +
      '</svg>';
  }

  async function txtToEpubBuffer(title, author, chapters) {
    var zip = new window.JSZip();
    zip.file("mimetype", "application/epub+zip", { compression: "STORE" });
    zip.file("META-INF/container.xml",
      '<?xml version="1.0" encoding="utf-8"?>' +
      '<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">' +
      '<rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>');
    zip.file("OEBPS/style.css",
      'body { font-family: "Songti SC", "STSong", serif; line-height: 1.95; margin: 0; padding: 0 6px; }' +
      'h1 { font-size: 1.15em; font-weight: 700; margin: 1.1em 0 1.2em; text-align: center; }' +
      'p { text-indent: 2em; margin: 0 0 0.7em 0; text-align: justify; }');
    zip.file("OEBPS/cover.svg", txtCoverSvg(title, author));
    zip.file("OEBPS/cover.xhtml",
      '<?xml version="1.0" encoding="utf-8"?>' +
      '<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="zh"><head><meta charset="utf-8"/><title>封面</title>' +
      '<style type="text/css">body{margin:0;padding:0;text-align:center;background:#141b2b;}img{max-width:100%;height:auto;}</style></head>' +
      '<body><img src="cover.svg" alt="封面"/></body></html>');

    var navItems = [], ncx = [], mani = [], spine = [];
    chapters.forEach(function (ch, i) {
      var fn = "f" + (i + 1) + ".xhtml";
      var body = ch.p.map(function (p) { return "    <p>" + escapeHTML(p) + "</p>"; }).join("\n");
      zip.file("OEBPS/" + fn,
        '<?xml version="1.0" encoding="utf-8"?>' +
        '<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="zh"><head><meta charset="utf-8"/><title>' + escapeHTML(ch.t) + '</title>' +
        '<link rel="stylesheet" type="text/css" href="style.css"/></head>' +
        '<body><h1>' + escapeHTML(ch.t) + '</h1>' + body + '</body></html>');
      navItems.push('<li><a href="' + fn + '">' + escapeHTML(ch.t) + "</a></li>");
      ncx.push('<navPoint id="np' + (i + 1) + '" playOrder="' + (i + 1) + '"><navLabel><text>' + escapeHTML(ch.t) + '</text></navLabel><content src="' + fn + '"/></navPoint>');
      mani.push('<item id="c' + (i + 1) + '" href="' + fn + '" media-type="application/xhtml+xml"/>');
      spine.push('<itemref idref="c' + (i + 1) + '"/>');
    });
    zip.file("OEBPS/nav.xhtml",
      '<?xml version="1.0" encoding="utf-8"?>' +
      '<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="zh">' +
      '<head><meta charset="utf-8"/><title>目录</title></head><body>' +
      '<nav epub:type="toc" id="toc"><h1>目录</h1><ol>' + navItems.join("") + '</ol></nav></body></html>');
    zip.file("OEBPS/toc.ncx",
      '<?xml version="1.0" encoding="utf-8"?>' +
      '<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1"><head>' +
      '<meta name="dtb:uid" content="urn:uuid:txt"/><meta name="dtb:depth" content="1"/></head>' +
      '<docTitle><text>' + escapeHTML(title) + '</text></docTitle><navMap>' + ncx.join("") + '</navMap></ncx>');
    zip.file("OEBPS/content.opf",
      '<?xml version="1.0" encoding="utf-8"?>' +
      '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bookid" xml:lang="zh">' +
      '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">' +
      '<dc:identifier id="bookid">urn:uuid:' + Date.now().toString(36) + '</dc:identifier>' +
      '<dc:title>' + escapeHTML(title) + '</dc:title><dc:creator>' + escapeHTML(author) + '</dc:creator><dc:language>zh</dc:language>' +
      '<meta property="dcterms:modified">2026-09-17T00:00:00Z</meta><meta name="cover" content="cover-image"/></metadata>' +
      '<manifest><item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>' +
      '<item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>' +
      '<item id="css" href="style.css" media-type="text/css"/>' +
      '<item id="cover-image" href="cover.svg" media-type="image/svg+xml" properties="cover-image"/>' +
      '<item id="coverpage" href="cover.xhtml" media-type="application/xhtml+xml"/>' + mani.join("") +
      '</manifest><spine toc="ncx"><itemref idref="coverpage"/>' + spine.join("") + '</spine></package>');
    return zip.generateAsync({ type: "arraybuffer", compression: "DEFLATE" });
  }

  async function importTxt(file) {
    toast("正在解析 " + file.name + " …");
    try {
      var buf = await file.arrayBuffer();
      var text = decodeTxt(buf);
      var lines = text.split("\n");
      var title = file.name.replace(/\.(txt|text)$/i, "");
      var author = "";
      for (var i = 0; i < Math.min(30, lines.length); i++) {
        var m = lines[i].trim().match(/^作者[:：]\s*(.+)$/);
        if (m) { author = m[1].trim(); break; }
      }
      author = author || "未知作者";
      var chapters = splitTxtChapters(text);
      if (!chapters.length) { toast("文件内容为空"); return; }
      toast("正在合成 EPUB（" + chapters.length + " 章）…");
      var epubBuf = await txtToEpubBuffer(title, author, chapters);
      await addBook(epubBuf, file.name);
    } catch (e) {
      console.error(e);
      toast("TXT 导入失败：" + (e && e.message));
    }
  }

  async function importFile(file) {
    var isTxt = /\.(txt|text)$/i.test(file.name) || file.type === "text/plain";
    if (isTxt) {
      if (file.size > 20 * 1024 * 1024) {
        toast("TXT 超过 20MB——把它作为聊天附件发给我来导入");
        return;
      }
      await importTxt(file);
      return;
    }
    if (!/\.epub$/i.test(file.name) && file.type !== "application/epub+zip") {
      toast("目前支持 EPUB 与 TXT 文件");
      return;
    }
    if (file.size > 100 * 1024 * 1024) {
      toast("文件超过 100MB，网页版装不下——把它作为聊天附件发给我来导入");
      return;
    }
    toast("正在导入 " + file.name + " …");
    try {
      var buf = await file.arrayBuffer();
      await addBook(buf, file.name);
    } catch (e) {
      console.error(e);
      toast("导入失败：" + (e && e.message));
    }
  }

  async function extractCover(b) {
    try {
      var url = await b.coverUrl();
      if (!url) return null;
      return await new Promise(function (resolve) {
        var img = new Image();
        img.onload = function () {
          try {
            var w = 300, h = Math.max(1, Math.round(img.naturalHeight * 300 / img.naturalWidth));
            var c = document.createElement("canvas");
            c.width = w; c.height = h;
            c.getContext("2d").drawImage(img, 0, 0, w, h);
            resolve(c.toDataURL("image/jpeg", 0.82));
          } catch (e) { resolve(null); }
        };
        img.onerror = function () { resolve(null); };
        img.src = url;
      });
    } catch (e) { return null; }
  }

  async function addBook(buf, filename) {
    var b = ePub(buf);
    try {
      var meta = await b.loaded.metadata;
      var cover = await extractCover(b);
      var rec = {
        id: "b" + Date.now().toString(36) + Math.random().toString(36).slice(2, 7),
        title: (meta && meta.title) || String(filename).replace(/\.epub$/i, ""),
        author: (meta && meta.creator) || "未知作者",
        cover: cover,
        data: buf,
        cfi: null, percent: 0,
        addedAt: Date.now(), updatedAt: Date.now()
      };
      await db.put(rec);
      toast("已加入《" + rec.title + "》");
      await renderLibrary();
    } finally {
      try { b.destroy(); } catch (e) {}
    }
  }

  /* ---------- 阅读 ---------- */
  function closeToc() { $("tocDrawer").classList.remove("open"); $("tocMask").classList.add("hidden"); }
  function closeStyle() { $("stylePanel").classList.remove("open"); $("styleMask").classList.add("hidden"); }

  function showLibrary() {
    if (saveTimer) { clearTimeout(saveTimer); saveTimer = null; }
    saveCurrentNow();
    stopSelPoll();
    hideHlPop();
    clearSearchMark();
    if (rendition) { try { rendition.destroy(); } catch (e) {} }
    if (book) { try { book.destroy(); } catch (e) {} }
    rendition = null; book = null; current = null;
    closeToc(); closeStyle();
    $("readerView").classList.add("hidden");
    $("libraryView").classList.remove("hidden");
    renderLibrary();
  }

  function showReader(title) {
    $("libraryView").classList.add("hidden");
    $("readerView").classList.remove("hidden");
    $("bookTitle").textContent = title || "";
    $("progressText").textContent = "…";
    $("panelProgress").textContent = "—";
    $("progressBar").style.width = "0%";
    $("tocList").innerHTML = "";
    $("stage").innerHTML = "";
    $("loading").classList.remove("hidden");
  }

  /* ---------- 相对路径解析（书内资源用） ---------- */
  function resolveZipPath(base, rel) {
    if (rel.charAt(0) === "/") return rel.replace(/^\/+/, "");
    var parts = base.split("/");
    parts.pop(); /* 去掉文件名，留下所在目录 */
    rel.split("/").forEach(function (seg) {
      if (seg === "..") parts.pop();
      else if (seg && seg !== ".") parts.push(seg);
    });
    return parts.join("/");
  }

  /* epub.js 的资源替换不处理 SVG <image xlink:href>（中文书封面常见）。
   * 不依赖它的 content 钩子（在本 WebView 里触发不稳定），
   * 每次页面定位后主动扫描 iframe，把这些资源改成 zip 内的 blob URL */
  function fixImagesInDoc(doc, bk) {
    try {
      if (!doc || !bk || !bk.archive) return;
      var baseEl = doc.querySelector("base");
      var baseHref = (baseEl && baseEl.getAttribute("href")) || "";
      var m = baseHref.match(/^minis:\/\/workspace\/(.+)$/);
      if (!m) return;
      var baseZip = m[1];
      var imgs = doc.querySelectorAll("image, img");
      Array.prototype.forEach.call(imgs, function (img) {
        var raw = img.getAttribute("xlink:href") || img.getAttribute("href") ||
                  img.getAttribute("src") || "";
        if (!raw || /^(data:|blob:|https?:)/i.test(raw)) return;
        var abs = resolveZipPath(baseZip, raw);
        /* epub.js 的 Archive.createUrl 内部会 substr(1) 剥掉前导斜杠，必须传 "/xxx" 形式 */
        bk.archive.createUrl("/" + abs, { base64: false }).then(function (url) {
          if (img.hasAttribute("xlink:href")) img.setAttribute("xlink:href", url);
          if (/^image$/i.test(img.tagName)) img.setAttribute("href", url);
          if (img.hasAttribute("src")) img.setAttribute("src", url);
        }).catch(function () {});
      });
    } catch (e) { log("fixImages err: " + e.message); }
  }

  function sweepBookImages() {
    if (!book) return;
    var frames = document.querySelectorAll("#stage iframe");
    Array.prototype.forEach.call(frames, function (f) {
      try { if (f.contentDocument) fixImagesInDoc(f.contentDocument, book); } catch (e) {}
    });
    /* epub.js 的高亮覆盖层 svg 默认 pointer-events:none，点击会穿透——
     * 打开每个标注的点击，让用户能点高亮进入编辑 */
    var gs = document.querySelectorAll('#stage svg g[ref]');
    for (var i = 0; i < gs.length; i++) {
      gs[i].style.pointerEvents = "auto";
      gs[i].style.cursor = "pointer";
    }
  }

  /* ---------- 翻页动画 ----------
   * 旧页滑出（160ms）→ 导航 → 新页从对侧滑入（160ms） */
  var ptBusy = false;
  function pageTurn(dir) {
    if (!rendition || ptBusy) return;
    ptBusy = true;
    var stage = $("stage");
    var outCls = dir > 0 ? "pt-out-next" : "pt-out-prev";
    var inCls = dir > 0 ? "pt-in-next" : "pt-in-prev";
    stage.classList.add(outCls);
    setTimeout(function () {
      var nav = null;
      try { nav = dir > 0 ? rendition.next() : rendition.prev(); } catch (e) {}
      Promise.resolve(nav).catch(function () {}).then(function () {
        stage.classList.remove(outCls);
        stage.classList.add("pt-no-anim", inCls);
        void stage.offsetWidth; /* 强制 reflow，让起始位置立即生效 */
        stage.classList.remove("pt-no-anim");
        stage.classList.remove(inCls);
        setTimeout(function () { ptBusy = false; }, 180);
      });
    }, 160);
  }

  /* ---------- 高亮与笔记 ----------
   * 本 WebView 里 iframe 内部事件（selectionchange/click）不可靠，
   * 改用 400ms 轮询检测选区；高亮的 SVG 覆盖层画在父文档，
   * 其点击回调可用（父文档事件正常）。CFI 用 new ePub.CFI(range, cfiBase) 生成。 */
  var HL_COLORS = { yellow: "#ffd52e", green: "#93e768", blue: "#5ac8fa", pink: "#ff89b0", purple: "#c7a2ff" };
  var pendingSel = null; /* 新选区 {cfi,text,range,iframe} */
  var editingHl = null;  /* 正在编辑的已有高亮记录 */
  var editorColor = "yellow";
  var selPoll = null;

  function hls() {
    if (!current) return [];
    try { return JSON.parse(prefs.get("hl." + current.id, "[]")) || []; } catch (e) { return []; }
  }
  function hlsSave(arr) {
    if (current) prefs.set("hl." + current.id, JSON.stringify(arr));
    renderNoteList();
  }
  function hlsFind(id) {
    var arr = hls();
    for (var i = 0; i < arr.length; i++) if (arr[i].id === id) return arr[i];
    return null;
  }

  function startSelPoll() {
    stopSelPoll();
    selPoll = setInterval(checkSelection, 400);
  }
  function stopSelPoll() {
    if (selPoll) { clearInterval(selPoll); selPoll = null; }
  }

  function checkSelection() {
    if (!rendition) return;
    if (!$("hlEditor").classList.contains("hidden")) return; /* 编辑笔记时不打扰 */
    var found = null;
    var frames = document.querySelectorAll("#stage iframe");
    var views = [];
    try { rendition.views().forEach(function (v) { views.push(v); }); } catch (e) {}
    for (var i = 0; i < frames.length && !found; i++) {
      var f = frames[i], sel = null;
      try { sel = f.contentWindow.getSelection(); } catch (e) { continue; }
      if (!sel || sel.rangeCount === 0 || sel.isCollapsed) continue;
      var text = String(sel.toString() || "").trim();
      if (!text) continue;
      var view = null;
      for (var k = 0; k < views.length; k++) if (views[k].iframe === f) { view = views[k]; break; }
      if (!view || !view.contents) continue;
      var cfi = null;
      try { cfi = new window.ePub.CFI(sel.getRangeAt(0), view.contents.cfiBase).toString(); }
      catch (e) { continue; }
      found = { cfi: cfi, text: text.slice(0, 200), range: sel.getRangeAt(0), iframe: f };
    }
    if (!found) {
      if (pendingSel) { pendingSel = null; editingHl = null; hideHlPop(); }
      return;
    }
    if (pendingSel && pendingSel.cfi === found.cfi) { positionHlPop(found); return; }
    pendingSel = found;
    editingHl = null;
    showHlPop();
  }

  function showHlPop() {
    $("hlEditor").classList.add("hidden");
    $("hlRemoveBtn").classList.toggle("hidden", !editingHl);
    markActiveDots(editingHl ? editingHl.color : null);
    positionHlPop(pendingSel);
  }
  function hideHlPop() {
    $("hlPop").classList.add("hidden");
    $("hlEditor").classList.add("hidden");
  }
  function markActiveDots(color) {
    var dots = document.querySelectorAll(".hl-dot");
    for (var i = 0; i < dots.length; i++) {
      dots[i].classList.toggle("active", dots[i].getAttribute("data-color") === color);
    }
  }

  function positionHlPop(sel) {
    if (!sel) return;
    var pop = $("hlPop");
    var left = window.innerWidth / 2 - 150, top = window.innerHeight / 2 - 60;
    try {
      var r = sel.range.getBoundingClientRect();
      var fr = sel.iframe.getBoundingClientRect();
      var cx = fr.left + r.left + r.width / 2, cy = fr.top + r.top;
      var pw = pop.offsetWidth || 300, ph = pop.offsetHeight || 48;
      left = Math.max(10, Math.min(window.innerWidth - pw - 10, cx - pw / 2));
      top = cy - ph - 12;
      if (top < 62) top = fr.top + r.bottom + 12;
    } catch (e) {}
    pop.style.left = Math.round(left) + "px";
    pop.style.top = Math.round(Math.max(62, top)) + "px";
    pop.classList.remove("hidden");
  }

  function injectHl(hl) {
    try {
      rendition.annotations.highlight(hl.cfi, { id: hl.id }, onHlMarkClick, "hl-" + hl.id, {
        fill: HL_COLORS[hl.color] || HL_COLORS.yellow,
        "fill-opacity": "0.35",
        "mix-blend-mode": "multiply"
      });
    } catch (e) { log("injectHl err: " + (e && e.message)); }
    /* 覆盖层默认不可点，打开点击 */
    setTimeout(function () {
      var g = document.querySelector('#stage svg g[ref="hl-' + hl.id + '"]');
      if (g) { g.style.pointerEvents = "auto"; g.style.cursor = "pointer"; }
    }, 200);
  }
  function applyAllHls() {
    hls().forEach(injectHl);
  }

  /* 点击已有高亮（SVG 覆盖层在父文档，事件可用） */
  function onHlMarkClick(e) {
    var el = e.target;
    while (el && el !== document.body && !(el.getAttribute && el.getAttribute("ref"))) el = el.parentElement;
    var ref = (el && el.getAttribute("ref")) || "";
    var id = ref.replace(/^hl-/, "");
    var hl = hlsFind(id);
    if (!hl) return;
    editingHl = hl;
    pendingSel = null;
    /* 就近弹窗 */
    $("hlEditor").classList.add("hidden");
    $("hlRemoveBtn").classList.remove("hidden");
    markActiveDots(hl.color);
    editorColor = hl.color;
    var pop = $("hlPop");
    pop.classList.remove("hidden");
    var r = e.target.getBoundingClientRect();
    var pw = pop.offsetWidth || 300;
    pop.style.left = Math.round(Math.max(10, Math.min(window.innerWidth - pw - 10, r.left + r.width / 2 - pw / 2))) + "px";
    pop.style.top = Math.round(Math.max(62, r.top - 56)) + "px";
  }

  function clearSel() {
    if (pendingSel && pendingSel.iframe) {
      try { pendingSel.iframe.contentWindow.getSelection().removeAllRanges(); } catch (e) {}
    }
  }

  function applyHl(color, note) {
    if (!pendingSel || !rendition) return;
    var hl = {
      id: "h" + Date.now().toString(36) + Math.random().toString(36).slice(2, 5),
      cfi: pendingSel.cfi, color: color,
      text: pendingSel.text, note: note || "",
      at: Date.now()
    };
    var arr = hls();
    arr.push(hl);
    hlsSave(arr);
    injectHl(hl);
    clearSel();
    hideHlPop();
    toast("已高亮");
  }

  function changeHl(hl, color, note) {
    try { rendition.annotations.remove(hl.cfi, "highlight"); } catch (e) {}
    hl.color = color;
    if (note != null) hl.note = note;
    var arr = hls();
    for (var i = 0; i < arr.length; i++) if (arr[i].id === hl.id) arr[i] = hl;
    hlsSave(arr);
    injectHl(hl);
  }

  function removeHlById(id) {
    var arr = hls(), target = null;
    for (var i = arr.length - 1; i >= 0; i--) {
      if (arr[i].id === id) { target = arr[i]; arr.splice(i, 1); }
    }
    if (target && rendition) {
      try { rendition.annotations.remove(target.cfi, "highlight"); } catch (e) {}
    }
    hlsSave(arr);
  }

  function renderNoteList() {
    var list = $("noteList");
    if (!list) return;
    if (!current) { list.innerHTML = ""; return; }
    var arr = hls();
    if (!arr.length) { list.innerHTML = '<div class="note-empty">还没有高亮或笔记<br/>长按选中正文即可添加</div>'; return; }
    list.innerHTML = "";
    arr.slice().reverse().forEach(function (hl) {
      var item = document.createElement("div");
      item.className = "note-item";
      item.style.borderLeftColor = HL_COLORS[hl.color] || HL_COLORS.yellow;
      item.innerHTML =
        '<div class="note-text">' + escapeHTML(hl.text.slice(0, 160)) + "</div>" +
        (hl.note ? '<div class="note-note">' + escapeHTML(hl.note) + "</div>" : "") +
        '<button class="note-del">✕</button>';
      item.addEventListener("click", function (e) {
        if (e.target.classList.contains("note-del")) return;
        if (rendition) rendition.display(hl.cfi);
        closeNoteDrawer();
      });
      item.querySelector(".note-del").addEventListener("click", function (e) {
        e.stopPropagation();
        removeHlById(hl.id);
        toast("已删除");
      });
      list.appendChild(item);
    });
  }

  function openNoteDrawer() {
    renderNoteList();
    $("noteDrawer").classList.add("open");
    $("noteMask").classList.remove("hidden");
  }
  function closeNoteDrawer() {
    $("noteDrawer").classList.remove("open");
    $("noteMask").classList.add("hidden");
  }

  function copyText(txt) {
    if (!txt) return;
    var done = function (ok) { toast(ok ? "已复制" : "复制失败，可长按文本框手动复制"); };
    function fallback() {
      try {
        var ta = document.createElement("textarea");
        ta.value = txt;
        ta.setAttribute("readonly", "");
        ta.style.cssText = "position:fixed;top:0;left:0;opacity:0;";
        document.body.appendChild(ta);
        ta.focus();
        ta.setSelectionRange(0, txt.length);
        var ok = document.execCommand("copy");
        ta.remove();
        done(ok);
      } catch (e) { done(false); }
    }
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(txt).then(function () { done(true); }).catch(fallback);
    } else { fallback(); }
  }

  /* ---------- 笔记导出（Markdown） ---------- */
  function buildNotesMd() {
    var arr = hls();
    var d = new Date();
    var pad = function (n) { return (n < 10 ? "0" : "") + n; };
    var lines = [
      "# 《" + (current ? current.title : "") + "》高亮与笔记",
      "",
      "> 共 " + arr.length + " 条 · " + d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate()) + " " + pad(d.getHours()) + ":" + pad(d.getMinutes()) + " 导出",
      ""
    ];
    arr.forEach(function (hl, i) {
      lines.push("**" + (i + 1) + ".** " + (hl.text || ""));
      lines.push("");
      if (hl.note) { lines.push(hl.note); lines.push(""); }
      lines.push("---");
      lines.push("");
    });
    return lines.join("\n");
  }

  function openExportSheet() {
    if (!current) { toast("先打开一本书"); return; }
    var arr = hls();
    if (!arr.length) { toast("这本书还没有高亮或笔记"); return; }
    $("expCount").textContent = arr.length + " 条";
    $("expText").value = buildNotesMd();
    $("exportSheet").classList.add("open");
    $("exportMask").classList.remove("hidden");
  }
  function closeExportSheet() {
    $("exportSheet").classList.remove("open");
    $("exportMask").classList.add("hidden");
  }
  function downloadMd() {
    try {
      var md = $("expText").value;
      var blob = new Blob([md], { type: "text/markdown;charset=utf-8" });
      var url = URL.createObjectURL(blob);
      var a = document.createElement("a");
      a.href = url;
      a.download = (current ? current.title : "notes") + "-笔记.md";
      document.body.appendChild(a);
      a.click();
      setTimeout(function () { a.remove(); URL.revokeObjectURL(url); }, 800);
      toast("已尝试下载（若无反应请用「复制」）");
    } catch (e) {
      toast("下载失败，请用「复制」");
    }
  }

  /* ---------- 书内全文搜索 ----------
   * 外部书：读取解包时预建的 __index.json（本地文件直读，秒级）
   * 本地书：首次搜索时逐章抽取纯文本并缓存进 IndexedDB
   * 跳转：懒解析 CFI——加载对应章节文档，按纯文本偏移找到文本节点生成 CFI */
  var searchIdx = null, searchIdxFor = null, searchMarkCfi = null, searchBusy = false;

  function setSrchStatus(t) { $("searchStatus").textContent = t; }

  function decodeEntities(s) {
    return s
      .replace(/&#x([0-9a-fA-F]+);/g, function (_, h) { return String.fromCodePoint(parseInt(h, 16)); })
      .replace(/&#(\d+);/g, function (_, d) { return String.fromCodePoint(parseInt(d, 10)); })
      .replace(/&nbsp;/g, "\u00a0")
      .replace(/&lt;/g, "<").replace(/&gt;/g, ">")
      .replace(/&quot;/g, '"').replace(/&apos;/g, "'")
      .replace(/&amp;/g, "&");
  }
  function rawXhtmlToText(raw) {
    var s = String(raw)
      .replace(/<!--[\s\S]*?-->/g, "")
      .replace(/<style[\s\S]*?<\/style>/gi, "")
      .replace(/<script[\s\S]*?<\/script>/gi, "")
      .replace(/<[^>]+>/g, "");
    return decodeEntities(s);
  }
  function docTextOf(doc) {
    var out = [];
    var body = doc.body || doc.documentElement;
    if (!body) return "";
    var walker = doc.createTreeWalker(body, 4, null);
    var n;
    while ((n = walker.nextNode())) {
      var p = n.parentElement;
      if (p && /^(script|style)$/i.test(p.tagName)) continue;
      out.push(n.textContent);
    }
    return out.join("");
  }

  async function buildLocalIndex() {
    var items = book.spine.items || [];
    var navMap = {};
    try {
      var nav = await book.loaded.navigation;
      (function walk(list) {
        (list || []).forEach(function (it) {
          var h = (it.href || "").split("#")[0];
          if (h) {
            var key = h.replace(/^\//, "");
            var bname = key.split("/").pop();
            if (it.label && !(key in navMap)) navMap[key] = String(it.label).trim();
            if (it.label && !(bname in navMap)) navMap[bname] = String(it.label).trim();
          }
          if (it.subitems) walk(it.subitems);
        });
      })(nav.toc || []);
    } catch (e) {}
    var chapters = [];
    for (var i = 0; i < items.length; i++) {
      var it = items[i];
      var zipPath = String(it.url || it.href || "");
      var text = "";
      try {
        /* url 形如 "/OEBPS/chap1.xhtml"（相对 zip 根）；href 只是 manifest 相对名 */
        var zipPath = String(it.url || it.href || "");
        var raw = null;
        if (book.archive) {
          try { raw = await book.archive.getText(zipPath); } catch (e) {}
        }
        if (raw == null) raw = "";
        text = rawXhtmlToText(raw);
      } catch (e) {}
      var key = zipPath.replace(/^\//, "");
      var bname = key.split("/").pop();
      chapters.push({ i: i, t: navMap[key] || navMap[bname] || "第 " + (i + 1) + " 节", text: text });
      if (i % 25 === 0) setSrchStatus("正在建立索引 " + (i + 1) + "/" + items.length + " …");
    }
    return chapters;
  }

  async function ensureSearchIndex() {
    if (searchIdx && searchIdxFor === current.id) return searchIdx;
    searchIdx = null;
    searchIdxFor = current.id;
    if (current.ext) {
      var slug = "";
      for (var i = 0; i < EXT_BOOKS.length; i++) {
        if (EXT_BOOKS[i].id === current.id) { slug = EXT_BOOKS[i].slug; break; }
      }
      setSrchStatus("加载索引 …");
      var r = await fetch("books/" + slug + "/__index.json");
      var data = await r.json();
      searchIdx = (data && data.chapters) || [];
    } else {
      var cached = await dbIdx.get(current.id);
      if (cached && cached.chapters && cached.chapters.some(function (c) { return c.text && c.text.length; })) {
        searchIdx = cached.chapters;
      } else {
        setSrchStatus("首次搜索需要建立索引 …");
        searchIdx = await buildLocalIndex();
        try { await dbIdx.put({ id: current.id, chapters: searchIdx }); } catch (e) {}
      }
    }
    return searchIdx;
  }

  async function runSearch(q) {
    if (!q || !current) { $("searchResults").innerHTML = ""; setSrchStatus("输入关键词搜索本书"); return; }
    if (searchBusy) return;
    searchBusy = true;
    try {
      var idx = await ensureSearchIndex();
      var results = [], total = 0;
      for (var ci = 0; ci < idx.length; ci++) {
        var ch = idx[ci], text = ch.text;
        if (!text || text.indexOf(q) === -1) continue;
        var pos = text.indexOf(q);
        while (pos !== -1) {
          total++;
          if (results.length < 150) {
            var pre = Math.max(0, pos - 16);
            var post = Math.min(text.length, pos + q.length + 40);
            results.push({ i: ch.i, t: ch.t, off: pos, pre: text.slice(pre, pos), hit: q, post: text.slice(pos + q.length, post) });
          }
          pos = text.indexOf(q, pos + q.length);
        }
        if (total > 9999) break;
      }
      setSrchStatus(total ? ("共 " + total + (results.length < total ? " 处，显示前 " + results.length : " 处")) : "没有找到「" + q + "」");
      renderSearchResults(results);
    } catch (e) {
      setSrchStatus("搜索失败：" + (e && e.message));
    }
    searchBusy = false;
  }

  function renderSearchResults(results) {
    var box = $("searchResults");
    box.innerHTML = "";
    results.forEach(function (r) {
      var item = document.createElement("div");
      item.className = "sr-item";
      item.innerHTML =
        '<div class="sr-ch">' + escapeHTML(r.t) + "</div>" +
        '<div class="sr-text">…' + escapeHTML(r.pre) + "<mark>" + escapeHTML(r.hit) + "</mark>" + escapeHTML(r.post) + "…</div>";
      item.addEventListener("click", function () { jumpToResult(r); });
      box.appendChild(item);
    });
  }

  async function cfiForOffset(spineIdx, offset, len) {
    try {
      var section = book.spine.items[spineIdx];
      if (!section) { log("cfiForOffset: no section " + spineIdx); return null; }
      var doc = null;
      try {
        if (typeof section.load === "function") doc = await section.load(book.load.bind(book));
      } catch (e) { log("cfiForOffset: load err " + (e && e.message)); }
      if (!doc || !doc.body) {
        /* section.load 在本环境不存在：本地书从 zip 取原文，外部书按文件取 */
        var raw = null;
        if (current.ext) {
          var base = (current && current.opf || "").replace(/[^/]+$/, "");
          var url = null;
          try { url = book.resolve(section.href); } catch (e) {}
          if (!url || (url.indexOf("books/") !== 0 && url.indexOf("minis://") !== 0)) {
            url = base + String(section.href || "").replace(/^\//, "");
          }
          var resp = await fetch(url);
          raw = await resp.text();
        } else if (book.archive) {
          try { raw = await book.archive.getText(String(section.url || section.href || "")); } catch (e) {}
        }
        if (!raw) { log("cfiForOffset: no raw"); return null; }
        doc = new DOMParser().parseFromString(raw, "application/xhtml+xml");
        /* epub.js 渲染时会在 html 起始处注入一个 meta 节点，
         * 使 body 的节点序号 +1（CFI 步进 +2）。模拟注入，保证
         * 生成的 CFI 能在渲染文档中正确解析 */
        try {
          var fakeMeta = doc.createElement("meta");
          doc.documentElement.insertBefore(fakeMeta, doc.documentElement.firstChild);
        } catch (e) {}
        log("cfiForOffset: raw len=" + raw.length);
      }
      var bodyEl = doc.body || doc.getElementsByTagName("body")[0] || doc.documentElement;
      if (!bodyEl) { log("cfiForOffset: no doc"); return null; }
      var walker = doc.createTreeWalker(bodyEl, 4, null);
      var acc = 0, node = null, hit = null;
      while ((node = walker.nextNode())) {
        var p = node.parentElement;
        if (p && /^(script|style)$/i.test(p.tagName)) continue;
        var t = node.textContent;
        if (offset < acc + t.length) { hit = node; break; }
        acc += t.length;
      }
      if (!hit) { log("cfiForOffset: walk miss off=" + offset + " total=" + acc); return null; }
      var so = Math.max(0, offset - acc);
      var eo = Math.min(hit.textContent.length, so + len);
      if (eo <= so) eo = Math.min(hit.textContent.length, so + 1);
      var range = doc.createRange();
      range.setStart(hit, so);
      range.setEnd(hit, eo);
      return new window.ePub.CFI(range, section.cfiBase).toString();
    } catch (e) { log("cfiForOffset err: " + (e && e.message)); return null; }
  }

  function clearSearchMark() {
    if (searchMarkCfi && rendition) {
      try { rendition.annotations.remove(searchMarkCfi, "highlight"); } catch (e) {}
    }
    searchMarkCfi = null;
  }

  async function jumpToResult(r) {
    if (!rendition) return;
    var cfi = await cfiForOffset(r.i, r.off, r.hit.length);
    log("jump cfi=" + (cfi || "null"));
    closeSearchDrawer();
    clearSearchMark();
    if (cfi) {
      rendition.display(cfi);
      /* 命中词临时高亮，帮助定位 */
      setTimeout(function () {
        try {
          rendition.annotations.highlight(cfi, { srch: 1 }, null, "srch", { fill: "#ff9500", "fill-opacity": "0.5", "mix-blend-mode": "multiply" });
          searchMarkCfi = cfi;
          log("srch mark injected");
        } catch (e) { log("srch mark err: " + e.message); }
      }, 500);
    } else {
      try { rendition.display(book.spine.items[r.i].href); } catch (e) {}
    }
  }

  function openSearchDrawer() {
    clearSearchMark();
    $("searchDrawer").classList.add("open");
    $("searchMask").classList.remove("hidden");
    setTimeout(function () { try { $("searchInput").focus(); } catch (e) {} }, 250);
  }
  function closeSearchDrawer() {
    $("searchDrawer").classList.remove("open");
    $("searchMask").classList.add("hidden");
  }

  async function openBook(id) {
    var rec;
    /* 外部书（shell 解包）：按 OPF 文件 URL 打开，绕开 JSZip */
    var ext = null;
    for (var i = 0; i < EXT_BOOKS.length; i++) {
      if (EXT_BOOKS[i].id === id) { ext = EXT_BOOKS[i]; break; }
    }
    if (ext) {
      var p = extProgress(id);
      rec = {
        id: id, ext: true,
        title: ext.title, author: ext.author,
        data: null, opf: ext.opf,
        cfi: p.cfi || null,
        percent: p.percent || 0,
        updatedAt: ext.addedAt || 0
      };
      log("openBook external -> " + rec.title);
    } else {
      try { rec = await db.get(id); } catch (e) {}
      log("openBook db.get -> " + (rec ? rec.title : "null"));
    }
    if (!rec) { toast("找不到这本书"); return; }
    current = rec;
    showReader(rec.title);
    try {
      /* 外部书传 OPF 文件 URL（按文件逐个读取）；本地书传 ArrayBuffer */
      book = ePub(rec.ext ? rec.opf : rec.data);
      log("ePub() created");
      rendition = book.renderTo($("stage"), {
        width: "100%", height: "100%",
        flow: "paginated",
        spread: window.matchMedia("(min-width: 860px)").matches ? "auto" : "none",
        allowScriptedContent: false
      });
      log("renderTo done");
      window.__bk = book; /* 调试用 */
      window.__rd = rendition; /* 调试用 */
      rendition.hooks.content.register(function (contents) {
        try {
          var doc = contents && (contents.document || (contents.contents && contents.contents.ownerDocument));
          if (doc) fixImagesInDoc(doc, book);
        } catch (e) {}
      });
      Object.keys(THEMES).forEach(function (name) {
        rendition.themes.register(name, THEMES[name]);
      });
      applyTheme(prefs.get("theme", "light"));
      applyFontSize(parseInt(prefs.get("fontSize", "100"), 10) || 100);
      rendition.on("relocated", onRelocated);
      log("display start, cfi=" + (rec.cfi || "none"));
      try { await rendition.display(rec.cfi || undefined); }
      catch (e) { await rendition.display(); }
      log("display resolved");
      $("loading").classList.add("hidden");
      book.loaded.navigation.then(function (nav) { renderTOC(nav.toc || []); }).catch(function () {});
      applyAllHls();
      startSelPoll();
    } catch (e) {
      console.error(e);
      log("openBook ERROR: " + (e && e.message));
      toast("打开失败，文件可能已损坏");
      showLibrary();
    }
  }

  function onRelocated(loc) {
    if (!current) return;
    log("relocated idx=" + (loc && loc.start && loc.start.index));
    /* 轻量进度：按 spine 章节序号计算，避免 locations.generate 阻塞大书 */
    var idx = loc && loc.start && typeof loc.start.index === "number" ? loc.start.index : null;
    var total = book && book.spine && book.spine.items ? book.spine.items.length : 0;
    var pct = null;
    if (idx != null && total > 1) pct = idx / (total - 1);
    else if (idx != null && total === 1) pct = 1;
    if (loc && loc.start && loc.start.cfi) current.cfi = loc.start.cfi;
    if (pct != null) current.percent = Math.round(pct * 100);
    current.updatedAt = Date.now();
    var label = pct != null ? "已读 " + Math.round(pct * 100) + "%" : "阅读中";
    $("progressText").textContent = label;
    $("panelProgress").textContent = label;
    $("progressBar").style.width = (pct != null ? Math.round(pct * 100) : 0) + "%";
    /* 渲染稳定后扫描一次书内图片，替换 SVG 封面等未改写的资源 */
    setTimeout(sweepBookImages, 300);
    if (saveTimer) clearTimeout(saveTimer);
    saveTimer = setTimeout(saveCurrentNow, 800);
  }

  function saveCurrentNow() {
    saveTimer = null;
    if (!current) return;
    if (current.ext) {
      prefs.set("ext." + current.id, JSON.stringify({ cfi: current.cfi, percent: current.percent }));
    } else {
      db.put(current).catch(function () {});
    }
  }

  /* ---------- 目录 ---------- */
  function renderTOC(toc) {
    var root = $("tocList");
    root.innerHTML = "";
    function build(items) {
      var ol = document.createElement("ol");
      items.forEach(function (it) {
        var li = document.createElement("li");
        var a = document.createElement("a");
        a.textContent = (it.label || "").trim() || it.href;
        a.addEventListener("click", function () {
          if (rendition) rendition.display(it.href);
          closeToc();
        });
        li.appendChild(a);
        if (it.subitems && it.subitems.length) li.appendChild(build(it.subitems));
        ol.appendChild(li);
      });
      return ol;
    }
    root.appendChild(build(toc));
  }

  /* ---------- 首次运行：内置示例图书 ---------- */
  async function ensureSample() {
    try {
      var n = await db.count();
      if (n > 0 || EXT_BOOKS.length > 0) return;
      var b64 = window.SAMPLE_EPUB_B64;
      if (!b64) return;
      var bin = atob(b64);
      var bytes = new Uint8Array(bin.length);
      for (var i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
      await addBook(bytes.buffer, "慢读.epub");
    } catch (e) { console.warn("示例图书载入失败", e); }
  }

  /* ---------- 事件绑定 ---------- */
  function wire() {
    window.__importFile = importFile; /* 调试用 */
    $("importBtn").addEventListener("click", function () { $("fileInput").click(); });
    $("fileInput").addEventListener("change", function (e) {
      var files = Array.prototype.slice.call(e.target.files || []);
      files.forEach(function (f) { importFile(f); });
      e.target.value = "";
    });
    $("libThemeBtn").addEventListener("click", function () {
      var order = ["light", "sepia", "dark"];
      var cur = document.body.getAttribute("data-theme") || "light";
      applyTheme(order[(order.indexOf(cur) + 1) % order.length]);
    });
    $("backBtn").addEventListener("click", showLibrary);
    $("prevBtn").addEventListener("click", function () { pageTurn(-1); });
    $("nextBtn").addEventListener("click", function () { pageTurn(1); });
    $("tocBtn").addEventListener("click", function () {
      $("tocDrawer").classList.add("open"); $("tocMask").classList.remove("hidden");
    });
    $("tocClose").addEventListener("click", closeToc);
    $("tocMask").addEventListener("click", closeToc);
    $("noteBtn").addEventListener("click", openNoteDrawer);
    $("noteClose").addEventListener("click", closeNoteDrawer);
    $("noteMask").addEventListener("click", closeNoteDrawer);
    $("noteExportBtn").addEventListener("click", function (e) {
      e.stopPropagation();
      openExportSheet();
    });
    $("exportMask").addEventListener("click", closeExportSheet);
    $("expCopyBtn").addEventListener("click", function () { copyText($("expText").value); });
    $("expDlBtn").addEventListener("click", downloadMd);
    /* 书架排序/视图 */
    $("libSheetBtn").addEventListener("click", function () {
      syncLibSheet();
      $("libSheet").classList.add("open");
      $("libSheetMask").classList.remove("hidden");
    });
    $("libSheetMask").addEventListener("click", function () {
      $("libSheet").classList.remove("open");
      $("libSheetMask").classList.add("hidden");
    });
    Array.prototype.forEach.call(document.querySelectorAll("#sortOpts .opt"), function (o) {
      o.addEventListener("click", function () {
        prefs.set("libSort", o.getAttribute("data-sort"));
        syncLibSheet();
        renderLibrary();
      });
    });
    Array.prototype.forEach.call(document.querySelectorAll("#viewOpts .opt"), function (o) {
      o.addEventListener("click", function () {
        prefs.set("libView", o.getAttribute("data-view"));
        syncLibSheet();
        renderLibrary();
      });
    });
    /* 搜索 */
    $("searchBtn").addEventListener("click", openSearchDrawer);
    $("searchClose").addEventListener("click", closeSearchDrawer);
    $("searchMask").addEventListener("click", closeSearchDrawer);
    var searchTimer = null;
    $("searchInput").addEventListener("input", function (e) {
      clearTimeout(searchTimer);
      var q = e.target.value.trim();
      searchTimer = setTimeout(function () { runSearch(q); }, 350);
    });
    /* 高亮弹窗 */
    Array.prototype.forEach.call(document.querySelectorAll(".hl-dot"), function (dot) {
      dot.addEventListener("click", function () {
        var color = dot.getAttribute("data-color");
        if (!$("hlEditor").classList.contains("hidden")) {
          editorColor = color; /* 编辑器开着：只选色 */
          markActiveDots(color);
          return;
        }
        if (editingHl) { changeHl(editingHl, color, null); hideHlPop(); editingHl = null; toast("已更新"); return; }
        if (pendingSel) applyHl(color, "");
      });
    });
    $("hlNoteBtn").addEventListener("click", function () {
      editorColor = editingHl ? editingHl.color : "yellow";
      markActiveDots(editorColor);
      $("hlText").value = editingHl ? (editingHl.note || "") : "";
      $("hlEditor").classList.remove("hidden");
      $("hlRemoveBtn").classList.toggle("hidden", !editingHl);
      try { setTimeout(function () { $("hlText").focus(); }, 50); } catch (e) {}
      positionHlPop(pendingSel);
    });
    $("hlCopyBtn").addEventListener("click", function () {
      copyText(pendingSel ? pendingSel.text : "");
    });
    $("hlRemoveBtn").addEventListener("click", function () {
      if (editingHl) { removeHlById(editingHl.id); editingHl = null; hideHlPop(); toast("已移除高亮"); }
    });
    $("hlSaveBtn").addEventListener("click", function () {
      var note = $("hlText").value.trim();
      if (editingHl) {
        changeHl(editingHl, editorColor, note);
        editingHl = null;
        hideHlPop();
        toast("已保存");
      } else if (pendingSel) {
        applyHl(editorColor, note);
      }
    });
    $("hlCancelBtn").addEventListener("click", function () {
      $("hlEditor").classList.add("hidden");
      if (!pendingSel && !editingHl) hideHlPop();
    });
    $("styleBtn").addEventListener("click", function () {
      $("stylePanel").classList.add("open"); $("styleMask").classList.remove("hidden");
    });
    $("styleMask").addEventListener("click", closeStyle);
    $("fontMinus").addEventListener("click", function () {
      applyFontSize(parseInt($("fontVal").textContent, 10) - 10);
    });
    $("fontPlus").addEventListener("click", function () {
      applyFontSize(parseInt($("fontVal").textContent, 10) + 10);
    });
    Array.prototype.forEach.call(document.querySelectorAll(".theme-chip"), function (chip) {
      chip.addEventListener("click", function () { applyTheme(chip.getAttribute("data-theme")); });
    });
    $("deleteBookBtn").addEventListener("click", async function () {
      if (!current) return;
      if (!confirm("从书架移除《" + current.title + "》？")) return;
      var id = current.id, isExt = !!current.ext;
      current = null;
      if (isExt) {
        var hidden = extHidden();
        if (hidden.indexOf(id) < 0) hidden.push(id);
        prefs.set("extHidden", JSON.stringify(hidden));
        showLibrary();
      } else {
        await db.del(id);
        showLibrary();
      }
    });
    document.addEventListener("keydown", function (e) {
      if ($("readerView").classList.contains("hidden")) return;
      if (e.key === "ArrowLeft") pageTurn(-1);
      if (e.key === "ArrowRight") pageTurn(1);
    });
    document.addEventListener("dragover", function (e) { e.preventDefault(); });
    document.addEventListener("drop", function (e) {
      e.preventDefault();
      var f = e.dataTransfer && e.dataTransfer.files && e.dataTransfer.files[0];
      if (f) importFile(f);
    });
    /* 触摸滑动翻页 */
    var tX = 0, tY = 0, tT = 0;
    var wrap = $("stageWrap");
    wrap.addEventListener("touchstart", function (e) {
      tX = e.touches[0].clientX; tY = e.touches[0].clientY; tT = Date.now();
    }, { passive: true });
    wrap.addEventListener("touchend", function (e) {
      var dx = e.changedTouches[0].clientX - tX;
      var dy = e.changedTouches[0].clientY - tY;
      if (Date.now() - tT < 600 && Math.abs(dx) > 48 && Math.abs(dx) > Math.abs(dy) * 1.5) {
        pageTurn(dx < 0 ? 1 : -1);
      }
    }, { passive: true });
    /* 视口变化时重排 */
    var resizeTimer = null;
    window.addEventListener("resize", function () {
      clearTimeout(resizeTimer);
      resizeTimer = setTimeout(function () {
        if (rendition) { try { rendition.resize("100%", "100%"); } catch (e) {} }
      }, 300);
    });
  }

  /* ---------- 启动 ---------- */
  function init() {
    applyTheme(prefs.get("theme", "light"));
    applyFontSize(parseInt(prefs.get("fontSize", "100"), 10) || 100);
    wire();
    loadExternalBooks()
      .then(function () { return renderLibrary(); })
      .then(ensureSample)
      .catch(console.error);
  }
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", init);
  else init();
})();
