        window.setConn = function(state, ms) {
            var d = document.getElementById('connDot');
            var pill = document.getElementById('statusPill');
            if (d) { d.className = 'dot conn-' + state; d.title = (state === 'lost') ? 'no connection' : ('ping ' + ms + ' ms'); }
            if (pill) {
                if (state === 'ok') { pill.textContent = 'LIVE'; pill.className = 'status'; }
                else if (state === 'slow') { pill.textContent = 'SLOW'; pill.className = 'status st-slow'; }
                else { pill.textContent = 'OFFLINE'; pill.className = 'status st-lost'; }
            }
        };
        window.showHoldHint = function(msg) {
            var el = document.getElementById('holdhint');
            if (!el) return;
            el.textContent = msg || 'Press and hold to confirm';
            el.classList.add('show');
            if (navigator.vibrate) navigator.vibrate(12);
            clearTimeout(el._t);
            el._t = setTimeout(function() { el.classList.remove('show'); }, 1500);
        };
        window.startPolling = function(expectedStatusArray, redirectUrl, opts) {
            opts = opts || {};
            var overlay = document.getElementById('offline-overlay');
            var defaultDelay = opts.defaultDelay || 1000;
            var maxDelay = opts.maxDelay || 5000;
            var backoffMultiplier = opts.backoffMultiplier || 1.5;
            var maxRetries = opts.maxRetries || 0;
            var maxErrors = opts.maxErrors || 0;
            var statusRedirects = opts.statusRedirects || {};
            var currentDelay = defaultDelay;
            var checkCount = 0;
            var errorCount = 0;
            var isPolling = true;

            function pollStatus() {
                if (!isPolling) return;
                var __t0 = Date.now();
                var showOverlayTimer = setTimeout(function() {
                    if (overlay) overlay.classList.add('active');
                }, 3000);

                fetch('/status?t=' + Date.now())
                .then(function(r) {
                    clearTimeout(showOverlayTimer);
                    if (overlay) overlay.classList.remove('active');
                    var __ms = Date.now() - __t0;
                    if (window.setConn) window.setConn(__ms > 600 ? 'slow' : 'ok', __ms);
                    if (r.status === 401 || r.status === 403) return 'unauthorized';
                    if (!r.ok) throw new Error('http ' + r.status);
                    return r.text();
                })
                .then(function(status) {
                    currentDelay = defaultDelay;
                    checkCount++;
                    if (statusRedirects[status]) {
                        isPolling = false;
                        window.location.href = statusRedirects[status];
                        return;
                    }
                    if (expectedStatusArray.indexOf(status) === -1) {
                        isPolling = false;
                        window.location.href = redirectUrl;
                    } else if (maxRetries > 0 && checkCount > maxRetries) {
                        window.location.href = redirectUrl;
                    } else {
                        setTimeout(pollStatus, currentDelay);
                    }
                })
                .catch(function(e) {
                    clearTimeout(showOverlayTimer);
                    if (overlay) overlay.classList.add('active');
                    if (window.setConn) window.setConn('lost');
                    currentDelay = Math.min(currentDelay * backoffMultiplier, maxDelay);
                    checkCount++;
                    errorCount++;
                    if ((maxRetries > 0 && checkCount > maxRetries) || (maxErrors > 0 && errorCount > maxErrors)) {
                        window.location.href = redirectUrl;
                    } else {
                        setTimeout(pollStatus, currentDelay);
                    }
                });
            }

            var forms = document.querySelectorAll('form');
            forms.forEach(function(form) {
                form.addEventListener('submit', function(e) {
                    if (overlay && overlay.classList.contains('active')) {
                        e.preventDefault();
                        return;
                    }
                    isPolling = false;
                });
            });

            pollStatus();
        };
