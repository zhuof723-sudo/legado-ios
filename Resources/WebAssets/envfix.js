/* 纸阅 —— WebView 环境补丁（必须在 epub.js 之前加载！）
 *
 * 本应用运行在 minis:// 自定义协议的 WKWebView 里，有三个与标准浏览器不同的行为，
 * epub.js 依赖它们，必须全部兜底，否则渲染管线会随机卡死：
 *
 * 1. requestAnimationFrame 在页面被遮挡/后台时长期不触发。
 *    epub.js 在模块加载时就把 window.requestAnimationFrame 抓进局部变量
 *    （var o = window.requestAnimationFrame || ...），
 *    所以补丁必须赶在它加载前替换掉 window 上的引用。
 *    —— 用 16ms 定时器兜底，真实 rAF 先到则优先。
 *
 * 2. 无 src 的 iframe：contentDocument 能拿到，但 load 事件长期不触发。
 *    epub.js 等不到 load 就不会往 iframe 里写内容。
 *    —— 创建时显式设置 src="about:blank" 可让 load 立即触发。
 *
 * 3. 后台状态下即使设置了 src，load 也可能仍然不触发（事件派发被挂起）。
 *    —— appendChild 后 150ms 仍未收到 load，且文档已就绪时，
 *       派发一个合成 load 事件并把 .onload 置空防止真实事件晚到重复执行。
 */
(function () {
  "use strict";

  var LOG = window.__readerLog = [];
  window.__zyLog = function (m) {
    LOG.push((Date.now() % 1000000) + " " + m);
    if (LOG.length > 500) LOG.splice(0, LOG.length - 500);
  };
  var log = window.__zyLog;

  /* ===== 补丁一：requestAnimationFrame / requestIdleCallback ===== */
  window.requestIdleCallback = window.requestIdleCallback || function (cb) {
    return setTimeout(function () {
      cb({ didTimeout: false, timeRemaining: function () { return 50; } });
    }, 1);
  };
  (function () {
    var orig = window.requestAnimationFrame ? window.requestAnimationFrame.bind(window) : null;
    window.requestAnimationFrame = function (cb) {
      var fired = false;
      var timer = setTimeout(function () {
        if (fired) return;
        fired = true;
        cb(Date.now());
      }, 16);
      if (orig) {
        return orig(function (ts) {
          if (fired) return;
          fired = true;
          clearTimeout(timer);
          cb(ts);
        });
      }
      return timer;
    };
    window.cancelAnimationFrame = window.cancelAnimationFrame || function (id) { clearTimeout(id); };
  })();

  /* ===== 补丁二：iframe 创建时显式 src ===== */
  var origCreate = document.createElement.bind(document);
  document.createElement = function (tag) {
    var el = origCreate(tag);
    if (String(tag).toLowerCase() === "iframe" && !el.getAttribute("src")) {
      el.setAttribute("src", "about:blank");
      el.addEventListener("load", function () { el.__zyLoaded = true; }, { capture: true });
      log("iframe created");
    }
    return el;
  };

  /* ===== 补丁三：合成 load 事件看门狗 ===== */
  function watchIframe(el) {
    if (el.__zyWatch) return;
    el.__zyWatch = true;
    setTimeout(function () {
      if (el.__zyLoaded) return;           /* 真实 load 已触发 */
      var doc = null;
      try { doc = el.contentDocument; } catch (e) { return; }
      if (!doc) return;                    /* 跨域或未就绪，放弃 */
      log("iframe synthetic load");
      el.dispatchEvent(new Event("load")); /* 同步执行 epub.js 的 onload 处理器 */
      el.onload = null;                    /* 防真实 load 晚到重复执行 */
    }, 150);
  }
  var origAppend = Node.prototype.appendChild;
  Node.prototype.appendChild = function (child) {
    var r = origAppend.call(this, child);
    if (child && child.tagName === "IFRAME") watchIframe(child);
    return r;
  };
  var origInsert = Node.prototype.insertBefore;
  Node.prototype.insertBefore = function (child, ref) {
    var r = origInsert.call(this, child, ref);
    if (child && child.tagName === "IFRAME") watchIframe(child);
    return r;
  };
})();
