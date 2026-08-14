/*
 * Live-Edit panel — the shipped implementation of visual-impl.md's
 * Live-Edit Mode. The command loads and evals THIS file (via
 * playwright-cli `run-code` + `addScriptTag`, or `eval`); it does not
 * re-derive the panel from prose. This file is the single source of
 * truth for the panel.
 *
 * ── Embedded spec (principles this file is built to; keep reproducible) ──
 *
 * PURPOSE. Inject a floating panel into a live-rendered page so a human
 * can toggle candidate changes ON/OFF and watch them apply live, then
 * export/lock-in the chosen set as permanent source edits. The panel is
 * the human's judgment surface; the code that ships is authored, diffed,
 * and reviewed through the normal git flow — never auto-written blind.
 *
 * DATA MODEL. window.__liveEditRegistry is an array of entries:
 *   { id, label, kind, apply, sourceLocator: { file, selector } }
 *   - kind ∈ style | markup | logic — decides ONLY the live-apply
 *     mechanism, never the write-back target.
 *   - apply is LITERAL replacement source text for its kind (CSS text /
 *     DOM-patch / handler body) — never a behavioral description. This is
 *     the no-re-judgment guarantee: lock-in writes `apply` verbatim.
 *   - sourceLocator names a place in the project's OWN source. One
 *     write-back target, reached the same way for every kind.
 *
 * LIVE-APPLY MECHANISMS (per kind):
 *   - style : one injected <style>, rebuilt from all ON style entries as
 *     `${sourceLocator.selector} { ${apply} }` — the entry's REAL target
 *     selector, not a body-wide proxy class.
 *   - markup: per-entry DOM patch fn + inverse/original snapshot
 *     (window.__liveEditMarkupPatches[id] = {apply, revert}).
 *   - logic : injected fn/handler toggled on/off
 *     (window.__liveEditLogicHandlers[id](turningOn)).
 *
 * SPECIFICITY (verified bug, task 051). A plain `.class { ... }` rule can
 * LOSE the cascade to the page's own higher-specificity or !important
 * rules — the rule injects but computes to no visible change. A style
 * candidate targeting an already-styled element must raise its own
 * specificity (add !important, or a more specific selector) in `apply`.
 * Injecting a rule is not proof it applied — verify the COMPUTED style.
 *
 * PANEL UX REQUIREMENTS:
 *   - Explicit per-row ON/OFF state (a labelled badge, not background
 *     alone) + a header count "N / M on", so state is unmistakable.
 *   - Labels on one line (white-space:nowrap); panel auto-widens to
 *     content and is user-resizable (resize:horizontal) for long labels.
 *   - Label text is selectable (user-select:text); toggling happens ONLY
 *     via the badge, so selecting/copying a label never toggles it.
 *   - Draggable by its header. No persistence across page loads.
 *
 * EXPORT / LOCK-IN (the point — permanent backend changes):
 *   - Export produces the full CHANGE SET for every ON entry (all
 *     sourceLocator fields spread + id + label + kind + apply), not just
 *     an id list — a maintainer or the agent can turn it straight into a
 *     source edit. Extra fields (component, state, breakpoint, …) added
 *     to sourceLocator by the caller survive lock-in verbatim. Copied to
 *     clipboard and returned.
 *   - Lock-in (window.__liveEditLockInPayload) returns the same ON change
 *     set for the agent to WRITE into real source, then cleanup removes
 *     all injected scaffolding. If a sourceLocator no longer resolves,
 *     halt before writing anything and report — error always stops.
 *
 * NAVIGATION SURVIVAL (FR-7, verified 2026-08-14). The panel must survive
 * a USER-driven navigation (the human clicks a link), not only an
 * agent-triggered one, AND an SPA re-render that replaces document.body.
 * Four mechanisms, all in-page (no controller re-injection — that path is
 * racy: the SPA paints before Playwright's framenavigated event arrives):
 *   - Register THIS file via Playwright `page.addInitScript`, so the
 *     browser re-runs it on EVERY hard document load. (A one-shot
 *     `eval`/`addScriptTag` does NOT survive; addInitScript is required.)
 *   - All DOM work is DEFERRED to DOMContentLoaded. addInitScript runs at
 *     document-start when document.head/body are null; the original defect
 *     was `head.appendChild` throwing there, which also aborted the
 *     end-of-run state save and wiped the ON-set.
 *   - SPA client-side navigation: `history.pushState`/`replaceState` +
 *     `popstate` are hooked to re-boot the panel (no page load fires).
 *   - SPA body replacement: a MutationObserver on <body> re-appends the
 *     panel when the framework removes it (disconnect-before-reappend to
 *     avoid an infinite loop; guarded by panel id).
 * Registry + ON-state live in `localStorage` (NOT sessionStorage, which
 * Playwright storageState ignores). Persisted on the FIRST run after
 * load/seed and on each mutation; a re-run never blindly re-saves (that
 * was a second ON-set-wipe cause). Scope by kind: `style` fully survives
 * (CSS text is serializable). `markup`/`logic` rows reappear from
 * persisted metadata, but their live closures cannot be serialized — they
 * are re-seeded by re-running their seed blocks against the new page;
 * until then, toggling them is a no-op. `__liveEditCleanup()` clears the
 * localStorage keys so a post-lock-in load starts clean. This persistence
 * does NOT violate NFR-2, which scopes "nothing persisted" to
 * cross-session state and to durable SOURCE change (only lock-in writes).
 *
 * Verified live 2026-08-14 on a clean Playwright session against a real
 * client-side SPA (localhost Artec site): panel + ON-set + style survived
 * multiple real navigations (screenshot captured); MutationObserver
 * self-heal re-appended the panel after node removal. style kind incl. the
 * specificity fix. markup/logic dispatch proven; their example population
 * blocks (bottom of file) were run on a local scratch page only.
 */
(() => {
  // Version this script was shipped with. Keep in lockstep with the plugin
  // manifest (plugin/.claude-plugin/plugin.json) on every release. The panel
  // shows it in the title, and warns if the INSTALLED embo differs (the
  // caller passes the installed version as window.__liveEditInstalledVersion
  // at inject time). This catches the stale-script trap: a user tunes with an
  // old panel still live in the browser, upgrades embo, and the running
  // script silently no longer matches the installed one.
  const PANEL_VERSION = '0.2.5';

  // Persisted state (localStorage — survives navigation AND is captured by
  // Playwright storageState, unlike sessionStorage). One namespaced key per
  // slice. Registry may be pre-seeded on `window` by the caller before this
  // runs (fresh session); otherwise it is restored from storage.
  const REG_KEY = '__liveEditRegistry', ON_KEY = '__liveEditOn';
  const loadReg = () => { try { return JSON.parse(localStorage.getItem(REG_KEY)) || []; } catch { return []; } };
  const loadOn = () => { try { return new Set(JSON.parse(localStorage.getItem(ON_KEY)) || []); } catch { return new Set(); } };
  const saveReg = () => { try { localStorage.setItem(REG_KEY, JSON.stringify(window.__liveEditRegistry || [])); } catch {} };
  const saveOn = () => { try { localStorage.setItem(ON_KEY, JSON.stringify([...window.__liveEditOn])); } catch {} };
  window.__liveEditPersist = () => { saveReg(); saveOn(); };

  // The functions below (toggle/bulk/export/lock-in/render) are (re)defined
  // on every run — cheap and keeps them current. The guard only protects the
  // one-time SETUP (history patch, observer) and initial state load. Callers
  // that re-inject after a navigation get a working API either way.
  const firstRun = !window.__liveEditSetup;

  // State load: safe at document-start (no DOM touched). On the very first
  // run, honor a caller-seeded registry; afterwards always trust storage so a
  // re-injection never clobbers persisted entries.
  if (firstRun) {
    if (!window.__liveEditRegistry) window.__liveEditRegistry = loadReg();
    if (!window.__liveEditOn) window.__liveEditOn = loadOn();
  }

  // Style tag is created lazily by ensureStyleEl() so NO DOM is touched at
  // document-start (where document.head is still null — the original defect).
  function ensureStyleEl() {
    let el = document.getElementById('__live-edit-style');
    if (!el && document.head) {
      el = document.createElement('style');
      el.id = '__live-edit-style';
      document.head.appendChild(el);
    }
    return el;
  }

  function rebuildStyleRules() {
    const el = ensureStyleEl();
    if (!el) return;
    const on = window.__liveEditRegistry.filter(f => window.__liveEditOn.has(f.id) && f.kind === 'style');
    el.textContent = on.map(f => `${f.sourceLocator.selector} { ${f.apply} }`).join('\n');
  }

  window.__liveEditApplyKind = (entry, turningOn) => {
    if (entry.kind === 'style') { rebuildStyleRules(); return; }
    if (entry.kind === 'markup') {
      const patch = window.__liveEditMarkupPatches && window.__liveEditMarkupPatches[entry.id];
      if (patch) { turningOn ? patch.apply() : patch.revert(); }
      return;
    }
    if (entry.kind === 'logic') {
      if (window.__liveEditLogicHandlers && window.__liveEditLogicHandlers[entry.id]) {
        window.__liveEditLogicHandlers[entry.id](turningOn);
      }
    }
  };

  window.__liveEditToggle = (id) => {
    const entry = window.__liveEditRegistry.find(f => f.id === id);
    const turningOn = !window.__liveEditOn.has(id);
    turningOn ? window.__liveEditOn.add(id) : window.__liveEditOn.delete(id);
    window.__liveEditApplyKind(entry, turningOn);
    saveOn();
    window.__liveEditRenderPanel();
  };

  window.__liveEditBulk = (mode) => {
    window.__liveEditRegistry.forEach(f => {
      const isOn = window.__liveEditOn.has(f.id);
      const shouldBeOn = mode === 'all-on' ? true : mode === 'all-off' ? false : !isOn;
      if (shouldBeOn !== isOn) window.__liveEditToggle(f.id);
    });
  };

  // The ON change set: every ON entry's REAL change (file + selector +
  // literal apply) — what a maintainer or the agent turns into source.
  window.__liveEditChangeSet = () => window.__liveEditRegistry
    .filter(f => window.__liveEditOn.has(f.id))
    .map(f => ({ ...f.sourceLocator, id: f.id, label: f.label, kind: f.kind, apply: f.apply }));

  // Human-readable export of the full change set (not just ids).
  window.__liveEditExport = () => {
    const cs = window.__liveEditChangeSet();
    const text = cs.length
      ? cs.map(c => `# ${c.label} [${c.kind}]\n${c.file} — ${c.selector}\n    ${c.apply}`).join('\n\n')
      : '(no changes ON)';
    if (navigator.clipboard && navigator.clipboard.writeText) navigator.clipboard.writeText(text).catch(() => {});
    return text;
  };

  // Lock-in payload the agent WRITES into real source (same change set).
  window.__liveEditLockInPayload = () => window.__liveEditChangeSet();

  window.__liveEditCleanup = () => {
    document.getElementById('__live-edit-panel')?.remove();
    document.getElementById('__live-edit-style')?.remove();
    // Stop self-healing so the panel does not resurrect after cleanup.
    if (window.__liveEditObserver) { window.__liveEditObserver.disconnect(); window.__liveEditObserver = null; }
    window.__liveEditInjected = false;
    window.__liveEditSetup = false;
    // End persistence so a later load starts clean (the change set has
    // been locked into real source; nothing should re-apply).
    try { localStorage.removeItem(REG_KEY); localStorage.removeItem(ON_KEY); } catch {}
  };

  window.__liveEditRenderPanel = () => {
    // Persist the registry on every render so a mid-session add (caller
    // pushes to __liveEditRegistry, then re-renders) survives navigation.
    saveReg();
    if (!document.body) return; // deferred boot calls this again once body exists
    const reg = window.__liveEditRegistry, on = window.__liveEditOn;
    let p = document.getElementById('__live-edit-panel');
    if (!p) {
      p = document.createElement('div');
      p.id = '__live-edit-panel';
      p.style.cssText = 'position:fixed;top:20px;left:20px;z-index:999999;background:#1e1e24;color:#e8e8ea;font:13px/1.4 -apple-system,Segoe UI,Roboto,sans-serif;border-radius:10px;box-shadow:0 6px 24px rgba(0,0,0,.35);min-width:240px;width:max-content;max-width:520px;resize:horizontal;overflow:auto;';
      p.innerHTML =
        '<div id="__le-hd" style="display:flex;justify-content:space-between;align-items:center;font-weight:600;padding:8px 12px;cursor:move;background:#2a2a32;border-radius:10px 10px 0 0;user-select:none;"><span>Embo Live-Edit <span style="font-weight:400;font-size:11px;color:#9aa;">(v.' + PANEL_VERSION + ')</span></span><span id="__le-count" style="font-weight:500;font-size:11px;color:#9aa;"></span></div>' +
        '<div id="__le-stale" style="display:none;padding:6px 12px;background:#4a2f13;color:#ffd08a;font-size:11px;line-height:1.35;border-bottom:1px solid #38383f;"></div>' +
        '<div style="padding:6px 10px;display:flex;gap:6px;border-bottom:1px solid #38383f;">' +
        '<button id="__le-on" style="flex:1;cursor:pointer;font:12px sans-serif;padding:4px;border:0;border-radius:6px;background:#3a3a44;color:#e8e8ea;">All on</button>' +
        '<button id="__le-off" style="flex:1;cursor:pointer;font:12px sans-serif;padding:4px;border:0;border-radius:6px;background:#3a3a44;color:#e8e8ea;">All off</button>' +
        '<button id="__le-inv" style="flex:1;cursor:pointer;font:12px sans-serif;padding:4px;border:0;border-radius:6px;background:#3a3a44;color:#e8e8ea;">Invert</button></div>' +
        '<div id="__le-rows" style="padding:6px;max-height:320px;overflow:auto;"></div>' +
        '<div style="padding:8px 10px;border-top:1px solid #38383f;"><button id="__le-exp" style="width:100%;cursor:pointer;font:12px sans-serif;padding:6px;border:0;border-radius:6px;background:#2563eb;color:#fff;">Export</button></div>';
      document.body.appendChild(p);

      p.querySelector('#__le-on').onclick = () => window.__liveEditBulk('all-on');
      p.querySelector('#__le-off').onclick = () => window.__liveEditBulk('all-off');
      p.querySelector('#__le-inv').onclick = () => window.__liveEditBulk('invert');

      const eb = p.querySelector('#__le-exp');
      eb.onclick = () => { window.__liveEditExport(); const o = eb.textContent; eb.textContent = 'Copied change set'; setTimeout(() => { eb.textContent = o; }, 1800); };

      const h = p.querySelector('#__le-hd');
      let drag = false, ox = 0, oy = 0;
      h.addEventListener('mousedown', (e) => { drag = true; const r = p.getBoundingClientRect(); ox = e.clientX - r.left; oy = e.clientY - r.top; e.preventDefault(); });
      document.addEventListener('mousemove', (e) => { if (!drag) return; p.style.left = (e.clientX - ox) + 'px'; p.style.top = (e.clientY - oy) + 'px'; });
      document.addEventListener('mouseup', () => { drag = false; });
    }

    // Staleness check: if the caller told us the installed embo version and
    // it differs from the version baked into this running script, warn — the
    // user is tuning with an out-of-date panel (e.g. they upgraded embo after
    // injecting). Re-injecting from the current install clears it.
    const stale = p.querySelector('#__le-stale');
    if (stale) {
      const installed = window.__liveEditInstalledVersion;
      if (installed && installed !== PANEL_VERSION) {
        stale.textContent = '⚠ This panel is v' + PANEL_VERSION + ', but embo v' + installed + ' is installed. Re-inject the panel to update.';
        stale.style.display = 'block';
      } else {
        stale.style.display = 'none';
      }
    }

    const onCount = reg.filter(f => on.has(f.id)).length;
    p.querySelector('#__le-count').textContent = onCount + ' / ' + reg.length + ' on';

    const rows = p.querySelector('#__le-rows');
    rows.innerHTML = reg.map(f => {
      const isOn = on.has(f.id);
      return '<div style="display:flex;align-items:center;gap:8px;padding:5px 8px;margin:2px 0;border-radius:6px;background:' + (isOn ? '#14351f' : '#26262e') + ';">' +
        '<button data-fix-id="' + f.id + '" title="Toggle this change" style="flex:0 0 40px;cursor:pointer;text-align:center;font:600 10px sans-serif;padding:3px 0;border:0;border-radius:4px;background:' + (isOn ? '#22c55e' : '#55555f') + ';color:' + (isOn ? '#04210f' : '#c8c8ce') + ';">' + (isOn ? 'ON' : 'OFF') + '</button>' +
        '<span style="white-space:nowrap;user-select:text;cursor:text;">' + f.label + '</span></div>';
    }).join('');
    rows.querySelectorAll('button[data-fix-id]').forEach(btn => {
      btn.addEventListener('click', (e) => window.__liveEditToggle(e.currentTarget.dataset.fixId));
    });
  };

  // Build + apply everything that touches the DOM. Idempotent: safe to call
  // repeatedly (on load, after an SPA route change, after a body swap).
  window.__liveEditBoot = () => {
    if (!document.body) return;
    rebuildStyleRules();        // re-apply the ON style set
    window.__liveEditRenderPanel();
  };

  // Run boot now if the DOM is ready, else defer to DOMContentLoaded. This
  // is the fix for the original defect: addInitScript runs at document-start
  // when document.head/body are null, so DOM work MUST wait for the parse.
  const bootWhenReady = () => {
    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', () => window.__liveEditBoot(), { once: true });
    } else {
      window.__liveEditBoot();
    }
  };

  // Persist ONLY on the first run, right after state was loaded/seeded — this
  // captures a caller-seeded registry. On a re-run (firstRun false) window
  // state may be empty/stale, so re-saving here would overwrite good
  // persisted state with nothing (this was the ON-set-wipe defect). Mutations
  // (__liveEditToggle) persist themselves, so no data is lost by skipping.
  if (firstRun) { saveReg(); saveOn(); }

  // ── One-time self-healing setup (survives navigation without a controller) ──
  if (firstRun) {
    window.__liveEditSetup = true;
    window.__liveEditInjected = true;

    // (a) SPA client-side navigation: history.pushState/replaceState do not
    //     fire a page load, so hook them (+ popstate) to re-boot the panel.
    const hookHistory = (type) => {
      const orig = history[type];
      if (orig && !orig.__liveEditHooked) {
        const wrapped = function (...args) { const r = orig.apply(this, args); try { window.__liveEditBoot(); } catch {} return r; };
        wrapped.__liveEditHooked = true;
        history[type] = wrapped;
      }
    };
    hookHistory('pushState');
    hookHistory('replaceState');
    window.addEventListener('popstate', () => window.__liveEditBoot());

    // (b) SPA body replacement: a framework can remove/replace the panel
    //     node. Watch body and re-append when our panel disappears. Guard
    //     against the infinite loop (disconnect before re-append, reconnect
    //     after) and by panel id.
    const startObserving = () => {
      if (!document.body || window.__liveEditObserver) return;
      const obs = new MutationObserver(() => {
        if (!document.getElementById('__live-edit-panel')) {
          obs.disconnect();
          try { window.__liveEditBoot(); } finally { if (document.body) obs.observe(document.body, { childList: true }); }
        }
      });
      obs.observe(document.body, { childList: true });
      window.__liveEditObserver = obs;
    };
    if (document.body) startObserving();
    else document.addEventListener('DOMContentLoaded', startObserving, { once: true });
  }

  bootWhenReady();
  return firstRun ? 'injected' : 'already injected, re-rendered';
})();

/*
 * EXAMPLE: markup kind — verified locally (CTA button text swap), not
 * against a production page. Run AFTER the IIFE above and AFTER seeding
 * window.__liveEditRegistry with an entry of kind 'markup' whose id
 * matches the key used below (e.g. 'f2').
 *
 * (() => {
 *   const ctaEl = document.getElementById('cta');
 *   const originalText = ctaEl.textContent;
 *   window.__liveEditMarkupPatches = window.__liveEditMarkupPatches || {};
 *   window.__liveEditMarkupPatches['f2'] = {
 *     apply: () => { ctaEl.textContent = 'NEW CTA TEXT'; },
 *     revert: () => { ctaEl.textContent = originalText; },
 *   };
 * })();
 *
 * `apply` is literal replacement content (per the no-re-judgment
 * guarantee), captured as a closure over the original value so `revert`
 * is an exact original-value snapshot, not a guess.
 */

/*
 * EXAMPLE: logic kind — verified locally (swapping which of two
 * functions handles a click), not against a production page. Run AFTER
 * the IIFE above and AFTER seeding window.__liveEditRegistry with an
 * entry of kind 'logic' whose id matches the key used below (e.g. 'f3').
 *
 * (() => {
 *   const ctaEl = document.getElementById('cta');
 *   const oldHandler = () => { ctaEl.textContent = 'Clicked (old handler)'; };
 *   const newHandler = () => { ctaEl.textContent = 'Clicked (NEW handler)'; };
 *   window.__liveEditLogicState = window.__liveEditLogicState || {};
 *   window.__liveEditLogicState['f3'] = { current: oldHandler };
 *   ctaEl.removeEventListener('click', oldHandler);
 *   ctaEl.addEventListener('click', (e) => window.__liveEditLogicState['f3'].current(e));
 *   window.__liveEditLogicHandlers = window.__liveEditLogicHandlers || {};
 *   window.__liveEditLogicHandlers['f3'] = (turningOn) => {
 *     window.__liveEditLogicState['f3'].current = turningOn ? newHandler : oldHandler;
 *   };
 * })();
 *
 * Toggling never adds/removes the DOM listener itself — it swaps which
 * of two functions the one installed delegator calls.
 */
