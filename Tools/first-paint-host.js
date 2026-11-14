// The runtime's side of the first paint (Documentation/Architecture/FIRST_PAINT.md).
//
// A page built with SWIFTUIWEB_FIRST_PAINT=1 carries the first screen as markup inside `#embedded-app-root[data-first-paint]`
// and its layout rules in `<style id="first-paint-style">`. The markup is a picture: it has no handlers. The first commit
// replaces it, in the same task as the commit's own insertion (no frame is painted between), and a click or typing the
// person made on the picture meanwhile (recorded by the inline script of index.html) is replayed on the real elements once
// the screen is mounted.
export function takeFirstPaint(document, root) {
  if (!root?.hasAttribute('data-first-paint')) return null;
  const events = document.defaultView.__firstPaintEvents ?? [];
  let released = false;
  return {
    release() {
      if (released) return;
      released = true;
      document.getElementById('first-paint-style')?.remove();
      root.removeAttribute('data-first-paint');
      root.replaceChildren();
    },
    // After the commit that mounted (the runtime ignores events while it commits): in a microtask. A recorded event is replayed
    // only on the element it was made on: same place in the tree, same tag, same text.
    replay() {
      if (events.length) document.defaultView.queueMicrotask(() => this.run());
    },
    run() {
      const typed = new Map();
      for (const event of events.splice(0)) {
        if (event.type === 'input') { typed.set(event.path.join('/'), event); continue; }
        const target = this.find(event);
        if (target && (target.textContent || '').slice(0, 40) === event.text) target.click();
      }
      for (const event of typed.values()) {
        const target = this.find(event);
        if (!target) continue;
        target.value = event.value;
        target.dispatchEvent(new document.defaultView.Event('input', {bubbles: true}));
      }
    },
    find(event) {
      let element = root;
      for (const index of event.path) element = element?.children[index];
      return element && element.localName === event.tag ? element : null;
    },
  };
}
