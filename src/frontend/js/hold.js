(function() {
    function buzz(p) { if (navigator.vibrate) { try { navigator.vibrate(p); } catch(e) {} } }

    window.bindHold = function(btn, onComplete) {
        if (onComplete) btn._onComplete = onComplete;
        if (btn.dataset.holdInited) return;
        btn.dataset.holdInited = '1';
        var dur = parseInt(btn.getAttribute('data-hold'), 10) || 1500;
        var formId = btn.getAttribute('data-submit');
        var raf = null, t0 = 0, active = false, fired = false;

        function set(p) { btn.style.setProperty('--chgp', p); }
        function frame(now) { var p = Math.min((now - t0) / dur, 1); set(p); if (p >= 1) { done(); return; } raf = requestAnimationFrame(frame); }
        function start(e) { if (btn.disabled) return; e.preventDefault(); active = true; fired = false; btn.classList.remove('releasing'); btn.classList.add('charging'); t0 = performance.now(); buzz(8); raf = requestAnimationFrame(frame); }
        function unwind() { if (raf) { cancelAnimationFrame(raf); raf = null; } btn.classList.add('releasing'); set(0); setTimeout(function() { btn.classList.remove('charging', 'releasing'); }, 320); }
        function up() { if (!active) return; var held = performance.now() - t0; active = false; unwind(); if (!fired && held < 420 && window.showHoldHint) { window.showHoldHint(btn.getAttribute('data-hint')); } }
        function leave() { if (!active) return; active = false; unwind(); }
        function fire() {
            if (typeof btn._onComplete === 'function') { btn._onComplete(); return; }
            var f = formId ? document.getElementById(formId) : btn.closest('form');
            if (f) { if (f.requestSubmit) { f.requestSubmit(); } else { var ev = new Event('submit', {bubbles: true, cancelable: true}); if (f.dispatchEvent(ev)) f.submit(); } }
        }
        function done() { fired = true; active = false; if (raf) { cancelAnimationFrame(raf); raf = null; } set(1); buzz([16, 26, 16]); fire(); setTimeout(function() { btn.classList.add('releasing'); set(0); setTimeout(function() { btn.classList.remove('charging', 'releasing'); }, 320); }, 110); }

        btn.addEventListener('pointerdown', start);
        btn.addEventListener('pointerup', up);
        btn.addEventListener('pointerleave', leave);
        btn.addEventListener('pointercancel', leave);
    };

    document.addEventListener('DOMContentLoaded', function() {
        var list = document.querySelectorAll('[data-hold]');
        for (var i = 0; i < list.length; i++) { window.bindHold(list[i]); }
    });
})();
