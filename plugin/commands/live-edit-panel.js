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
 *   - Export produces the full CHANGE SET for every ON entry (file +
 *     selector + literal apply), not just an id list — a maintainer or
 *     the agent can turn it straight into a source edit. Copied to
 *     clipboard and returned.
 *   - Lock-in (window.__liveEditLockInPayload) returns the same ON change
 *     set for the agent to WRITE into real source, then cleanup removes
 *     all injected scaffolding. If a sourceLocator no longer resolves,
 *     halt before writing anything and report — error always stops.
 *
 * IDEMPOTENT RE-INJECTION. Re-running this file just re-renders from the
 * current registry (window.__liveEditInjected guard) — so re-injecting
 * after a real page navigation needs no extra machinery.
 *
 * Verified live against a real production page (dev-www.artec3d.com):
 * style kind (incl. the specificity fix). markup/logic dispatch proven;
 * their example population blocks (bottom of file) were run on a local
 * scratch page only.
 */
(() => {
  if (window.__liveEditInjected) { window.__liveEditRenderPanel(); return 'already injected, re-rendered'; }
  window.__liveEditInjected = true;
  window.__liveEditOn = new Set();

  const styleEl = document.createElement('style');
  styleEl.id = '__live-edit-style';
  document.head.appendChild(styleEl);

  function rebuildStyleRules() {
    const on = window.__liveEditRegistry.filter(f => window.__liveEditOn.has(f.id) && f.kind === 'style');
    styleEl.textContent = on.map(f => `${f.sourceLocator.selector} { ${f.apply} }`).join('\n');
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
    .map(f => ({ id: f.id, label: f.label, kind: f.kind, file: f.sourceLocator.file, selector: f.sourceLocator.selector, apply: f.apply }));

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
    styleEl.remove();
    window.__liveEditInjected = false;
  };

  window.__liveEditRenderPanel = () => {
    const reg = window.__liveEditRegistry, on = window.__liveEditOn;
    let p = document.getElementById('__live-edit-panel');
    if (!p) {
      p = document.createElement('div');
      p.id = '__live-edit-panel';
      p.style.cssText = 'position:fixed;top:20px;left:20px;z-index:999999;background:#1e1e24;color:#e8e8ea;font:13px/1.4 -apple-system,Segoe UI,Roboto,sans-serif;border-radius:10px;box-shadow:0 6px 24px rgba(0,0,0,.35);min-width:240px;width:max-content;max-width:520px;resize:horizontal;overflow:auto;';
      p.innerHTML =
        '<div id="__le-hd" style="display:flex;justify-content:space-between;align-items:center;font-weight:600;padding:8px 12px;cursor:move;background:#2a2a32;border-radius:10px 10px 0 0;user-select:none;"><span>Live-Edit</span><span id="__le-count" style="font-weight:500;font-size:11px;color:#9aa;"></span></div>' +
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

  window.__liveEditRenderPanel();
  return 'injected';
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
