// Drives a Mac program through the accessibility tree of its window (osascript -l JavaScript ax.js <process> <command> [pattern]).
//   windows           how many windows the process has
//   front             brings it to the front
//   bounds            puts its first window at a known place and size
//   dump              every element of the first window: its role and its names (stops after four minutes)
//   exists <regex>    whether an element whose name matches is there
//   click <regex>     presses the first element whose name matches
//   rexists / rclick  the same, looking from the end of the window's content first (a window that opened last stands there)
function run(argv) {
  const procName = argv[0];
  const cmd = argv[1];
  const pattern = argv[2] ? new RegExp(argv[2], 'i') : null;
  const se = Application('System Events');
  const proc = se.processes.byName(procName);
  if (cmd === 'windows') return String(proc.windows.length);
  if (cmd === 'front') { proc.frontmost = true; return 'ok'; }
  if (cmd === 'bounds') {
    const w = proc.windows[0];
    w.position = [0, 30];
    w.size = [1600, 950];
    return JSON.stringify({ position: w.position(), size: w.size() });
  }
  const win = proc.windows[0];
  const reversed = cmd === 'rexists' || cmd === 'rclick';
  const dump = cmd === 'dump';
  const press = cmd === 'click' || cmd === 'rclick';
  const started = Date.now();
  const limit = dump ? 240000 : 150000;
  const lines = [];
  let hit = null;
  let count = 0;
  let late = false;
  const get = (el, prop) => {
    try {
      const v = el[prop]();
      return v === null || v === undefined ? '' : String(v);
    } catch (e) {
      return '';
    }
  };
  function walk(el, depth) {
    if (hit || late || depth > 40) return;
    if (Date.now() - started > limit) { late = true; return; }
    let kids;
    try { kids = el.uiElements(); } catch (e) { return; }
    const order = kids.map((k, i) => i);
    if (reversed) order.reverse();
    for (const i of order) {
      if (hit || late) return;
      const k = kids[i];
      count++;
      const name = get(k, 'name');
      if (dump) {
        lines.push('  '.repeat(depth) + get(k, 'role') + ' | ' + name);
      } else if (pattern && name && pattern.test(name)) {
        hit = { el: k, label: name };
        return;
      } else if (pattern && !name) {
        // (a control with no name of its own may be named by its description)
        const desc = get(k, 'description');
        if (desc && pattern.test(desc)) { hit = { el: k, label: desc }; return; }
      }
      walk(k, depth + 1);
    }
  }
  walk(win, 0);
  const took = ((Date.now() - started) / 1000).toFixed(1) + ' s';
  if (dump) return lines.join('\n') + (late ? '\n(stopped: out of time)' : '');
  if (!hit) return 'NOT FOUND (' + count + ' elements looked at, ' + took + (late ? ', out of time' : '') + ')';
  if (!press) return 'FOUND ' + hit.label + ' (' + count + ' elements, ' + took + ')';
  try {
    hit.el.actions.byName('AXPress').perform();
    return 'PRESSED ' + hit.label + ' (' + count + ' elements, ' + took + ')';
  } catch (e) {
    try {
      hit.el.click();
      return 'CLICKED ' + hit.label + ' (' + count + ' elements, ' + took + ')';
    } catch (e2) {
      return 'FOUND BUT NOT PRESSED: ' + hit.label + ' | ' + e2;
    }
  }
}
