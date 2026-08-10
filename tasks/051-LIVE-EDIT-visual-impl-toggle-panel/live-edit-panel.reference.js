/*
 * Reference implementation for visual-impl.md's Live-Edit Mode section.
 *
 * Not shipped in plugin/ — the tech design's Out of Scope explicitly rules
 * out a new command/agent/library file; Live-Edit Mode lives as a prose +
 * snippet spec inside visual-impl.md, re-derived by the agent at run time
 * via playwright-cli eval. This file is a proven, bug-fixed working copy
 * kept for reference/reuse, verified live against a real production page
 * (dev-www.artec3d.com) during task 051's implementation.
 *
 * Usage: seed window.__liveEditRegistry with entries, then eval this IIFE.
 * Re-running it on an already-injected page just re-renders the panel
 * (see the window.__liveEditInjected guard).
 *
 * Fixed defect (task 051): rebuildStyleRules() originally scoped every
 * style-kind rule under a hardcoded `body.__live-edit-${id}` class and
 * toggled that class on <body> — this only ever worked when a candidate's
 * effective selector happened to be reachable via a body-descendant rule
 * written to match. Verified live: it silently no-op'd for real fixes
 * targeting an arbitrary element (a form field's box-shadow, in this
 * case). Fixed to build each rule directly from the entry's own
 * `sourceLocator.selector` — the real target, not a proxy.
 *
 * Verification status by kind:
 * - style: proven against a real production page (dev-www.artec3d.com) —
 *   the box-shadow/underline-removal fixes above.
 * - markup / logic: the dispatch above (window.__liveEditApplyKind) is
 *   proven; the two example population blocks near the bottom of this
 *   file (search "EXAMPLE: markup kind" / "EXAMPLE: logic kind") are the
 *   worked, watched-live examples from earlier in task 051's session, run
 *   only against a local scratch test page, not a production page. Wire
 *   up window.__liveEditMarkupPatches / window.__liveEditLogicHandlers
 *   the same way for a new markup/logic candidate.
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

  window.__liveEditExport = () => {
    const on = window.__liveEditRegistry.filter(f => window.__liveEditOn.has(f.id)).map(f => f.id);
    const off = window.__liveEditRegistry.filter(f => !window.__liveEditOn.has(f.id)).map(f => f.id);
    const text = 'ON: ' + (on.join(', ') || '(none)') + '\nOFF: ' + (off.join(', ') || '(none)');
    if (navigator.clipboard && navigator.clipboard.writeText) navigator.clipboard.writeText(text).catch(() => {});
    return text;
  };

  window.__liveEditLockInPayload = () => window.__liveEditRegistry
    .filter(f => window.__liveEditOn.has(f.id))
    .map(f => ({ id: f.id, apply: f.apply, sourceLocator: f.sourceLocator }));

  window.__liveEditCleanup = () => {
    document.getElementById('__live-edit-panel')?.remove();
    styleEl.remove();
    window.__liveEditInjected = false;
  };

  window.__liveEditRenderPanel = () => {
    let panel = document.getElementById('__live-edit-panel');
    if (!panel) {
      panel = document.createElement('div');
      panel.id = '__live-edit-panel';
      panel.style.cssText = 'position:fixed;top:20px;left:20px;z-index:999999;background:#222;color:#fff;font:11px/1.3 monospace;border-radius:5px;box-shadow:0 2px 8px rgba(0,0,0,.4);user-select:none;max-width:220px;';
      panel.innerHTML =
        '<div id="__live-edit-header" style="font-weight:bold;font-size:11px;padding:4px 8px;cursor:move;background:#000;border-radius:5px 5px 0 0;">⠿ Live-Edit</div>' +
        '<div style="padding:3px 6px;display:flex;gap:3px;border-bottom:1px solid #444;">' +
        '<button id="__live-edit-all-on" style="flex:1;cursor:pointer;font-size:10px;padding:2px 4px;">ON</button>' +
        '<button id="__live-edit-all-off" style="flex:1;cursor:pointer;font-size:10px;padding:2px 4px;">OFF</button>' +
        '<button id="__live-edit-invert" style="flex:1;cursor:pointer;font-size:10px;padding:2px 4px;">Inv</button></div>' +
        '<div id="__live-edit-rows" style="padding:3px 6px;max-height:220px;overflow:auto;"></div>' +
        '<div style="padding:4px 6px;border-top:1px solid #444;">' +
        '<button id="__live-edit-export-btn" style="width:100%;cursor:pointer;font-size:10px;padding:3px;">Export</button></div>';
      document.body.appendChild(panel);

      panel.querySelector('#__live-edit-all-on').onclick = () => window.__liveEditBulk('all-on');
      panel.querySelector('#__live-edit-all-off').onclick = () => window.__liveEditBulk('all-off');
      panel.querySelector('#__live-edit-invert').onclick = () => window.__liveEditBulk('invert');

      const exportBtn = panel.querySelector('#__live-edit-export-btn');
      exportBtn.onclick = () => {
        const text = window.__liveEditExport();
        const orig = exportBtn.textContent;
        exportBtn.textContent = 'Copied: ' + text.replace(/\n/g, ' / ');
        setTimeout(() => { exportBtn.textContent = orig; }, 2500);
      };

      const handle = panel.querySelector('#__live-edit-header');
      let dragging = false, offX = 0, offY = 0;
      handle.addEventListener('mousedown', (e) => {
        dragging = true;
        const r = panel.getBoundingClientRect();
        offX = e.clientX - r.left; offY = e.clientY - r.top;
        e.preventDefault();
      });
      document.addEventListener('mousemove', (e) => {
        if (!dragging) return;
        panel.style.left = (e.clientX - offX) + 'px';
        panel.style.top = (e.clientY - offY) + 'px';
      });
      document.addEventListener('mouseup', () => { dragging = false; });
    }

    const rows = document.getElementById('__live-edit-rows');
    rows.innerHTML = window.__liveEditRegistry.map(f => {
      const isOn = window.__liveEditOn.has(f.id);
      return '<label data-fix-id="' + f.id + '" style="display:flex;align-items:flex-start;gap:4px;padding:2px 4px;border-radius:3px;cursor:pointer;background:' +
        (isOn ? '#2d5a2d' : 'transparent') + ';"><input type="checkbox" style="margin-top:2px;" ' + (isOn ? 'checked' : '') +
        ' data-fix-id="' + f.id + '"><span>' + f.label + '</span></label>';
    }).join('');
    rows.querySelectorAll('input[type=checkbox]').forEach(cb => {
      cb.addEventListener('change', (e) => window.__liveEditToggle(e.target.dataset.fixId));
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
 * `apply` is literal replacement content (per FR-5's no-re-judgment
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
 * of two functions the one installed delegator calls, so the "attach/
 * detach" language in visual-impl.md's mechanism table can be either a
 * literal listener swap or (as here) a delegator-and-swapped-target,
 * whichever fits the candidate's actual behavior.
 */

