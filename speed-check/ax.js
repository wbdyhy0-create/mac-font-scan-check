// Drives a Mac program through the accessibility tree of its window (osascript -l JavaScript ax.js <process> <command> [pattern]).
//   windows          how many windows the process has
//   front            brings it to the front
//   bounds           puts its first window at a known place and size
//   dump             every element of the first window: its role and its names
//   exists <regex>   whether an element whose name matches is there
//   click <regex>    presses the first element whose name matches
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
  const lines = [];
  let hit = null;
  let count = 0;
  const get = (el, prop) => {
    try {
      const v = el[prop]();
      return v === null || v === undefined ? '' : String(v);
    } catch (e) {
      return '';
    }
  };
  function walk(el, depth) {
    if (hit || depth > 30 || count > 8000) return;
    let kids;
    try { kids = el.uiElements(); } catch (e) { return; }
    for (let i = 0; i < kids.length && !hit; i++) {
      const k = kids[i];
      count++;
      const role = get(k, 'role');
      const names = [get(k, 'name'), get(k, 'description'), get(k, 'title')].filter(Boolean);
      if (cmd === 'dump') lines.push('  '.repeat(depth) + role + ' | ' + names.join(' / '));
      else if (pattern && names.some((s) => pattern.test(s))) { hit = { el: k, role: role, label: names.join(' / ') }; break; }
      walk(k, depth + 1);
    }
  }
  walk(win, 0);
  if (cmd === 'dump') return lines.join('\n');
  if (!hit) return 'NOT FOUND (' + count + ' elements looked at)';
  if (cmd === 'exists') return 'FOUND ' + hit.role + ' | ' + hit.label;
  if (cmd === 'click') {
    try {
      hit.el.actions.byName('AXPress').perform();
      return 'PRESSED ' + hit.role + ' | ' + hit.label;
    } catch (e) {
      try {
        hit.el.click();
        return 'CLICKED ' + hit.role + ' | ' + hit.label;
      } catch (e2) {
        return 'FOUND BUT NOT PRESSED: ' + hit.role + ' | ' + hit.label + ' | ' + e2;
      }
    }
  }
  return 'unknown command';
}
