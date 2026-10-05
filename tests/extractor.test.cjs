const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const script=fs.readFileSync('iOS/iOSApp.swift','utf8').split('static let extractor = #"""')[1].split('"""#')[0];
const txt=s=>({nodeType:3,textContent:s});
function el(tag,attrs={},children=[]){
 const e={nodeType:1,tagName:tag,childNodes:children,children:children.filter(c=>c.nodeType===1),classList:{contains:c=>(attrs.class||'').split(' ').includes(c)},getAttribute:k=>attrs[k]??null,hasAttribute:k=>k in attrs};
 Object.defineProperty(e,'textContent',{get:()=>children.map(c=>c.textContent).join('')});
 e.querySelectorAll=q=>{const tags=q.split(',').map(s=>s.toUpperCase());const out=[];const walk=n=>{for(const c of n.children||[]){if(tags.includes(c.tagName))out.push(c);walk(c)}};walk(e);return out};e.querySelector=q=>e.querySelectorAll(q)[0]||null;return e;
}
function fixture({host='chatgpt.com',path='/c/123',secret=false,turns=[],streaming=false}={}){
 const sent=[];let callback;
 const nodes=turns.map((t,i)=>el('DIV',{'data-message-author-role':t.role||'assistant','data-message-id':`m${i}`},t.children||[txt(t.text||'')]));
 const document={title:'Test',documentElement:{},querySelector:q=>q.startsWith('input')?(secret?{}:null):(streaming?{}:null),querySelectorAll:()=>nodes,addEventListener:()=>{},createElement:()=>{throw Error('cross origin')}};
 const window={webkit:{messageHandlers:{aecMirror:{postMessage:x=>sent.push(x)}}}};
 vm.runInNewContext(script,{window,document,location:{hostname:host,pathname:path},TextEncoder,MutationObserver:class{constructor(f){callback=f}observe(){}},setTimeout:f=>f()});
 return {sent,window,mutate:()=>callback?.()};
}
let f=fixture({turns:[{children:[el('H2',{},[txt('Q1')]),el('OL',{start:'3'},[el('LI',{},[txt('C')]),el('LI',{},[el('STRONG',{},[txt('True')])])])]}]});
assert.equal(f.sent[0].messages[0].blocks[1].marker,'3.');assert.equal(f.sent[0].messages[0].blocks[2].marker,'4.');assert.equal(f.sent[0].messages[0].blocks[2].text,'**True**');
f.mutate();assert.equal(f.sent.length,1);f.window.__aecEmit(true);assert.equal(f.sent.length,2);
assert.equal(fixture({secret:true,turns:[{text:'secret'}]}).sent.length,0);
assert.equal(fixture({path:'/auth/login'}).sent.length,0);assert.equal(fixture({host:'accounts.google.com'}).sent.length,0);
f=fixture({turns:[{children:[el('TABLE',{},[el('TR',{},[el('TH',{},[txt('رقم')]),el('TH',{},[txt('جواب')])]),el('TR',{},[el('TD',{},[txt('1')]),el('TD',{},[txt('C')])])])]}]});assert.equal(f.sent[0].messages[0].blocks[0].rows[1][1],'C');
f=fixture({turns:[{children:[el('UL',{},[el('LI',{},[txt('parent'),el('OL',{},[el('LI',{},[txt('child')])])])])]}]});assert.equal(f.sent[0].messages[0].blocks[1].depth,1);
const img=el('IMG');Object.assign(img,{src:'https://chatgpt.com/image',complete:true,naturalWidth:10,naturalHeight:10});f=fixture({turns:[{children:[img]}]});assert.equal(f.sent[0].messages[0].blocks[0].unavailable,true);
f=fixture({turns:Array.from({length:40},()=>({text:'سؤال جواب '.repeat(1000)}))});assert.equal(f.sent[0].truncated,true);assert.ok(new TextEncoder().encode(JSON.stringify(f.sent[0])).length<55000);
console.log('Rich extraction: numbering, bold, nested lists, tables, payload bounds, auth privacy, deduplication and blocked-image fallback passed');
