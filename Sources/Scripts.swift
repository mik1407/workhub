import Foundation

/// Script iniettati nelle pagine.
/// - notificationShim gira nel mondo della pagina: sostituisce window.Notification
///   (WKWebView non la implementa) e inoltra le notifiche con un evento DOM.
/// - notificationBridge e badge girano in un mondo isolato: solo loro vedono
///   window.webkit.messageHandlers, la pagina no.
enum Scripts {

    static let notificationShim = #"""
    (() => {
      if (window.__hubShim) return;
      window.__hubShim = true;
      let seq = 0;
      const live = new Map();
      const send = (payload) => {
        document.dispatchEvent(new CustomEvent('__hub_notify', { detail: JSON.stringify(payload) }));
      };
      const fire = (target, type) => {
        const e = new Event(type, { cancelable: type === 'click' });
        target.dispatchEvent(e);
        const handler = target['on' + type];
        if (typeof handler === 'function') { try { handler.call(target, e); } catch (_) {} }
      };
      class HubNotification extends EventTarget {
        constructor(title, options) {
          super();
          const o = options || {};
          this.id = 'n' + Date.now() + '_' + (++seq);
          this.title = String(title || '');
          this.body = o.body ? String(o.body) : '';
          this.tag = o.tag ? String(o.tag) : '';
          this.data = o.data;
          this.icon = o.icon || '';
          this.silent = !!o.silent;
          this.onclick = null; this.onshow = null; this.onclose = null; this.onerror = null;
          live.set(this.id, this);
          if (live.size > 200) live.delete(live.keys().next().value);
          send({ action: 'show', id: this.id, title: this.title, body: this.body, tag: this.tag, silent: this.silent });
          setTimeout(() => fire(this, 'show'), 0);
        }
        close() {
          send({ action: 'close', id: this.id, tag: this.tag });
          live.delete(this.id);
          fire(this, 'close');
        }
        static get permission() { return 'granted'; }
        static get maxActions() { return 0; }
        static requestPermission(cb) {
          if (typeof cb === 'function') cb('granted');
          return Promise.resolve('granted');
        }
      }
      window.__hubNotifyClick = (id) => {
        window.focus();
        const n = live.get(id);
        if (n) fire(n, 'click');
      };
      Object.defineProperty(window, 'Notification', { value: HubNotification, writable: true, configurable: true });
      if (window.ServiceWorkerRegistration && ServiceWorkerRegistration.prototype) {
        ServiceWorkerRegistration.prototype.showNotification = function (title, options) {
          new HubNotification(title, options);
          return Promise.resolve();
        };
        ServiceWorkerRegistration.prototype.getNotifications = function () { return Promise.resolve([]); };
      }
      if (navigator.permissions && navigator.permissions.query) {
        const query = navigator.permissions.query.bind(navigator.permissions);
        navigator.permissions.query = (desc) => {
          if (desc && desc.name === 'notifications') {
            return Promise.resolve({ state: 'granted', status: 'granted', onchange: null,
                                     addEventListener() {}, removeEventListener() {} });
          }
          return query(desc);
        };
      }
    })();
    """#

    static let notificationBridge = #"""
    (() => {
      if (window.__hubBridge) return;
      window.__hubBridge = true;
      document.addEventListener('__hub_notify', (e) => {
        try { window.webkit.messageHandlers.hubNotify.postMessage(String(e.detail)); } catch (_) {}
      }, true);
    })();
    """#

    private static let badgeTemplate = #"""
    (() => {
      if (window.__hubBadge) return;
      window.__hubBadge = true;
      const MODE = '__MODE__';
      let last = '';
      let gmailCount = 0;
      const titleCount = () => {
        const m = (document.title || '').match(/\((\d+)\)/);
        return m ? parseInt(m[1], 10) : null;
      };
      const sumBadges = (selector) => Array.from(document.querySelectorAll(selector)).reduce((acc, el) => {
        const n = parseInt((el.textContent || '').replace(/\D/g, ''), 10);
        return acc + (isNaN(n) ? 1 : n);
      }, 0);
      const read = () => {
        if (MODE === 'gmail') {
          const n = titleCount();
          const hash = location.hash || '';
          if (n !== null) gmailCount = n;
          else if (hash === '' || hash === '#inbox') gmailCount = 0;
          return { count: gmailCount, dot: false };
        }
        if (MODE === 'slack') {
          let count = sumBadges('.p-channel_sidebar__badge');
          if (count === 0) count = sumBadges('.c-mention_badge');
          const unread = document.querySelectorAll(
            '.p-channel_sidebar__channel--unread:not(.p-channel_sidebar__channel--muted)').length > 0;
          const title = document.title || '';
          return { count: Math.max(count, titleCount() || 0), dot: unread || /^\s*[*!]/.test(title) };
        }
        return { count: titleCount() || 0, dot: false };
      };
      const tick = () => {
        let r;
        try { r = read(); } catch (_) { return; }
        const key = r.count + '|' + r.dot;
        if (key === last) return;
        last = key;
        try { window.webkit.messageHandlers.hubBadge.postMessage({ count: r.count, dot: r.dot }); } catch (_) {}
      };
      tick();
      setInterval(tick, 2000);
    })();
    """#

    static func badge(_ mode: BadgeMode) -> String? {
        let name: String
        switch mode {
        case .none: return nil
        case .title: name = "title"
        case .gmail: name = "gmail"
        case .slack: name = "slack"
        }
        return badgeTemplate.replacingOccurrences(of: "__MODE__", with: name)
    }

    /// Restituisce (come JSON) gli URL delle icone della pagina, dal migliore al peggiore.
    static let faviconCandidates = #"""
    (() => {
      const selector = 'link[rel~="icon"], link[rel~="apple-touch-icon"], link[rel~="apple-touch-icon-precomposed"]';
      const score = (l) => {
        const rel = (l.getAttribute('rel') || '').toLowerCase();
        const sizes = (l.getAttribute('sizes') || '').toLowerCase();
        const href = l.href || '';
        let s = parseInt(sizes.split('x')[0], 10) || 0;
        if (rel.includes('apple-touch-icon')) s += 500;
        if (/\.svg(\?|#|$)/i.test(href) || (l.type || '').includes('svg')) s -= 10000;
        return s;
      };
      const links = Array.from(document.querySelectorAll(selector))
        .filter((l) => l.href && !l.href.startsWith('data:'));
      links.sort((a, b) => score(b) - score(a));
      const out = links.map((l) => l.href);
      out.push(location.origin + '/apple-touch-icon.png', location.origin + '/favicon.ico');
      return JSON.stringify(Array.from(new Set(out)));
    })();
    """#
}
