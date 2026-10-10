// Checks every Omarchy binding against the key map model on this machine:
// it shows when its modifiers are held, and pressing its key (by keycode)
// lists it with the exact combination first. Run from the plugin folder:
//   d=$(mktemp -d); ./extended-keybindings-viewer > $d/records.txt; ./extended-keybindings-viewer keys > $d/layout.txt; node tests/audit.js $d
const fs=require('fs'), S=process.argv[2];
const M=new Function(fs.readFileSync('Model.js','utf8').replace('.pragma library','')+';return {parse,list,parseLayout,resolve,keyLabel}')();
// Keyboard.qml geometry names (ISO), copied logic
const names=(p,a,b)=>{const o=[];for(let i=a;i<=b;i++)o.push(p+(i<10?'0':'')+i);return o};
const drawn=['ESC',...names('FK',1,12),'PRSC','HOME','DELE','TLDE',...names('AE',1,12),'BKSP','TAB',...names('AD',1,12),'RTRN','CAPS',...names('AC',1,11),'BKSL','LFSH','LSGT',...names('AB',1,10),'RTSH','UP','LCTL','LWIN','LALT','SPCE','RALT','RWIN','COMP','RCTL','LEFT','DOWN','RGHT'];
const L=M.parseLayout(fs.readFileSync(S+'/layout.txt','utf8'));
const b=M.resolve(M.parse(fs.readFileSync(S+'/records.txt','utf8')),L,drawn,n=>n);
const same=(x,y)=>x.join('+')===y.join('+');
let fails=[], unlit=[];
for (const x of b) {
  const held=M.list(b,x.mods,'');
  if (!held.some(l=>l.bindings.includes(x))) fails.push('hold '+x.combo);
  if (x.keyId) {
    // the real press path: a key event's keycode → key name → lookup
    // mouse parts are pressed by button, not keycode
    const mouse=/^(BTN_|WHEEL_)/.test(x.keyId);
    const code=mouse ? null : Object.keys(L.codes).find(c=>L.codes[c]===x.keyId);
    if (!mouse && !code) { fails.push('no keycode for '+x.keyId+' ('+x.combo+')'); continue }
    const pr=M.list(b,x.mods,'',mouse ? x.keyId : L.codes[code]);
    if (!pr.length || !same(pr[0].mods,x.mods) || !pr.some(l=>l.bindings.includes(x))) fails.push('press '+x.combo+' ('+x.keyId+')');
  } else {
    unlit.push(x.combo+'  ['+x.key+']  '+x.desc);
    // only a key the layout has no keycode for may stay unresolved
    if (!/^XF86/i.test(x.key)) fails.push('unresolved '+x.combo+' ['+x.key+']');
  }
}
// every single modifier and pair shows something
for (const m of [['SUPER'],['SHIFT'],['CTRL'],['ALT'],['SUPER','SHIFT'],['SUPER','CTRL'],['SUPER','ALT'],['SHIFT','ALT'],['CTRL','ALT'],['SHIFT','CTRL']])
  console.log('hold', m.join('+').padEnd(12), M.list(b,m,'').length);
let dup=0; for (const x of b) for (const n of (x.keyNames||[]).filter(n=>!/^(BTN_|WHEEL_)/.test(n))) { dup++;
  const code=Object.keys(L.codes).find(c=>L.codes[c]===n); if (!code) continue;
  if (!M.list(b,x.mods,'',L.codes[code]).some(l=>l.bindings.includes(x))) fails.push('alt key '+n+' for '+x.combo); }
console.log('key/binding pairs checked:', dup);
console.log('drawn keys without a keycode:', drawn.filter(n=>!Object.values(L.codes).includes(n)));
console.log('undrawn but pressable:', b.filter(x=>x.keyId&&!drawn.includes(x.keyId)).length);
console.log('\nbindings', b.length, 'failures', fails.length); fails.forEach(f=>console.log('  FAIL', f));
console.log('\nnot on the drawn keyboard:', unlit.length); unlit.forEach(u=>console.log('  ', u));
// physical-key binds whose keycode is not drawn
const rev={}; for (const c in L.codes) rev[c]=L.codes[c];
for (const k in L.codeBinds) { const n=rev[L.codeBinds[k]]; if (!drawn.includes(n)) console.log('code bind not drawn:', k, 'code', L.codeBinds[k], n); }
process.exit(fails.length ? 1 : 0)
