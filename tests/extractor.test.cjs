const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const source = fs.readFileSync('iOS/iOSApp.swift', 'utf8').split('static let extractor = #"""')[1].split('"""#')[0];
function fixture({host='chatgpt.com', path='/c/123', secret=false, turns=[], streaming=false}={}) {
  const sent=[];
  const nodes=turns.map((t,i)=>({getAttribute:k=>k==='data-message-author-role'?t.role:`m${i}`,
    querySelector:k=>k==='img'?(t.image?{}:null):null, innerText:t.text||''}));
  let callback;
  const document={title:'اختبار عربي',documentElement:{},
    querySelector:k=>k.startsWith('input')?(secret?{}:null):(streaming?{}:null),
    querySelectorAll:()=>nodes};
  const window={webkit:{messageHandlers:{aecMirror:{postMessage:x=>sent.push(x)}}}};
  const context={location:{hostname:host,pathname:path},document,window,
    MutationObserver:class{constructor(fn){callback=fn} observe(){}},setTimeout:fn=>fn(),setInterval:()=>{}};
  vm.runInNewContext(source,context);
  return {sent,window,document,mutate:()=>callback?.()};
}
let f=fixture({turns:[{role:'user',text:'ما هذا؟'},{role:'assistant',text:'جواب عربي'}],streaming:true});
assert.equal(f.sent[0].messages[1].text,'جواب عربي');
assert.equal(f.sent[0].streaming,true);
f.mutate(); assert.equal(f.sent.length,1,'unchanged DOM must not resend');
f.window.__aecEmit(true); assert.equal(f.sent.length,2,'manual refresh must resend');
assert.equal(fixture({host:'auth.openai.com'}).sent.length,0,'never inject into auth hosts');
assert.equal(fixture({path:'/auth/login'}).sent[0].safe,false);
assert.equal(fixture({secret:true,turns:[{role:'user',text:'private'}]}).sent[0].messages.length,0);
assert.equal(fixture({turns:[{role:'user',image:true}]}).sent[0].messages[0].text,'📷 صورة');
assert.equal(fixture({turns:[{role:'system',text:'hidden'}]}).sent[0].messages.length,0);
f=fixture({turns:Array.from({length:40},()=>({role:'assistant',text:'x'.repeat(3000)}))});
assert.ok(f.sent[0].messages.length<=24);
assert.ok(f.sent[0].messages.reduce((a,m)=>a+m.text.length,0)<=22000);
f=fixture(); assert.equal(f.sent[0].messages.length,0,'empty conversation clears text');
console.log('Extractor: 11 privacy, streaming, refresh and payload checks passed');
