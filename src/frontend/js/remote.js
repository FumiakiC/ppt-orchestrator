(function() {
    var cid = sessionStorage.getItem('ppt_cid');
    if (!cid) {
        cid = (window.crypto && crypto.randomUUID) ? crypto.randomUUID() : (Date.now() + '' + Math.random()).replace(/\D/g,'').slice(0,18);
        sessionStorage.setItem('ppt_cid', cid);
    }
    var el=document.getElementById('elapsed'), posEl=document.getElementById('pos'), dot=document.querySelector('.onair i');
    var pad=document.getElementById('pad'), btns=pad.querySelectorAll('.slide-btn');
    var lockSw=document.getElementById('lockSwitch'), lockLbl=document.getElementById('lockLbl'), lockOtherMsg=document.getElementById('lockOtherMsg');
    var stealBtn=document.getElementById('stealBtn'), stopBtn=document.getElementById('stopBtn'), stopForm=document.getElementById('stopForm');
    var container=document.querySelector('.container');
    var blkBtn=pad.querySelector('[data-cmd="blackout"]'), whtBtn=pad.querySelector('[data-cmd="whiteout"]');
    var baseMs=0, baseAt=performance.now(), seeded=false, lastT='', armed=false, lockOn=false, curPos=0, curTotal=0, curAtEnd=false;

    function post(u){ return fetch(u, { method:'POST', headers:{'Content-Type':'application/x-www-form-urlencoded'}, body:'cid='+encodeURIComponent(cid) }).then(function(r){ if(r.status===401){ window.location.href='/'; return null; } if(!r.ok) return null; return r.json().catch(function(){ return null; }); }).catch(function(){ return null; }); }
    function buzz(p){ if (navigator.vibrate) { try { navigator.vibrate(p); } catch(e){} } }

    function paint(){ var t=baseMs+(performance.now()-baseAt); if(t<0)t=0; var s=Math.floor(t/1000); var m=String(Math.floor(s/60)).padStart(2,'0'); var x=String(s%60).padStart(2,'0'); var v=m+':'+x; if(el&&v!==lastT){el.textContent=v;lastT=v;} if(dot)dot.style.opacity=(t%1000)<500?'1':'0.25'; requestAnimationFrame(paint); }
    function applyBounds(){ if(!armed)return; var nb=pad.querySelector('[data-cmd="next"]'), pb=pad.querySelector('[data-cmd="prev"]'); if(nb)nb.disabled=!!curAtEnd; if(pb)pb.disabled=(curTotal>0&&curPos<=1); }
    function setArmed(on){ armed=on; for(var i=0;i<btns.length;i++)btns[i].disabled=!on; if(container)container.classList.toggle('armed',on); applyBounds(); }
    function setProj(b,w){ if(blkBtn)blkBtn.classList.toggle('act',!!b); if(whtBtn)whtBtn.classList.toggle('act',!!w); }
    function renderLock(st){ if(!lockSw || !lockLbl || !lockOtherMsg || !stealBtn) return; lockOn=!!st.lock; var mine=!!st.mine; lockSw.classList.toggle('on',mine); lockSw.setAttribute('aria-checked',mine?'true':'false');
        if(mine){ lockLbl.textContent='YOU HAVE CONTROL'; lockLbl.style.color='var(--accent)'; lockOtherMsg.textContent='You have control of this presentation.'; stealBtn.disabled=true; setArmed(true); }
        else if(lockOn){ lockLbl.textContent='LOCKED BY ANOTHER'; lockLbl.style.color='var(--standby)'; lockOtherMsg.textContent='This presentation is being controlled by another device.'; stealBtn.disabled=false; setArmed(false); }
        else { lockLbl.textContent='REMOTE CONTROL LOCK'; lockLbl.style.color=''; lockOtherMsg.textContent='Tap the switch above to take control.'; stealBtn.disabled=true; setArmed(false); }
        setProj(st.black,st.white); }
    function pollState(){ fetch('/slide/state?cid='+encodeURIComponent(cid)+'&t='+Date.now()).then(function(r){ if(r.status===401){ window.location.href='/'; return null; } if(!r.ok) return null; return r.json(); }).then(function(st){ if(!st)return; var pred=baseMs+(performance.now()-baseAt); if(!seeded||Math.abs(st.ms-pred)>1000){baseMs=st.ms;baseAt=performance.now();seeded=true;} curPos=st.pos; curTotal=st.total; curAtEnd=!!st.atEnd; if(st.total>0&&posEl)posEl.textContent=Math.min(st.pos,st.total)+' / '+st.total; renderLock(st); }).catch(function(){}); }
    function sendSlide(cmd){ if(!armed)return; var hb=pad.querySelector('[data-cmd="'+cmd+'"]'); if(hb){ hb.classList.add('hit'); setTimeout(function(){ hb.classList.remove('hit'); },200); } buzz(12); post('/slide/'+cmd).then(function(res){ if(!res)return; if(res.locked){setArmed(false);pollState();return;} curPos=res.pos; curTotal=res.total; curAtEnd=!!res.atEnd; if(res.total>0&&posEl)posEl.textContent=Math.min(res.pos,res.total)+' / '+res.total; setProj(res.black,res.white); applyBounds(); }); }
    for(var i=0;i<btns.length;i++){ (function(b){ b.addEventListener('click',function(){ sendSlide(b.getAttribute('data-cmd')); }); })(btns[i]); }

    document.addEventListener('keydown',function(e){ if(e.key===' '||e.key==='Spacebar'){ e.preventDefault(); return; } if(!armed)return; var k=e.key;
        if(k==='ArrowRight'||k==='PageDown'){ e.preventDefault(); sendSlide('next'); }
        else if(k==='ArrowLeft'||k==='PageUp'){ e.preventDefault(); sendSlide('prev'); }
        else if(k==='Home'){ e.preventDefault(); sendSlide('first'); }
        else if(k==='End'){ e.preventDefault(); sendSlide('last'); }
        else if(k==='b'||k==='B'){ sendSlide('blackout'); }
        else if(k==='w'||k==='W'){ sendSlide('whiteout'); } });

    function toggleLock(){ if(armed) post('/lock/off').then(pollState); else if(!lockOn) post('/lock/on').then(function(){pollState();}); else pollState(); }
    lockSw.addEventListener('click',toggleLock);
    lockSw.addEventListener('keydown',function(e){ if(e.key==='Enter'){ e.preventDefault(); toggleLock(); } });

    window.bindHold(stopBtn, function(){ if(stopForm.requestSubmit){ stopForm.requestSubmit(); } else { var ev=new Event('submit',{bubbles:true,cancelable:true}); if(stopForm.dispatchEvent(ev)) stopForm.submit(); } });
    if(stealBtn) window.bindHold(stealBtn, function(){ post('/lock/steal').then(pollState); });

    var wl=null;
    function reqWake(){ if(document.visibilityState==='visible' && 'wakeLock' in navigator){ navigator.wakeLock.request('screen').then(function(s){wl=s;}).catch(function(){}); } }
    reqWake();
    document.addEventListener('visibilitychange',function(){ if(document.visibilityState==='visible'){ reqWake(); pollState(); } });

    function initNowNameMarquee(){
        var nameEl=document.querySelector('.np .now-name');
        if(!nameEl)return;
        var track=nameEl.querySelector('.nn-track');
        var seg=track&&track.querySelector('.nn-seg');
        if(!track || !seg)return;

        var SPEED_PX_PER_SEC=45;
        var START_DELAY=900;
        var MIN_DUR=4000;
        var LOOP_PAUSE_MS=3000;
        var rm=window.matchMedia ? window.matchMedia('(prefers-reduced-motion: reduce)') : null;
        var anim=null;
        var clone=null;
        var ro=null;

        function teardown(){
            if(anim){ anim.cancel(); anim=null; }
            if(clone && clone.parentNode===track){ track.removeChild(clone); }
            clone=null;
            nameEl.classList.remove('marquee');
        }

        function evaluate(){
            teardown();
            if(rm && rm.matches) return;
            if(nameEl.scrollWidth<=nameEl.clientWidth+1) return;

            nameEl.classList.add('marquee');
            clone=seg.cloneNode(true);
            clone.setAttribute('aria-hidden','true');
            track.appendChild(clone);

            var shift=seg.getBoundingClientRect().width;
            if(!(shift>0)){ teardown(); return; }

            var moveDuration=Math.max(MIN_DUR, (shift / SPEED_PX_PER_SEC) * 1000);
            var duration=moveDuration+LOOP_PAUSE_MS;
            var moveOffset=moveDuration/duration;
            anim=track.animate(
                [
                    { transform:'translateX(0)', offset:0 },
                    { transform:'translateX(' + (-shift) + 'px)', offset:moveOffset },
                    { transform:'translateX(' + (-shift) + 'px)', offset:1 }
                ],
                { duration:duration, iterations:Infinity, easing:'linear', delay:START_DELAY }
            );
        }

        if('ResizeObserver' in window){
            ro=new ResizeObserver(function(){ evaluate(); });
            ro.observe(nameEl);
        } else {
            window.addEventListener('resize', evaluate);
        }
        if(document.fonts && document.fonts.ready){ document.fonts.ready.then(function(){ evaluate(); }); }
        if(rm){
            if(rm.addEventListener){ rm.addEventListener('change', evaluate); }
            else if(rm.addListener){ rm.addListener(evaluate); }
        }

        evaluate();
    }

    initNowNameMarquee();
    requestAnimationFrame(paint); pollState(); setInterval(pollState,1200);
    window.startPolling(['running'], '/', { defaultDelay: 1500 });
})();
