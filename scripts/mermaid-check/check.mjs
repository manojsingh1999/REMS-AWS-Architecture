// Usage: (cd scripts/mermaid-check && npm install && node check.mjs ../..)
import { JSDOM } from 'jsdom';
import fs from 'fs';
import path from 'path';
const dom = new JSDOM('<!doctype html><html><body></body></html>');
globalThis.window = dom.window; globalThis.document = dom.window.document;
globalThis.DOMParser = dom.window.DOMParser; globalThis.Element = dom.window.Element;
const mermaid = (await import('mermaid')).default;
mermaid.initialize({ startOnLoad: false });
const root = process.argv[2];
function walk(d){ return fs.readdirSync(d,{withFileTypes:true}).flatMap(e=> e.isDirectory()? (e.name.startsWith('.')?[]:walk(path.join(d,e.name))) : e.name.endsWith('.md')?[path.join(d,e.name)]:[]); }
let ok=0, bad=0;
for (const f of walk(root)) {
  const s = fs.readFileSync(f,'utf8');
  const re = /```mermaid\n([\s\S]*?)```/g; let m; let i=0;
  while ((m = re.exec(s))) {
    i++;
    try { await mermaid.parse(m[1]); ok++; }
    catch (e) { bad++; console.log(`FAIL ${path.relative(root,f)} #${i}: ${String(e.message||e).split('\n').slice(0,3).join(' | ')}`); }
  }
}
console.log(`mermaid diagrams: ${ok} ok, ${bad} failed`);
process.exit(bad?1:0);
