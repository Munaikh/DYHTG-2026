// Separate authenticated test player for simulator/manual testing. Never stores tokens.
// Automatic predictions are calculated from the PUBLIC presented state, not answer banks.
import {readFileSync} from 'node:fs';
import {predictDuel} from './duel_prediction.mjs';
import {randomUUID} from 'node:crypto';
import {createInterface} from 'node:readline';
const roomCode=process.argv[2];
if(!roomCode || roomCode==='--help') {
  console.log('Usage: node scripts/duel_partner.mjs ROOMCODE [--auto] [--local]\nCommands: ready, answer NODE, next, state, quit\n--auto readies, solves using the public graph/state, and advances only after its opponent.');
  process.exit(0);
}
if(!/^[A-Fa-f0-9]{6}$/.test(roomCode)) throw Error('Room code must contain six hex characters.');
const automatic=process.argv.includes('--auto');
const local=process.argv.includes('--local');
const cfg=JSON.parse(readFileSync(new URL('../supabase/client-config.json',import.meta.url)));
const url=process.env.SUPABASE_URL ?? (local?'http://127.0.0.1:56321':cfg.url);
const key=process.env.SUPABASE_PUBLISHABLE_KEY ?? (local?undefined:cfg.publishableKey);
if(!key || key.startsWith('sb_secret_')) throw Error('Use a publishable key; for --local set SUPABASE_PUBLISHABLE_KEY.');
let session, snapshot, busy=false, done=false, lastRevision=-1;
const pause=ms=>new Promise(resolve=>setTimeout(resolve,ms));
async function request(path,body,token=session?.access_token){
  const response=await fetch(url+path,{method:'POST',headers:{apikey:key,'Content-Type':'application/json',
    ...(token?{Authorization:`Bearer ${token}`}:{})},body:JSON.stringify(body),signal:AbortSignal.timeout(10000)});
  const data=await response.json();
  if(!response.ok){let detail;try{detail=JSON.parse(data.message);}catch{detail=data;}throw Object.assign(Error(detail.message),{server:detail});}
  return data;
}
function report(){
  if(snapshot.revision===lastRevision)return;
  lastRevision=snapshot.revision;
  console.log(`Round ${snapshot.roundIndex+1}/3 · ${snapshot.phase} · revision ${snapshot.revision}`);
  console.log(snapshot.players.map(p=>`${p.nickname}: ${p.score} points${p.submitted?' · locked':''}${p.hasContinued?' · continued':''}`).join(' | '));
  if(snapshot.currentRound)console.log(`${snapshot.currentRound.title}: ${snapshot.currentRound.prompt}`);
  if(snapshot.reveal)console.log(snapshot.reveal.explanation);
}
async function refresh(){snapshot=await request('/rest/v1/rpc/arena_duel_snapshot',{match_id:snapshot.id});report();}
async function send(action,answerNodeID){
  if(busy || done)return;busy=true;
  const round=snapshot.roundIndex;
  let command={id:randomUUID(),action,matchID:snapshot.id,revision:snapshot.revision,...(answerNodeID?{answerNodeID}:{})};
  try{
    for(let attempt=0;attempt<3;attempt++){
      try{snapshot=await request('/rest/v1/rpc/arena_duel_command',{command});report();return;}
      catch(error){
        if(error.server?.code==='staleRevision'){
          await refresh();const me=snapshot.players.find(p=>p.id===snapshot.viewerID);
          if((action==='submit'&&(snapshot.roundIndex!==round||snapshot.phase!=='answering'||me.submitted)) ||
             (action==='advance'&&(snapshot.roundIndex!==round||snapshot.phase!=='reveal'||me.hasContinued)))return;
          command={...command,id:randomUUID(),revision:snapshot.revision};
        }else if(error.server)throw error;
        // An uncertain network outcome retains the original command UUID and payload.
        await pause(750);
      }
    }
    throw Error('Could not reconcile the command. Check state before trying again.');
  }finally{busy=false;}
}
session=await request('/auth/v1/signup',{},null);
snapshot=await request('/rest/v1/rpc/arena_duel_command',{command:{id:randomUUID(),action:'join',code:roomCode,nickname:'Test partner'}});
console.log(`Joined ${snapshot.roomCode} as a separate anonymous player. ${automatic?'Automatic test mode.':'Type ready, answer NODE, next, state, or quit.'}`);
report();
const input=createInterface({input:process.stdin,output:process.stdout});
input.on('line',async line=>{
  const [action,node]=line.trim().split(/\s+/);
  try{
    if(action==='state')await refresh();
    else if(action==='quit'){await send('leave');done=true;input.close();}
    else if(action==='ready')await send('ready');
    else if(action==='answer'&&node)await send('submit',node.toUpperCase());
    else if(action==='next')await send('advance');
  }catch(error){console.error(error.message);}
});
while(!done){
  try{
    if(!busy){
      await refresh();
      if(['finished','incomplete'].includes(snapshot.phase)){done=true;break;}
      if(automatic){
        const me=snapshot.players.find(p=>p.id===snapshot.viewerID),opponent=snapshot.players.find(p=>p.id!==snapshot.viewerID);
        if(snapshot.phase==='lobby'&&!me.ready)await send('ready');
        if(snapshot.phase==='answering'&&!me.submitted){
          const round=snapshot.currentRound;
          const prediction=predictDuel(snapshot.algorithm,round);
          console.log(`Test partner predicts ${prediction} from the public graph and state.`);
          await send('submit',prediction);
        }
        if(snapshot.phase==='reveal'&&!me.hasContinued&&opponent.hasContinued)await send('advance');
      }
    }
  }catch(error){console.error(`Waiting to reconnect: ${error.message}`);}
  await pause(1000);
}
input.close();
console.log('Partner finished.');
