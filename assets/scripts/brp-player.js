(function () {
    var STORAGE_KEY = 'brp-listen-progress-v1';
    var STORAGE_KEY_LAST = 'brp-last-listened-v1';
    var SESSION_HANDOFF_KEY = 'brp-playback-handoff-v1';
    var SESSION_META_KEY = 'brp-playback-meta-v1';
    var MIN_RESUME_SEC = 5;
    var END_MARGIN_SEC = 15;
    var TIMEUPDATE_SAVE_MS = 5000;
    var SKIP_BACK_SEC = 15;
    var SKIP_FORWARD_SEC = 30;

    var player = null;
    var globalRoot = null;
    var globalArt = null;
    var globalArtWrap = null;
    var globalTitle = null;
    var globalShow = null;
    var globalPlay = null;
    var globalScrub = null;
    var globalScrubProgress = null;
    var globalCurrentEl = null;
    var globalDurationEl = null;
    var globalScrubbing = false;

    var fullscreenRoot = null;
    var fullscreenArt = null;
    var fullscreenArtWrap = null;
    var fullscreenTitle = null;
    var fullscreenShow = null;
    var fullscreenEpisodeLink = null;
    var fullscreenPodcastLink = null;
    var fullscreenPlay = null;
    var fullscreenScrub = null;
    var fullscreenScrubProgress = null;
    var fullscreenCurrentEl = null;
    var fullscreenDurationEl = null;
    var fullscreenScrubbing = false;
    var fullscreenOpen = false;
    var fullscreenEscHandler = null;

    var activeDeck = null;
    var currentMeta = {
        episodeTitle: '',
        podcastTitle: '',
        coverUrl: '',
        episodePageUrl: '',
        podcastPageUrl: '',
    };
    var mediaSessionReady = false;
    var iosMediaSessionResumeTime = 0;
    var lastTimeupdateSave = 0;
    var resumeAppliedForSrc = '';
    var engineReady = false;
    var deckShellVisible = false;
    var deckVisibilityObserver = null;
    var metaSourceUrl = '';

    var isIOS =
        /iPad|iPhone|iPod/.test(navigator.userAgent) ||
        (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);

    function notifyUserSync(immediate) {
        if (!window.BrpUserSync) return;
        if (immediate && window.BrpUserSync.flushLocalChange) {
            window.BrpUserSync.flushLocalChange();
        } else if (window.BrpUserSync.notifyLocalChange) {
            window.BrpUserSync.notifyLocalChange();
        }
    }

    function formatTime(seconds) {
        if (!isFinite(seconds) || seconds < 0) return '0:00';
        var total = Math.floor(seconds);
        var h = Math.floor(total / 3600);
        var m = Math.floor((total % 3600) / 60);
        var s = total % 60;
        if (h > 0) {
            return h + ':' + String(m).padStart(2, '0') + ':' + String(s).padStart(2, '0');
        }
        return m + ':' + String(s).padStart(2, '0');
    }

    function absoluteAssetUrl(url) {
        if (!url) return '';
        try {
            return new URL(url, window.location.origin).href;
        } catch (e) {
            return url;
        }
    }

    function imageMimeTypeFromUrl(url) {
        if (!url) return '';
        var path = '';
        try {
            path = new URL(url, window.location.href).pathname;
        } catch (e) {
            path = String(url).split(/[?#]/)[0];
        }
        if (/\.png$/i.test(path)) return 'image/png';
        if (/\.webp$/i.test(path)) return 'image/webp';
        if (/\.gif$/i.test(path)) return 'image/gif';
        if (/\.jpe?g$/i.test(path)) return 'image/jpeg';
        return '';
    }

    function defaultFallbackArtworkUrl() {
        var link = document.querySelector('link[rel="apple-touch-icon"][href]');
        if (link) return absoluteAssetUrl(link.getAttribute('href'));
        return absoluteAssetUrl('/assets/img/favicon.png');
    }

    function buildMediaSessionArtwork(coverUrl) {
        var src = absoluteAssetUrl((coverUrl || '').trim());
        if (!src) return [];
        var mime = imageMimeTypeFromUrl(src);
        var sizes = ['96x96', '128x128', '256x256', '512x512', '1024x1024'];
        return sizes.map(function (size) {
            var entry = { src: src, sizes: size };
            if (mime) entry.type = mime;
            return entry;
        });
    }

    var mediaSessionMetaToken = 0;

    function preloadArtworkForMediaSession(url, callback) {
        if (!url) {
            callback(url);
            return;
        }
        if (!isIOS) {
            callback(url);
            return;
        }
        var img = new Image();
        var settled = false;
        function finish() {
            if (settled) return;
            settled = true;
            callback(url);
        }
        img.onload = finish;
        img.onerror = finish;
        img.src = url;
        window.setTimeout(finish, 2000);
    }

    function storageUrlKey(url) {
        if (!url) return '';
        try {
            return new URL(url, window.location.href).href;
        } catch (e) {
            return url;
        }
    }

    function urlsMatch(a, b) {
        if (!a || !b) return false;
        if (a === b) return true;
        try {
            return new URL(a, window.location.href).href === new URL(b, window.location.href).href;
        } catch (e) {
            return false;
        }
    }

    function loadProgressMap() {
        try {
            var raw = localStorage.getItem(STORAGE_KEY);
            if (!raw) return {};
            var data = JSON.parse(raw);
            return data && typeof data === 'object' && !Array.isArray(data) ? data : {};
        } catch (e) {
            return {};
        }
    }

    function isProgressComplete(row) {
        if (!row) return false;
        if (row.c === true) return true;
        if (!isFinite(row.d) || row.d <= 0) return false;
        return isFinite(row.t) && row.t >= row.d - END_MARGIN_SEC;
    }

    function persistProgressMap(map) {
        try {
            localStorage.setItem(STORAGE_KEY, JSON.stringify(map));
            notifyUserSync();
        } catch (e) {}
    }

    function getSavedProgressRow(url) {
        var key = storageUrlKey(url);
        if (!key) return null;
        var row = loadProgressMap()[key];
        if (!row || typeof row !== 'object') return null;
        if (row.c === true) return row;
        if (typeof row.t !== 'number' || !isFinite(row.t)) return null;
        return row;
    }

    function getSavedProgressSeconds(url) {
        var row = getSavedProgressRow(url);
        if (!row || isProgressComplete(row)) return null;
        return row.t;
    }

    function markProgressComplete(url, duration) {
        var key = storageUrlKey(url);
        if (!key) return;
        var dur = duration;
        if (!isFinite(dur) || dur <= 0) {
            var existing = getSavedProgressRow(url);
            if (existing && isFinite(existing.d) && existing.d > 0) dur = existing.d;
        }
        var map = loadProgressMap();
        if (!isFinite(dur) || dur <= 0) {
            map[key] = { c: true, u: Date.now() };
        } else {
            map[key] = { t: dur, d: dur, u: Date.now(), c: true };
        }
        persistProgressMap(map);
    }

    function removeProgressForUrl(url) {
        var key = storageUrlKey(url);
        if (!key) return;
        var map = loadProgressMap();
        if (!map[key]) return;
        map[key] = { x: 1, u: Date.now() };
        persistProgressMap(map);
    }

    function saveProgressForUrl(url, currentTime, duration) {
        var key = storageUrlKey(url);
        if (!key || !isFinite(currentTime)) return;
        if (currentTime < MIN_RESUME_SEC) {
            removeProgressForUrl(url);
            return;
        }
        var map = loadProgressMap();
        var existing = map[key] || {};
        var dur = duration;
        if (!isFinite(dur) || dur <= 0) {
            if (isFinite(existing.d) && existing.d > 0) dur = existing.d;
        }
        var entry;
        if (isFinite(dur) && dur > 0 && currentTime >= dur - END_MARGIN_SEC) {
            entry = { t: dur, d: dur, u: Date.now(), c: true };
        } else {
            entry = { t: currentTime, u: Date.now() };
            if (isFinite(dur) && dur > 0) entry.d = dur;
            else if (isFinite(existing.d) && existing.d > 0) entry.d = existing.d;
        }
        map[key] = entry;
        persistProgressMap(map);
    }

    function playerActiveUrl() {
        if (!player) return '';
        // Prefer the assigned episode URL (feed enclosure) over CDN redirect currentSrc.
        return player.src || player.currentSrc || '';
    }

    function isPlaybackActive() {
        return !!(player && !player.paused && !player.ended);
    }

    function hasLoadedPlayback() {
        return !!playerActiveUrl();
    }

    function refreshMediaSessionFromPlayback() {
        if (!hasLoadedPlayback()) return;
        restorePlaybackMeta();
        updateMediaSessionMetadata();
        if (isPlaybackActive()) updateMediaSessionPosition();
    }

    function urlsMatchEpisode(a, b) {
        if (!a || !b) return false;
        if (urlsMatch(a, b)) return true;
        if (!player) return false;
        var assigned = player.src || '';
        var resolved = player.currentSrc || '';
        if (assigned && urlsMatch(a, assigned) && urlsMatch(b, assigned)) return true;
        if (resolved && urlsMatch(a, resolved) && urlsMatch(b, resolved)) return true;
        return false;
    }

    function playerMatchesEpisodeUrl(episodeUrl) {
        if (!episodeUrl || !player) return false;
        return urlsMatchEpisode(episodeUrl, playerActiveUrl());
    }

    function metaMatchesActivePlayer() {
        if (!metaSourceUrl || !playerActiveUrl()) return false;
        return urlsMatchEpisode(metaSourceUrl, playerActiveUrl());
    }

    function loadLastListened() {
        try {
            var raw = localStorage.getItem(STORAGE_KEY_LAST);
            if (!raw) return null;
            var row = JSON.parse(raw);
            if (!row || typeof row.url !== 'string' || !row.url) return null;
            return row;
        } catch (e) {
            return null;
        }
    }

    function saveLastListened(audioUrl, episodeTitle, podcastTitle, coverUrl) {
        var key = storageUrlKey(audioUrl);
        if (!key) return;
        try {
            localStorage.setItem(
                STORAGE_KEY_LAST,
                JSON.stringify({
                    url: key,
                    episodeTitle: episodeTitle || 'Episode',
                    podcastTitle: podcastTitle || 'Podcast',
                    coverUrl: (coverUrl || '').trim(),
                    u: Date.now(),
                })
            );
            notifyUserSync();
        } catch (e) {}
    }

    function clearLastListenedIfUrl(url) {
        var last = loadLastListened();
        if (!last || !url) return;
        if (urlsMatch(last.url, url)) {
            try {
                localStorage.setItem(
                    STORAGE_KEY_LAST,
                    JSON.stringify({ cleared: true, u: Date.now() })
                );
                notifyUserSync(true);
            } catch (e) {}
        }
    }

    function escapeHtml(str) {
        return String(str)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;');
    }

    function resolveSitePath(url) {
        if (!url) return '';
        var value = String(url).trim();
        if (!value) return '';
        try {
            return new URL(value, window.location.origin).pathname;
        } catch (e) {
            return value.charAt(0) === '/' ? value : '/' + value;
        }
    }

    function metaLinkHtml(text, url, linkClass, appearanceClass) {
        text = (text || '').trim();
        url = resolveSitePath(url);
        if (!text) return '';
        if (url) {
            var classes = linkClass;
            if (appearanceClass) classes = appearanceClass + ' ' + linkClass;
            return (
                '<a class="' +
                classes +
                '" href="' +
                escapeHtml(url) +
                '">' +
                escapeHtml(text) +
                '</a>'
            );
        }
        if (appearanceClass) {
            return '<span class="' + appearanceClass + '">' + escapeHtml(text) + '</span>';
        }
        return escapeHtml(text);
    }

    function setGlobalMetaLine(container, text, url, linkClass) {
        if (!container) return;
        text = (text || '').trim();
        url = resolveSitePath(url);
        if (!text) {
            container.textContent = '';
            return;
        }
        if (url) {
            container.innerHTML = metaLinkHtml(text, url, linkClass);
        } else {
            container.textContent = text;
        }
    }

    function readMetaUrlsFromButton(button) {
        var clickedLi = button.closest('.latest-episodes__item');
        var episodePageUrl = (button.getAttribute('data-episode-url') || '').trim();
        var podcastPageUrl = (button.getAttribute('data-podcast-url') || '').trim();

        if (!episodePageUrl && clickedLi) {
            var epLink =
                clickedLi.querySelector('a.latest-episodes__episode-hit[href]') ||
                clickedLi.querySelector('a.latest-episodes__episode-title[href]');
            if (epLink) episodePageUrl = (epLink.getAttribute('href') || '').trim();
            if (!episodePageUrl) {
                episodePageUrl = (clickedLi.getAttribute('data-episode-url') || '').trim();
            }
        }
        if (!podcastPageUrl && clickedLi) {
            podcastPageUrl = (clickedLi.getAttribute('data-podcast-url') || '').trim();
            if (!podcastPageUrl) {
                var podLink = clickedLi.querySelector('a.latest-episodes__podcast-link[href]');
                if (podLink) podcastPageUrl = (podLink.getAttribute('href') || '').trim();
            }
        }

        return {
            episodePageUrl: episodePageUrl,
            podcastPageUrl: podcastPageUrl,
        };
    }

    function rememberEpisodeMeta(episodeTitle, podcastTitle, coverUrl, audioUrl, episodePageUrl, podcastPageUrl) {
        currentMeta.episodeTitle = episodeTitle || 'Episode';
        currentMeta.podcastTitle = podcastTitle || 'Podcast';
        currentMeta.coverUrl = (coverUrl || '').trim();
        currentMeta.episodePageUrl = (episodePageUrl || '').trim();
        currentMeta.podcastPageUrl = (podcastPageUrl || '').trim();
        metaSourceUrl = storageUrlKey(audioUrl || playerActiveUrl());
        persistPlaybackMeta(audioUrl);
        setupMediaSessionHandlers();
        updateMediaSessionMetadata();
    }

    function persistPlaybackMeta(optionalUrl) {
        var url = optionalUrl || playerActiveUrl();
        url = storageUrlKey(url);
        if (!url) return;
        if (!currentMeta.episodeTitle && !currentMeta.podcastTitle) return;
        try {
            sessionStorage.setItem(
                SESSION_META_KEY,
                JSON.stringify({
                    url: storageUrlKey(url),
                    meta: currentMeta,
                })
            );
        } catch (e) {}
    }

    function applyMetaFully(meta, sourceUrl) {
        if (!meta) return;
        currentMeta.episodeTitle = meta.episodeTitle || 'Episode';
        currentMeta.podcastTitle = meta.podcastTitle || 'Podcast';
        currentMeta.coverUrl = (meta.coverUrl || '').trim();
        currentMeta.episodePageUrl = (meta.episodePageUrl || '').trim();
        currentMeta.podcastPageUrl = (meta.podcastPageUrl || '').trim();
        if (sourceUrl) metaSourceUrl = storageUrlKey(sourceUrl);
    }

    function metaFromPlayButton(button, fallbackUrl) {
        if (!button) return null;
        var urls = readMetaUrlsFromButton(button);
        return {
            episodeTitle: button.getAttribute('data-episode-title') || 'Episode',
            podcastTitle: button.getAttribute('data-podcast-title') || 'Podcast',
            coverUrl: button.getAttribute('data-cover-url') || '',
            audioUrl: button.getAttribute('data-audio-url') || fallbackUrl || '',
            episodePageUrl: urls.episodePageUrl,
            podcastPageUrl: urls.podcastPageUrl,
        };
    }

    function findPlayButtonForUrl(searchRoot, storedUrl) {
        var url = storedUrl || playerActiveUrl();
        if (!url) return null;
        var scope = searchRoot || document;
        var buttons = scope.querySelectorAll('[data-audio-url]');
        for (var i = 0; i < buttons.length; i++) {
            var btn = buttons[i];
            var btnUrl = btn.getAttribute('data-audio-url');
            if (playerMatchesEpisodeUrl(btnUrl) || urlsMatchEpisode(btnUrl, url)) {
                return btn;
            }
        }
        return null;
    }

    function findPlayButtonForActiveEpisode(searchRoot) {
        return findPlayButtonForUrl(searchRoot, playerActiveUrl());
    }

    function hydrateMetaFromPageButtons() {
        var url = playerActiveUrl();
        if (!url) return false;
        var btn = null;
        if (activeDeck && activeDeck.root) {
            btn = findPlayButtonForActiveEpisode(activeDeck.root);
        }
        if (!btn) btn = findPlayButtonForActiveEpisode(document);
        if (!btn) return false;
        var meta = metaFromPlayButton(btn, url);
        rememberEpisodeMeta(
            meta.episodeTitle,
            meta.podcastTitle,
            meta.coverUrl,
            meta.audioUrl,
            meta.episodePageUrl,
            meta.podcastPageUrl
        );
        return true;
    }

    function restorePlaybackMeta() {
        var url = playerActiveUrl();
        if (!url) return;

        if (metaMatchesActivePlayer() && (currentMeta.episodeTitle || currentMeta.podcastTitle)) {
            return;
        }

        try {
            var raw = sessionStorage.getItem(SESSION_META_KEY);
            if (raw) {
                var saved = JSON.parse(raw);
                if (saved && saved.meta && urlsMatchEpisode(saved.url, url)) {
                    applyMetaFully(saved.meta, saved.url);
                    return;
                }
            }
        } catch (e) {}

        var last = loadLastListened();
        if (last && urlsMatchEpisode(last.url, url)) {
            applyMetaFully(
                {
                    episodeTitle: last.episodeTitle,
                    podcastTitle: last.podcastTitle,
                    coverUrl: last.coverUrl,
                },
                last.url
            );
            return;
        }

        hydrateMetaFromPageButtons();
    }

    function setEpisodeSource(audioUrl) {
        player.removeAttribute('crossorigin');
        player.src = audioUrl;
    }

    function applyResumeIfNeeded() {
        var url = playerActiveUrl();
        if (!url) return;
        if (resumeAppliedForSrc === url) return;
        var saved = getSavedProgressSeconds(url);
        if (saved == null) {
            resumeAppliedForSrc = url;
            return;
        }
        var dur = player.duration;
        if (!isFinite(dur) || dur <= 0) return;
        if (saved < MIN_RESUME_SEC || saved >= dur - END_MARGIN_SEC) {
            resumeAppliedForSrc = url;
            return;
        }
        try {
            player.currentTime = saved;
        } catch (e) {}
        resumeAppliedForSrc = url;
    }

    function localWebpCandidate(url) {
        var value = (url || '').trim();
        if (!value) return '';
        var path = '';
        try {
            path = new URL(value, window.location.href).pathname;
        } catch (e) {
            path = String(value).split(/[?#]/)[0];
        }
        if (!path || /\.webp$/i.test(path)) return '';
        if (/^[a-z][a-z0-9+.-]*:\/\//i.test(value)) return '';
        if (!/\.(jpe?g|png)$/i.test(path)) return '';
        return value.replace(/\.(jpe?g|png)(?=([?#]|$))/i, '.webp');
    }

    function resolveCoverUrl(url) {
        return absoluteAssetUrl((url || '').trim());
    }

    function updateGlobalBarVisibility() {
        if (!globalRoot) return;
        var hasSource = !!playerActiveUrl();
        var deckActive = document.body.classList.contains('brp-deck-active');
        var stickyOnlyDeck = activeDeck && activeDeck.stickyOnly;
        var showGlobal = hasSource && (stickyOnlyDeck || !deckActive || !deckShellVisible);
        globalRoot.hidden = !showGlobal;
        document.body.classList.toggle('brp-global-player-visible', showGlobal);
    }

    function observeDeckShell(root) {
        if (deckVisibilityObserver) {
            deckVisibilityObserver.disconnect();
            deckVisibilityObserver = null;
        }

        if (!root || typeof IntersectionObserver === 'undefined') {
            deckShellVisible = false;
            updateGlobalBarVisibility();
            return;
        }

        // Observe the inline player shell, not the full section. On long pages (e.g.
        // latest-episodes) the section includes the episode list, so watching the
        // section root would keep the sticky bar hidden while scrolling the list.
        var observeTarget = root.querySelector('.latest-episodes__player-shell') || root;

        var rect = observeTarget.getBoundingClientRect();
        deckShellVisible = rect.bottom > 0 && rect.top < window.innerHeight;

        deckVisibilityObserver = new IntersectionObserver(
            function (entries) {
                deckShellVisible = !!(entries[0] && entries[0].isIntersecting);
                updateGlobalBarVisibility();
            },
            { threshold: 0, rootMargin: '0px' }
        );
        deckVisibilityObserver.observe(observeTarget);
        updateGlobalBarVisibility();
    }

    function updateGlobalArt(url) {
        if (!globalArt || !globalArtWrap) return;
        var effective = resolveCoverUrl(url);
        if (effective) {
            globalArt.onload = function () {
                globalArt.onerror = null;
                if (!player.paused && !player.ended) updateMediaSessionMetadata();
            };
            globalArt.onerror = function () {
                var webp = localWebpCandidate(url || currentMeta.coverUrl || '');
                if (webp && globalArt.src.indexOf('.webp') === -1) {
                    globalArt.src = absoluteAssetUrl(webp);
                    return;
                }
                globalArt.onerror = null;
                globalArt.removeAttribute('src');
                globalArtWrap.classList.add('brp-global-player__art-wrap--empty');
            };
            if (globalArt.getAttribute('data-brp-cover-url') !== effective) {
                globalArt.setAttribute('data-brp-cover-url', effective);
                globalArt.src = effective;
            }
            globalArtWrap.classList.remove('brp-global-player__art-wrap--empty');
        } else {
            globalArt.onerror = null;
            globalArt.removeAttribute('data-brp-cover-url');
            globalArt.removeAttribute('src');
            globalArtWrap.classList.add('brp-global-player__art-wrap--empty');
        }
    }

    function syncGlobalPlayButton() {
        if (!player) return;
        var playing = !player.paused && !player.ended;
        if (globalPlay) {
            globalPlay.classList.toggle('brp-global-player__play--playing', playing);
            globalPlay.setAttribute('aria-pressed', playing ? 'true' : 'false');
            globalPlay.setAttribute('aria-label', playing ? 'Pause' : 'Play');
        }
        if (fullscreenPlay) {
            fullscreenPlay.classList.toggle('brp-player-fullscreen__play--playing', playing);
            fullscreenPlay.setAttribute('aria-pressed', playing ? 'true' : 'false');
            fullscreenPlay.setAttribute('aria-label', playing ? 'Pause' : 'Play');
        }
    }

    function updateGlobalScrubVisual(pct) {
        if (!globalScrubProgress) return;
        var clamped = Math.min(100, Math.max(0, pct));
        globalScrubProgress.style.width = clamped + '%';
    }

    function updateFullscreenScrubVisual(pct) {
        if (!fullscreenScrubProgress) return;
        var clamped = Math.min(100, Math.max(0, pct));
        fullscreenScrubProgress.style.width = clamped + '%';
    }

    function updateAllScrubVisuals(pct) {
        updateGlobalScrubVisual(pct);
        updateFullscreenScrubVisual(pct);
    }

    function syncScrubInputs(scaled) {
        var value = String(scaled);
        if (globalScrub) {
            globalScrub.value = value;
            globalScrub.setAttribute('aria-valuenow', value);
        }
        if (fullscreenScrub) {
            fullscreenScrub.value = value;
            fullscreenScrub.setAttribute('aria-valuenow', value);
        }
    }

    function updateGlobalTransportTimes() {
        if (!player) return;
        var dur = player.duration;
        var cur = player.currentTime;
        var curLabel = formatTime(cur);
        var durLabel = isFinite(dur) && dur > 0 ? formatTime(dur) : '0:00';
        if (globalCurrentEl) globalCurrentEl.textContent = curLabel;
        if (globalDurationEl) globalDurationEl.textContent = durLabel;
        if (fullscreenCurrentEl) fullscreenCurrentEl.textContent = curLabel;
        if (fullscreenDurationEl) fullscreenDurationEl.textContent = durLabel;
        if (isFinite(dur) && dur > 0 && !globalScrubbing && !fullscreenScrubbing) {
            var scaled = Math.round((cur / dur) * 1000);
            syncScrubInputs(scaled);
            updateAllScrubVisuals((cur / dur) * 100);
        }
    }

    function syncFullscreenMeta() {
        if (!fullscreenTitle || !fullscreenShow) return;
        setGlobalMetaLine(
            fullscreenTitle,
            currentMeta.episodeTitle,
            currentMeta.episodePageUrl,
            'brp-player-fullscreen__title-link'
        );
        setGlobalMetaLine(
            fullscreenShow,
            currentMeta.podcastTitle,
            currentMeta.podcastPageUrl,
            'brp-player-fullscreen__show-link'
        );
        if (fullscreenEpisodeLink) {
            var episodePath = resolveSitePath(currentMeta.episodePageUrl);
            if (episodePath) {
                fullscreenEpisodeLink.href = episodePath;
                fullscreenEpisodeLink.hidden = false;
            } else {
                fullscreenEpisodeLink.hidden = true;
            }
        }
        if (fullscreenPodcastLink) {
            var podcastPath = resolveSitePath(currentMeta.podcastPageUrl);
            if (podcastPath) {
                fullscreenPodcastLink.href = podcastPath;
                fullscreenPodcastLink.hidden = false;
            } else {
                fullscreenPodcastLink.hidden = true;
            }
        }
        if (fullscreenArt && fullscreenArtWrap) {
            var cover = resolveCoverUrl(currentMeta.coverUrl);
            if (cover) {
                fullscreenArt.onload = function () {
                    fullscreenArt.onerror = null;
                };
                fullscreenArt.onerror = function () {
                    var webp = localWebpCandidate(currentMeta.coverUrl || '');
                    if (webp && fullscreenArt.src.indexOf('.webp') === -1) {
                        fullscreenArt.src = absoluteAssetUrl(webp);
                        return;
                    }
                    fullscreenArt.onerror = null;
                    fullscreenArt.removeAttribute('src');
                    fullscreenArtWrap.classList.add('brp-player-fullscreen__art-wrap--empty');
                };
                if (fullscreenArt.getAttribute('data-brp-cover-url') !== cover) {
                    fullscreenArt.setAttribute('data-brp-cover-url', cover);
                    fullscreenArt.src = cover;
                }
                fullscreenArtWrap.classList.remove('brp-player-fullscreen__art-wrap--empty');
            } else {
                fullscreenArt.onerror = null;
                fullscreenArt.removeAttribute('data-brp-cover-url');
                fullscreenArt.removeAttribute('src');
                fullscreenArtWrap.classList.add('brp-player-fullscreen__art-wrap--empty');
            }
        }
    }

    function syncFullscreenUi() {
        syncFullscreenMeta();
        syncGlobalPlayButton();
        updateGlobalTransportTimes();
    }

    function prefersReducedMotion() {
        return !!(window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches);
    }

    function finishClosePlayerFullscreen() {
        if (!fullscreenRoot) return;
        fullscreenRoot.hidden = true;
        fullscreenRoot.setAttribute('aria-hidden', 'true');
        fullscreenRoot.classList.remove('brp-player-fullscreen--opening', 'brp-player-fullscreen--closing');
        document.body.classList.remove('brp-player-fullscreen-open');
        fullscreenOpen = false;
        fullscreenScrubbing = false;
        if (fullscreenEscHandler) {
            document.removeEventListener('keydown', fullscreenEscHandler);
        }
        if (globalPlay) {
            globalPlay.focus();
        }
    }

    function openPlayerFullscreen() {
        if (!fullscreenRoot || !playerActiveUrl()) return;
        fullscreenRoot.classList.remove('brp-player-fullscreen--closing');
        fullscreenRoot.hidden = false;
        fullscreenRoot.setAttribute('aria-hidden', 'false');
        document.body.classList.add('brp-player-fullscreen-open');
        fullscreenOpen = true;
        syncFullscreenUi();
        if (!prefersReducedMotion()) {
            fullscreenRoot.classList.remove('brp-player-fullscreen--opening');
            requestAnimationFrame(function () {
                requestAnimationFrame(function () {
                    fullscreenRoot.classList.add('brp-player-fullscreen--opening');
                });
            });
            fullscreenRoot.addEventListener(
                'animationend',
                function onEnterEnd(event) {
                    if (event.animationName !== 'brp-player-fullscreen-enter') return;
                    fullscreenRoot.classList.remove('brp-player-fullscreen--opening');
                    fullscreenRoot.removeEventListener('animationend', onEnterEnd);
                }
            );
        }
        if (!fullscreenEscHandler) {
            fullscreenEscHandler = function (event) {
                if (event.key === 'Escape') {
                    closePlayerFullscreen();
                }
            };
        }
        document.addEventListener('keydown', fullscreenEscHandler);
        if (fullscreenPlay) {
            fullscreenPlay.focus();
        }
    }

    function closePlayerFullscreen(instant) {
        if (!fullscreenRoot || !fullscreenOpen) return;
        if (instant || prefersReducedMotion()) {
            finishClosePlayerFullscreen();
            return;
        }
        fullscreenRoot.classList.remove('brp-player-fullscreen--opening');
        fullscreenRoot.classList.add('brp-player-fullscreen--closing');
        fullscreenRoot.addEventListener(
            'animationend',
            function onExitEnd(event) {
                if (event.animationName !== 'brp-player-fullscreen-exit') return;
                fullscreenRoot.removeEventListener('animationend', onExitEnd);
                finishClosePlayerFullscreen();
            }
        );
    }

    function handleGlobalScrubInput(scrubInput) {
        if (!player || !scrubInput) return;
        var dur = player.duration;
        if (!isFinite(dur) || dur <= 0) return;
        globalScrubbing = scrubInput === globalScrub;
        fullscreenScrubbing = scrubInput === fullscreenScrub;
        var scaled = Number(scrubInput.value);
        syncScrubInputs(scaled);
        updateAllScrubVisuals(scaled / 10);
        var preview = formatTime((scaled / 1000) * dur);
        if (globalCurrentEl) globalCurrentEl.textContent = preview;
        if (fullscreenCurrentEl) fullscreenCurrentEl.textContent = preview;
    }

    function renderGlobalBarFromMeta() {
        if (globalTitle) {
            setGlobalMetaLine(globalTitle, currentMeta.episodeTitle, null, null);
        }
        if (globalShow) {
            setGlobalMetaLine(globalShow, currentMeta.podcastTitle, null, null);
        }
        updateGlobalArt(currentMeta.coverUrl);
        syncFullscreenMeta();
        syncGlobalPlayButton();
        updateGlobalTransportTimes();
        updateGlobalBarVisibility();
    }

    function syncGlobalBarFromMeta() {
        restorePlaybackMeta();
        renderGlobalBarFromMeta();
    }

    function reconcilePlaybackAfterNavigation() {
        if (!playerActiveUrl()) return;
        refreshMediaSessionFromPlayback();
        renderGlobalBarFromMeta();
    }

    function updateMediaSessionPosition() {
        if (!('mediaSession' in navigator)) return;
        if (!player.src || player.paused) return;
        var dur = player.duration;
        if (!isFinite(dur) || dur <= 0) return;
        try {
            navigator.mediaSession.setPositionState({
                duration: dur,
                playbackRate: player.playbackRate || 1,
                position: Math.min(player.currentTime, dur),
            });
        } catch (e) {}
    }

    function updateMediaSessionMetadata() {
        if (!('mediaSession' in navigator)) return;
        var token = ++mediaSessionMetaToken;
        var title = currentMeta.episodeTitle || 'Episode';
        var artist = currentMeta.podcastTitle || 'Podcast';
        var cover = resolveCoverUrl(currentMeta.coverUrl) || defaultFallbackArtworkUrl();

        function applyMetadata(artUrl) {
            if (token !== mediaSessionMetaToken) return;
            var artwork = buildMediaSessionArtwork(artUrl);
            try {
                navigator.mediaSession.metadata = new MediaMetadata({
                    title: title,
                    artist: artist,
                    album: artist,
                    artwork: artwork,
                });
            } catch (e) {}
        }

        preloadArtworkForMediaSession(cover, applyMetadata);
    }

    function setMediaSessionPlaybackState(state) {
        if (!('mediaSession' in navigator)) return;
        try {
            navigator.mediaSession.playbackState = state;
        } catch (e) {}
    }

    function playEpisode(options) {
        options = options || {};
        updateMediaSessionMetadata();
        var playPromise = player.play();
        if (playPromise && typeof playPromise.then === 'function') {
            playPromise
                .then(function () {
                    if (options.onSuccess) options.onSuccess();
                    if (activeDeck && activeDeck.onPlayStateChange) activeDeck.onPlayStateChange();
                    syncGlobalBarFromMeta();
                })
                .catch(function () {
                    setMediaSessionPlaybackState('paused');
                    if (activeDeck && activeDeck.onPlayStateChange) activeDeck.onPlayStateChange();
                    syncGlobalBarFromMeta();
                });
            return playPromise;
        }
        if (activeDeck && activeDeck.onPlayStateChange) activeDeck.onPlayStateChange();
        syncGlobalBarFromMeta();
        return null;
    }

    function finishMediaSessionPlaySuccess() {
        if (activeDeck && activeDeck.onPlayStateChange) activeDeck.onPlayStateChange();
        setMediaSessionPlaybackState('playing');
        updateMediaSessionPosition();
        syncGlobalBarFromMeta();
    }

    function finishMediaSessionPlayFailure() {
        setMediaSessionPlaybackState('paused');
        if (activeDeck && activeDeck.onPlayStateChange) activeDeck.onPlayStateChange();
        syncGlobalBarFromMeta();
    }

    function refreshMediaSessionHandlersForIOS() {
        if (!isIOS || !('mediaSession' in navigator)) return;
        mediaSessionReady = false;
        setupMediaSessionHandlers();
    }

    function reloadPlayerForIOSLockScreenResume(callback) {
        var url = playerActiveUrl();
        if (!url) {
            callback(new Error('no active url'));
            return;
        }

        var resumeTime = player.currentTime;
        if (!isFinite(resumeTime) || resumeTime < 0) resumeTime = 0;
        if (iosMediaSessionResumeTime > 0) {
            resumeTime = iosMediaSessionResumeTime;
        } else {
            var saved = getSavedProgressSeconds(url);
            if (saved != null) resumeTime = saved;
        }

        resumeAppliedForSrc = '';
        setEpisodeSource(url);
        var settled = false;
        function done(err) {
            if (settled) return;
            settled = true;
            callback(err || null);
        }

        function onMeta() {
            player.removeEventListener('loadedmetadata', onMeta);
            try {
                if (resumeTime >= MIN_RESUME_SEC) player.currentTime = resumeTime;
            } catch (e) {}
            done(null);
        }

        player.addEventListener('loadedmetadata', onMeta);
        window.setTimeout(function () {
            done(new Error('metadata timeout'));
        }, 8000);

        try {
            player.load();
        } catch (e) {
            done(e);
        }
    }

    function attemptPlayFromMediaSession(retryLevel) {
        if (!player || !playerActiveUrl()) {
            finishMediaSessionPlayFailure();
            return;
        }

        updateMediaSessionMetadata();
        refreshMediaSessionHandlersForIOS();

        var playPromise = player.play();
        if (!playPromise || typeof playPromise.then !== 'function') {
            finishMediaSessionPlaySuccess();
            return;
        }

        playPromise
            .then(function () {
                iosMediaSessionResumeTime = 0;
                finishMediaSessionPlaySuccess();
            })
            .catch(function () {
                if (!isIOS || retryLevel >= 2) {
                    finishMediaSessionPlayFailure();
                    return;
                }
                if (retryLevel === 0) {
                    window.setTimeout(function () {
                        attemptPlayFromMediaSession(1);
                    }, 150);
                    return;
                }
                reloadPlayerForIOSLockScreenResume(function (err) {
                    if (err) {
                        finishMediaSessionPlayFailure();
                        return;
                    }
                    attemptPlayFromMediaSession(2);
                });
            });
    }

    function playFromMediaSession() {
        attemptPlayFromMediaSession(0);
    }

    function pauseFromMediaSession() {
        var url = playerActiveUrl();
        if (url) {
            iosMediaSessionResumeTime = player.currentTime;
            saveProgressForUrl(url, player.currentTime, player.duration);
        }
        player.pause();
        if (activeDeck && activeDeck.onPlayStateChange) activeDeck.onPlayStateChange();
        setMediaSessionPlaybackState('paused');
        syncGlobalBarFromMeta();
        refreshMediaSessionHandlersForIOS();
    }

    function bindMediaSessionActionHandlers() {
        navigator.mediaSession.setActionHandler('play', function () {
            playFromMediaSession();
        });

        navigator.mediaSession.setActionHandler('pause', function () {
            pauseFromMediaSession();
        });

        try {
            navigator.mediaSession.setActionHandler('stop', function () {
                pauseFromMediaSession();
            });
        } catch (e) {}

        navigator.mediaSession.setActionHandler('seekbackward', function (details) {
            var offset = details && details.seekOffset ? details.seekOffset : SKIP_BACK_SEC;
            player.currentTime = Math.max(0, player.currentTime - offset);
            updateGlobalTransportTimes();
            if (activeDeck && activeDeck.updateTransportTimes) activeDeck.updateTransportTimes();
            updateMediaSessionPosition();
        });

        navigator.mediaSession.setActionHandler('seekforward', function (details) {
            var offset = details && details.seekOffset ? details.seekOffset : SKIP_FORWARD_SEC;
            var dur = player.duration;
            var next = player.currentTime + offset;
            if (isFinite(dur) && dur > 0) next = Math.min(next, dur);
            player.currentTime = next;
            updateGlobalTransportTimes();
            if (activeDeck && activeDeck.updateTransportTimes) activeDeck.updateTransportTimes();
            updateMediaSessionPosition();
        });

        navigator.mediaSession.setActionHandler('seekto', function (details) {
            if (details && details.seekTime != null && isFinite(details.seekTime)) {
                player.currentTime = details.seekTime;
                updateGlobalTransportTimes();
                if (activeDeck && activeDeck.updateTransportTimes) activeDeck.updateTransportTimes();
                updateMediaSessionPosition();
            }
        });
    }

    function setupMediaSessionHandlers() {
        if (!('mediaSession' in navigator) || mediaSessionReady) return;
        mediaSessionReady = true;
        bindMediaSessionActionHandlers();
    }

    function refreshAllListenProgress() {
        document.querySelectorAll('[data-audio-url]').forEach(function (button) {
            updateListenProgressForButton(button);
        });
    }

    function listenPctForButton(button) {
        if (!button) return null;
        var url = button.getAttribute('data-audio-url');
        if (!url) return null;
        var keyNorm = storageUrlKey(url);
        var liveKey = storageUrlKey(playerActiveUrl());
        var cur = player.currentTime;
        var dur = player.duration;
        if (keyNorm && keyNorm === liveKey && isFinite(dur) && dur > 0) {
            return Math.min(100, Math.max(0, (cur / dur) * 100));
        }
        var row = getSavedProgressRow(url);
        if (!row) return null;
        if (isProgressComplete(row)) return 100;
        if (!isFinite(row.d) || row.d <= 0) return null;
        if (row.t < MIN_RESUME_SEC) return null;
        return Math.min(100, Math.max(0, (row.t / row.d) * 100));
    }

    function isListenHistoryListItem(li) {
        if (!li) return false;
        return li.hasAttribute('data-brp-history-item') || !!li.closest('[data-brp-listen-history]');
    }

    function updateListenProgressForButton(button) {
        var li = button.closest('.latest-episodes__item');
        if (!li) return;
        var url = button.getAttribute('data-audio-url');
        var row = url ? getSavedProgressRow(url) : null;
        var played = !!(row && isProgressComplete(row));
        if (isListenHistoryListItem(li)) {
            li.classList.remove('latest-episodes__item--played');
        } else {
            li.classList.toggle('latest-episodes__item--played', played);
        }

        var track = li.querySelector('[data-listen-progress-track]');
        var fill = li.querySelector('[data-listen-progress]');
        if (!track || !fill) return;
        if (isListenHistoryListItem(li)) {
            track.hidden = true;
            fill.style.width = '0%';
            return;
        }
        var pct = listenPctForButton(button);
        if (pct == null) {
            track.hidden = true;
            fill.style.width = '0%';
            return;
        }
        track.hidden = false;
        fill.style.width = pct + '%';
    }

    function savePlaybackHandoff() {
        var url = playerActiveUrl();
        if (!url) return;
        try {
            sessionStorage.setItem(
                SESSION_HANDOFF_KEY,
                JSON.stringify({
                    url: url,
                    time: player.currentTime,
                    playing: !player.paused && !player.ended,
                    meta: currentMeta,
                })
            );
        } catch (e) {}
    }

    function restorePlaybackHandoff() {
        if (!player) return;
        if (playerActiveUrl() && !player.paused && !player.ended) return;
        try {
            var raw = sessionStorage.getItem(SESSION_HANDOFF_KEY);
            if (!raw) return;
            sessionStorage.removeItem(SESSION_HANDOFF_KEY);
            var handoff = JSON.parse(raw);
            if (!handoff || !handoff.url || !handoff.playing) return;
            if (handoff.meta) {
                applyMetaFully(
                    {
                        episodeTitle: handoff.meta.episodeTitle || 'Episode',
                        podcastTitle: handoff.meta.podcastTitle || 'Podcast',
                        coverUrl: handoff.meta.coverUrl || '',
                        episodePageUrl: handoff.meta.episodePageUrl || '',
                        podcastPageUrl: handoff.meta.podcastPageUrl || '',
                    },
                    handoff.url
                );
            }
            resumeAppliedForSrc = storageUrlKey(handoff.url);
            setEpisodeSource(handoff.url);
            player.addEventListener(
                'loadedmetadata',
                function onMeta() {
                    player.removeEventListener('loadedmetadata', onMeta);
                    if (isFinite(handoff.time) && handoff.time > 0) {
                        try {
                            player.currentTime = handoff.time;
                        } catch (e) {}
                    }
                    playEpisode();
                    syncGlobalBarFromMeta();
                },
                { once: true }
            );
            try {
                player.load();
            } catch (e) {}
        } catch (e) {}
    }

    function recoverPlaybackAfterBackground() {
        if (!player.src || player.paused || player.ended) return;
        var t0 = player.currentTime;
        window.setTimeout(function () {
            if (player.paused || player.ended) return;
            if (player.currentTime - t0 < 0.05 && !player.seeking) {
                try {
                    player.pause();
                } catch (e) {}
                playEpisode();
            }
        }, 450);
    }

    function commitGlobalScrubSeek() {
        var scrubInput = fullscreenScrubbing ? fullscreenScrub : globalScrub;
        if (!scrubInput) scrubInput = globalScrub;
        if ((!globalScrubbing && !fullscreenScrubbing) || !scrubInput) return;
        var dur = player.duration;
        if (isFinite(dur) && dur > 0) {
            player.currentTime = (Number(scrubInput.value) / 1000) * dur;
        }
        globalScrubbing = false;
        fullscreenScrubbing = false;
        updateGlobalTransportTimes();
        if (activeDeck && activeDeck.updateTransportTimes) activeDeck.updateTransportTimes();
        updateMediaSessionPosition();
        refreshAllListenProgress();
    }

    function cancelGlobalScrubGesture() {
        globalScrubbing = false;
        fullscreenScrubbing = false;
        updateGlobalTransportTimes();
    }

    function toggleGlobalPlayback() {
        if (!player || !playerActiveUrl()) return;
        if (!player.paused && !player.ended) {
            player.pause();
        } else {
            playEpisode();
        }
    }

    function seekGlobalBySeconds(deltaSec) {
        if (!player || !player.src) return;
        var dur = player.duration;
        var next = player.currentTime + deltaSec;
        if (deltaSec < 0) {
            next = Math.max(0, next);
        } else if (isFinite(dur) && dur > 0) {
            next = Math.min(next, dur);
        }
        player.currentTime = next;
        updateGlobalTransportTimes();
        if (activeDeck && activeDeck.updateTransportTimes) activeDeck.updateTransportTimes();
        updateMediaSessionPosition();
        refreshAllListenProgress();
    }

    function parseSecondsFromMediaUrl(href) {
        if (!href) return null;
        var match = href.match(/[?&]t=(\d+)(?:s\b|$|&)/i);
        if (!match) return null;
        var seconds = parseInt(match[1], 10);
        return isFinite(seconds) ? seconds : null;
    }

    function getEpisodePagePlayButton() {
        var root = document.getElementById('episode-single-player');
        if (!root) return null;
        return root.querySelector('[data-audio-url]');
    }

    function ensureEpisodePageDeck() {
        var root = document.getElementById('episode-single-player');
        if (!root) return activeDeck;
        if (root.getAttribute('data-brp-deck-wired') !== 'true') {
            return window.BrpPlayer.registerDeck('episode-single-player');
        }
        return activeDeck;
    }

    function applyAbsoluteSeek(seconds) {
        if (!player || !isFinite(seconds) || seconds < 0) return;

        var dur = player.duration;
        var target = seconds;
        if (isFinite(dur) && dur > 0) {
            target = Math.min(target, dur);
        }

        player.currentTime = target;
        updateGlobalTransportTimes();
        if (activeDeck && activeDeck.updateTransportTimes) activeDeck.updateTransportTimes();
        updateMediaSessionPosition();
        refreshAllListenProgress();
    }

    function seekEpisodeToSeconds(seconds, options) {
        options = options || {};
        if (!isFinite(seconds) || seconds < 0) return;

        var pageBtn = getEpisodePagePlayButton();
        var pageUrl = pageBtn ? pageBtn.getAttribute('data-audio-url') : '';
        var currentUrl = playerActiveUrl();
        var needsEpisodeLoad = pageUrl && (!currentUrl || !urlsMatchEpisode(pageUrl, currentUrl));

        function startPlayback() {
            if (options.play !== false && player.paused) {
                playEpisode();
            }
        }

        function seekWhenReady() {
            if (player.readyState >= 1) {
                applyAbsoluteSeek(seconds);
                startPlayback();
                return;
            }

            player.addEventListener(
                'loadedmetadata',
                function onMeta() {
                    player.removeEventListener('loadedmetadata', onMeta);
                    applyAbsoluteSeek(seconds);
                    startPlayback();
                }
            );
        }

        if (pageUrl) {
            if (needsEpisodeLoad) {
                var deck = ensureEpisodePageDeck();
                activateEpisode(pageBtn, { userGesture: true, play: options.play !== false }, deck);
            }
            seekWhenReady();
            return;
        }

        if (!player || !player.src) return;
        seekWhenReady();
    }

    function isEmbeddedChapterLink(link) {
        if (!link || !link.getAttribute) return false;
        var href = link.getAttribute('href') || '';
        if (!/youtu(\.be|be\.com)/i.test(href)) return false;
        if (parseSecondsFromMediaUrl(href) == null) return false;

        var body = link.closest('.episode-page__description-body');
        if (!body) return false;

        var section = link.closest('.episode-chapters, ul, ol');
        if (!section) return false;

        if (section.classList && section.classList.contains('episode-chapters')) {
            return true;
        }

        var prev = section.previousElementSibling;
        while (prev) {
            var text = (prev.textContent || '').replace(/\s+/g, ' ').trim();
            if (/^chapters:?$/i.test(text)) {
                return true;
            }
            if (prev.matches && prev.matches('p, h2, h3, h4, section')) {
                break;
            }
            prev = prev.previousElementSibling;
        }

        return false;
    }

    function wireEpisodeChapterSeeks() {
        if (document.body.getAttribute('data-brp-chapter-seeks-wired') === 'true') return;
        document.body.setAttribute('data-brp-chapter-seeks-wired', 'true');

        document.addEventListener('click', function (event) {
            if (!document.body.classList.contains('post-page--episode')) return;

            var seekControl = event.target.closest('[data-brp-chapter-seek]');
            if (seekControl) {
                event.preventDefault();
                var seconds = Number(seekControl.getAttribute('data-brp-chapter-seek'));
                seekEpisodeToSeconds(seconds, { play: true });
                return;
            }

            var chapterLink = event.target.closest('.episode-page__description-body a[href]');
            if (!chapterLink || !isEmbeddedChapterLink(chapterLink)) return;

            var linkSeconds = parseSecondsFromMediaUrl(chapterLink.getAttribute('href'));
            if (linkSeconds == null) return;

            event.preventDefault();
            seekEpisodeToSeconds(linkSeconds, { play: true });
        });
    }

    function wireFullscreenControls() {
        if (!fullscreenRoot || fullscreenRoot.getAttribute('data-brp-fullscreen-wired') === 'true') return;
        fullscreenRoot.setAttribute('data-brp-fullscreen-wired', 'true');

        var openBtn = globalRoot ? globalRoot.querySelector('[data-global-player-fullscreen]') : null;
        var closeBtn = fullscreenRoot.querySelector('[data-fullscreen-close]');
        var fsSkipBack = fullscreenRoot.querySelector('[data-fullscreen-skip-back]');
        var fsSkipForward = fullscreenRoot.querySelector('[data-fullscreen-skip-forward]');

        if (openBtn) {
            openBtn.addEventListener('click', function (e) {
                e.preventDefault();
                e.stopPropagation();
                openPlayerFullscreen();
            });
        }

        if (closeBtn) {
            closeBtn.addEventListener('click', function (e) {
                e.preventDefault();
                e.stopPropagation();
                closePlayerFullscreen();
            });
        }

        if (fullscreenPlay) {
            fullscreenPlay.addEventListener('click', function (e) {
                e.preventDefault();
                e.stopPropagation();
                toggleGlobalPlayback();
            });
        }

        if (fsSkipBack) {
            fsSkipBack.addEventListener('click', function (e) {
                e.preventDefault();
                e.stopPropagation();
                seekGlobalBySeconds(-SKIP_BACK_SEC);
            });
        }

        if (fsSkipForward) {
            fsSkipForward.addEventListener('click', function (e) {
                e.preventDefault();
                e.stopPropagation();
                seekGlobalBySeconds(SKIP_FORWARD_SEC);
            });
        }

        if (fullscreenScrub) {
            fullscreenScrub.addEventListener('input', function () {
                handleGlobalScrubInput(fullscreenScrub);
            });
            fullscreenScrub.addEventListener('change', commitGlobalScrubSeek);
            fullscreenScrub.addEventListener('pointerdown', function () {
                fullscreenScrubbing = true;
            });
            fullscreenScrub.addEventListener('pointerup', commitGlobalScrubSeek);
            fullscreenScrub.addEventListener('pointercancel', cancelGlobalScrubGesture);
        }
    }

    function wireGlobalControls() {
        if (!globalRoot || globalRoot.getAttribute('data-brp-controls-wired') === 'true') return;
        globalRoot.setAttribute('data-brp-controls-wired', 'true');

        var globalSkipBack = globalRoot.querySelector('[data-global-player-skip-back]');
        var globalSkipForward = globalRoot.querySelector('[data-global-player-skip-forward]');

        if (globalPlay) {
            globalPlay.addEventListener('pointerdown', function (e) {
                e.stopPropagation();
            });

            globalPlay.addEventListener('click', function (e) {
                e.preventDefault();
                e.stopPropagation();
                toggleGlobalPlayback();
            });
        }

        if (globalSkipBack) {
            globalSkipBack.addEventListener('click', function (e) {
                e.preventDefault();
                e.stopPropagation();
                seekGlobalBySeconds(-SKIP_BACK_SEC);
            });
        }

        if (globalSkipForward) {
            globalSkipForward.addEventListener('click', function (e) {
                e.preventDefault();
                e.stopPropagation();
                seekGlobalBySeconds(SKIP_FORWARD_SEC);
            });
        }

        var globalNowPlaying = globalRoot.querySelector('[data-global-player-fullscreen-trigger]');
        if (globalNowPlaying) {
            globalNowPlaying.addEventListener('click', function (e) {
                e.preventDefault();
                openPlayerFullscreen();
            });
        }

        if (globalScrub) {
            globalScrub.addEventListener('input', function () {
                handleGlobalScrubInput(globalScrub);
            });

            globalScrub.addEventListener('change', commitGlobalScrubSeek);

            globalScrub.addEventListener('pointerdown', function () {
                globalScrubbing = true;
            });

            globalScrub.addEventListener('pointerup', commitGlobalScrubSeek);
            globalScrub.addEventListener('pointercancel', cancelGlobalScrubGesture);
        }

        wireFullscreenControls();
    }

    function wireEngineEvents() {
        if (!player || player.getAttribute('data-brp-engine-wired') === 'true') return;
        player.setAttribute('data-brp-engine-wired', 'true');

        player.playsInline = true;
        player.setAttribute('playsinline', '');

        player.addEventListener('loadedmetadata', function () {
            applyResumeIfNeeded();
            restorePlaybackMeta();
            renderGlobalBarFromMeta();
            if (isPlaybackActive()) refreshMediaSessionFromPlayback();
            updateGlobalTransportTimes();
            if (activeDeck && activeDeck.updateTransportTimes) activeDeck.updateTransportTimes();
            refreshAllListenProgress();
        });

        player.addEventListener('durationchange', function () {
            var url = playerActiveUrl();
            if (url && resumeAppliedForSrc !== url) applyResumeIfNeeded();
            updateGlobalTransportTimes();
            if (activeDeck && activeDeck.updateTransportTimes) activeDeck.updateTransportTimes();
            refreshAllListenProgress();
        });

        player.addEventListener('timeupdate', function () {
            if (!globalScrubbing) updateGlobalTransportTimes();
            if (activeDeck && activeDeck.onTimeUpdate) activeDeck.onTimeUpdate();
            if (!player.paused) updateMediaSessionPosition();
            if (!player.paused) {
                var now = Date.now();
                if (now - lastTimeupdateSave >= TIMEUPDATE_SAVE_MS) {
                    lastTimeupdateSave = now;
                    var uSave = playerActiveUrl();
                    if (uSave) saveProgressForUrl(uSave, player.currentTime, player.duration);
                }
            }
        });

        player.addEventListener('play', function () {
            if (activeDeck && activeDeck.onPlayStateChange) activeDeck.onPlayStateChange();
            setMediaSessionPlaybackState('playing');
            updateMediaSessionMetadata();
            updateMediaSessionPosition();
            syncGlobalBarFromMeta();
            refreshAllListenProgress();
        });

        player.addEventListener('pause', function () {
            if (activeDeck && activeDeck.onPlayStateChange) activeDeck.onPlayStateChange();
            setMediaSessionPlaybackState('paused');
            var u = playerActiveUrl();
            if (u) {
                if (isIOS) iosMediaSessionResumeTime = player.currentTime;
                saveProgressForUrl(u, player.currentTime, player.duration);
            }
            notifyUserSync(true);
            syncGlobalBarFromMeta();
            refreshAllListenProgress();
            if (isIOS) refreshMediaSessionHandlersForIOS();
        });

        player.addEventListener('seeked', function () {
            var u = playerActiveUrl();
            if (u) saveProgressForUrl(u, player.currentTime, player.duration);
            notifyUserSync(true);
            updateGlobalTransportTimes();
            if (activeDeck && activeDeck.updateTransportTimes) activeDeck.updateTransportTimes();
            updateMediaSessionPosition();
            refreshAllListenProgress();
        });

        player.addEventListener('ended', function () {
            if (activeDeck && activeDeck.onEnded) activeDeck.onEnded();
            setMediaSessionPlaybackState('paused');
            var u = playerActiveUrl();
            if (u) {
                markProgressComplete(u, player.duration);
                clearLastListenedIfUrl(u);
                notifyUserSync(true);
            }
            resumeAppliedForSrc = '';
            syncGlobalBarFromMeta();
            refreshAllListenProgress();
            dispatchPlaybackEnded(u);
        });

        player.addEventListener('stalled', function () {
            if (isIOS && !player.paused && !player.ended) recoverPlaybackAfterBackground();
        });

        player.addEventListener('waiting', function () {
            if (isIOS && !player.paused && !player.ended) {
                window.setTimeout(function () {
                    if (!player.paused && !player.ended && player.readyState < 3) {
                        recoverPlaybackAfterBackground();
                    }
                }, 1200);
            }
        });

        window.addEventListener('pagehide', function () {
            var u = playerActiveUrl();
            if (u && !player.ended) saveProgressForUrl(u, player.currentTime, player.duration);
            savePlaybackHandoff();
            notifyUserSync(true);
            if (activeDeck && activeDeck.suspendWaveAudioContext) activeDeck.suspendWaveAudioContext();
        });

        document.addEventListener('visibilitychange', function () {
            if (document.visibilityState === 'hidden') {
                var hiddenUrl = playerActiveUrl();
                if (hiddenUrl && !player.paused && !player.ended) {
                    saveProgressForUrl(hiddenUrl, player.currentTime, player.duration);
                }
                refreshMediaSessionFromPlayback();
                savePlaybackHandoff();
                notifyUserSync(true);
                if (activeDeck && activeDeck.suspendWaveAudioContext) activeDeck.suspendWaveAudioContext();
                return;
            }
            if (player.paused || player.ended || !player.src) {
                if (isIOS && player && player.src) refreshMediaSessionHandlersForIOS();
                return;
            }
            if (activeDeck && activeDeck.resumeWaveAudioContext) activeDeck.resumeWaveAudioContext();
            if (isIOS) recoverPlaybackAfterBackground();
        });

        document.addEventListener('brp-user-synced', function () {
            refreshAllListenProgress();
        });

        setupMediaSessionHandlers();
        wireEpisodeChapterSeeks();
    }

    function activateEpisode(button, options, deck) {
        options = options || {};
        var userGesture = !!options.userGesture;
        var shouldPlay = options.play !== false;

        var audioUrl = button.getAttribute('data-audio-url');
        var episodeTitle = button.getAttribute('data-episode-title') || 'Episode';
        var podcastTitle = button.getAttribute('data-podcast-title') || 'Podcast';
        var coverUrl = button.getAttribute('data-cover-url') || '';
        if (!coverUrl) {
            coverUrl = coverUrlFromPlayButton(button);
        }
        var metaUrls = readMetaUrlsFromButton(button);
        var clickedLi = button.closest('.latest-episodes__item');

        if (!audioUrl) return;

        var playerEpisode = playerActiveUrl();
        var switchingEpisode = !urlsMatchEpisode(audioUrl, playerEpisode);
        if (switchingEpisode && !shouldPlay && !userGesture && (playerEpisode || isPlaybackActive())) {
            return;
        }

        if (deck) {
            activeDeck = deck;
            document.body.classList.add('brp-deck-active');
        }

        if (
            userGesture &&
            !switchingEpisode &&
            deck &&
            ((deck.currentLi && clickedLi === deck.currentLi) ||
                (deck.stickyOnly && clickedLi && deck.currentLi === clickedLi))
        ) {
            if (!player.paused) {
                player.pause();
            } else {
                playEpisode();
            }
            if (deck.onPlayStateChange) deck.onPlayStateChange();
            return;
        }

        if (deck) {
            deck.clearCurrent();
            deck.currentLi = clickedLi;
            if (deck.currentLi) {
                deck.currentLi.classList.add('latest-episodes__item--current');
            }
            deck.updateArt(coverUrl);
            deck.setNowPlaying(
            episodeTitle,
            podcastTitle,
            Object.prototype.hasOwnProperty.call(options, 'kicker')
                ? options.kicker
                : shouldPlay || userGesture
                  ? 'Now playing'
                  : 'Continue listening',
            metaUrls.episodePageUrl,
            metaUrls.podcastPageUrl
        );
        }

        if (switchingEpisode) {
            resumeAppliedForSrc = '';
            if (deck && deck.resetAudioGraph) deck.resetAudioGraph();
            setEpisodeSource(audioUrl);
        }

        rememberEpisodeMeta(
            episodeTitle,
            podcastTitle,
            coverUrl,
            audioUrl,
            metaUrls.episodePageUrl,
            metaUrls.podcastPageUrl
        );
        saveLastListened(audioUrl, episodeTitle, podcastTitle, coverUrl);

        if (shouldPlay) {
            playEpisode();
        } else if (deck && deck.onPlayStateChange) {
            deck.onPlayStateChange();
        }

        if (deck && deck.updateTransportTimes) deck.updateTransportTimes();
        syncGlobalBarFromMeta();
        refreshAllListenProgress();
        dispatchEpisodeActivated({
            episodeTitle: episodeTitle,
            podcastTitle: podcastTitle,
            coverUrl: coverUrl,
            audioUrl: audioUrl,
            episodePageUrl: metaUrls.episodePageUrl,
            podcastPageUrl: metaUrls.podcastPageUrl,
        });
    }

    function dispatchEpisodeActivated(meta) {
        if (!meta || !meta.audioUrl) return;
        try {
            document.dispatchEvent(
                new CustomEvent('brp-episode-activated', {
                    detail: { meta: meta },
                })
            );
        } catch (e) {}
    }

    function dispatchPlaybackEnded(url) {
        if (!url) return;
        try {
            document.dispatchEvent(
                new CustomEvent('brp-playback-ended', {
                    detail: {
                        url: url,
                        meta: {
                            episodeTitle: currentMeta.episodeTitle,
                            podcastTitle: currentMeta.podcastTitle,
                            coverUrl: currentMeta.coverUrl,
                            audioUrl: url,
                            episodePageUrl: currentMeta.episodePageUrl,
                            podcastPageUrl: currentMeta.podcastPageUrl,
                        },
                    },
                })
            );
        } catch (e) {}
    }

    function activateFromMeta(meta, options) {
        options = options || {};
        if (!meta || !meta.audioUrl) return false;
        initEngine();
        var btn = findPlayButtonForUrl(document, meta.audioUrl);
        if (btn) {
            activateEpisode(btn, options, activeDeck);
            return true;
        }

        var switchingEpisode = !urlsMatchEpisode(meta.audioUrl, playerActiveUrl());
        if (switchingEpisode) {
            resumeAppliedForSrc = '';
            if (activeDeck && activeDeck.resetAudioGraph) activeDeck.resetAudioGraph();
            setEpisodeSource(meta.audioUrl);
        }
        rememberEpisodeMeta(
            meta.episodeTitle,
            meta.podcastTitle,
            meta.coverUrl,
            meta.audioUrl,
            meta.episodePageUrl,
            meta.podcastPageUrl
        );
        saveLastListened(meta.audioUrl, meta.episodeTitle, meta.podcastTitle, meta.coverUrl);
        if (options.play !== false) {
            playEpisode();
        }
        syncGlobalBarFromMeta();
        refreshAllListenProgress();
        dispatchEpisodeActivated(meta);
        return true;
    }

    function coverUrlFromPlayButton(button) {
        if (!button) return '';
        var coverUrl = button.getAttribute('data-cover-url') || '';
        if (coverUrl) return coverUrl;
        var coverImg = button.closest('.latest-episodes__item, .latest-episodes__episode-stack, .latest-episodes__episode-card');
        if (!coverImg) return '';
        var img = coverImg.querySelector('.latest-episodes__cover, img[data-cover-src]');
        if (!img) return '';
        return img.getAttribute('data-cover-src') || img.currentSrc || img.getAttribute('src') || '';
    }

    function findFirstListEpisodeButton(root) {
        if (!root) return null;
        return root.querySelector('.latest-episodes__list .latest-episodes__item:not([hidden]) [data-audio-url]');
    }

    function shouldResumeLastEpisode(last, root) {
        if (!last || !last.url) return false;
        if (isProgressComplete(getSavedProgressRow(last.url))) return false;
        if (!findPlayButtonForUrl(root, last.url)) return false;
        var t = getSavedProgressSeconds(last.url);
        if (t == null && (!last.u || Date.now() - last.u > 1000 * 60 * 60 * 24 * 14)) return false;
        return true;
    }

    function primeDeckEpisodePreview(button, deck, kickerLabel) {
        if (!button || !deck) return false;
        if (isPlaybackActive()) return false;

        var audioUrl = button.getAttribute('data-audio-url');
        if (!audioUrl) return false;

        var meta = metaFromPlayButton(button, audioUrl);
        var coverUrl = coverUrlFromPlayButton(button) || meta.coverUrl;
        var clickedLi = button.closest('.latest-episodes__item');

        deck.clearCurrent();
        deck.currentLi = clickedLi;
        if (deck.currentLi) deck.currentLi.classList.add('latest-episodes__item--current');
        if (deck.updateArt) deck.updateArt(coverUrl);
        if (deck.setNowPlaying) {
            deck.setNowPlaying(
                meta.episodeTitle,
                meta.podcastTitle,
                kickerLabel || 'Latest episode',
                meta.episodePageUrl,
                meta.podcastPageUrl
            );
        }
        rememberEpisodeMeta(
            meta.episodeTitle,
            meta.podcastTitle,
            coverUrl,
            audioUrl,
            meta.episodePageUrl,
            meta.podcastPageUrl
        );
        setEpisodeSource(audioUrl);
        try {
            player.preload = 'metadata';
        } catch (e) {}
        if (deck.updateTransportTimes) deck.updateTransportTimes();
        if (deck.syncDeckPlayButton) deck.syncDeckPlayButton();
        return true;
    }

    function primeLatestEpisodePreview(deck, root) {
        var btn = findFirstListEpisodeButton(root);
        if (!btn) return false;
        return primeDeckEpisodePreview(btn, deck, 'Latest episode');
    }

    function isModifiedNavigationClick(event) {
        return event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey;
    }

    function isFeedEpisodeClickExempt(target) {
        if (!target || !target.closest) return false;
        return !!(
            target.closest('a.latest-episodes__podcast-link') ||
            target.closest('[data-episode-actions]')
        );
    }

    function isFeedCardItem(item) {
        if (!item) return false;
        if (item.classList.contains('latest-episodes__feed-day')) return false;
        if (item.classList.contains('latest-episodes__empty')) return false;
        if (item.classList.contains('latest-episodes__item--promo')) return false;
        return !!item.querySelector('.latest-episodes__episode-card');
    }

    function openFeedEpisodeModal(item, deck) {
        var playBtn = item ? item.querySelector('[data-audio-url]') : null;
        if (!playBtn) return;
        var audioUrl = playBtn.getAttribute('data-audio-url');
        if (!audioUrl) return;

        var sameEpisode = urlsMatchEpisode(audioUrl, playerActiveUrl());
        if (!sameEpisode) {
            activateEpisode(playBtn, { userGesture: true, play: true }, deck);
        } else {
            if (deck) {
                deck.clearCurrent();
                deck.currentLi = item;
                if (deck.currentLi) deck.currentLi.classList.add('latest-episodes__item--current');
            }
            if (player.paused && !player.ended) {
                playEpisode();
            }
            if (deck && deck.onPlayStateChange) deck.onPlayStateChange();
        }

        openPlayerFullscreen();
    }

    function wireStickyOnlyDeck(root) {
        root.setAttribute('data-brp-deck-wired', 'true');

        var deck = {
            root: root,
            currentLi: null,
            stickyOnly: true,
            clearCurrent: clearCurrent,
            updateArt: function () {},
            setNowPlaying: function () {},
            updateTransportTimes: function () {},
            resetAudioGraph: function () {},
            suspendWaveAudioContext: function () {},
            resumeWaveAudioContext: function () {},
            onPlayStateChange: onPlayStateChange,
            onTimeUpdate: onTimeUpdate,
            onEnded: onEnded,
        };

        function clearCurrent() {
            root.querySelectorAll('.latest-episodes__item--current').forEach(function (el) {
                el.classList.remove('latest-episodes__item--current', 'latest-episodes__item--playing');
            });
            root.querySelectorAll('.latest-episodes__play').forEach(function (el) {
                el.classList.remove('latest-episodes__play--playing');
                el.setAttribute('aria-pressed', 'false');
            });
            deck.currentLi = null;
        }

        function findButtonForStoredUrl(storedUrl) {
            return findPlayButtonForUrl(root, storedUrl);
        }

        function syncListPlayingState() {
            var playing = !player.paused && !player.ended;
            var btn = deck.currentLi ? deck.currentLi.querySelector('.latest-episodes__play') : null;
            if (!btn && deck.currentLi && deck.currentLi.classList.contains('latest-episodes__item--solo')) {
                btn = deck.currentLi.querySelector('[data-audio-url]');
            }
            if (deck.currentLi) {
                deck.currentLi.classList.toggle('latest-episodes__item--playing', playing);
            }
            if (btn) {
                btn.classList.toggle('latest-episodes__play--playing', playing);
                btn.setAttribute('aria-pressed', playing ? 'true' : 'false');
                var label = btn.querySelector('.episode-page__listen-label');
                if (label) {
                    label.textContent = playing ? 'Pause episode' : 'Play episode';
                }
                if (btn.classList.contains('episode-page__listen-btn')) {
                    btn.setAttribute('aria-label', playing ? 'Pause episode' : 'Play episode');
                }
            }
        }

        function syncListFromPlayer() {
            var url = playerActiveUrl();
            clearCurrent();
            if (!url) return;
            var btn = findButtonForStoredUrl(url);
            if (!btn) return;
            deck.currentLi = btn.closest('.latest-episodes__item');
            if (deck.currentLi) deck.currentLi.classList.add('latest-episodes__item--current');
            syncListPlayingState();
        }

        function onPlayStateChange() {
            syncListPlayingState();
            syncGlobalBarFromMeta();
        }

        function onTimeUpdate() {
            if (deck.currentLi) {
                var curBtn = deck.currentLi.querySelector('[data-audio-url]');
                if (curBtn) updateListenProgressForButton(curBtn);
            }
        }

        function onEnded() {
            syncListPlayingState();
        }

        root.addEventListener('click', function (event) {
            if (isFeedEpisodeClickExempt(event.target)) return;

            var item = event.target.closest('.latest-episodes__item');
            if (!isFeedCardItem(item)) return;

            var button = event.target.closest('[data-audio-url]');
            var hitLink = event.target.closest('a.latest-episodes__episode-hit');
            if (!button && !hitLink) return;

            if (hitLink && isModifiedNavigationClick(event)) return;

            event.preventDefault();
            event.stopPropagation();

            if (button) {
                var audioUrl = button.getAttribute('data-audio-url');
                var sameEpisode = urlsMatchEpisode(audioUrl, playerActiveUrl());
                var willTogglePause =
                    sameEpisode && deck.currentLi === item && !player.paused && !player.ended;
                activateEpisode(button, { userGesture: true, play: true }, deck);
                if (!willTogglePause) openPlayerFullscreen();
                return;
            }

            openFeedEpisodeModal(item, deck);
        });

        syncListFromPlayer();
        activeDeck = deck;
        document.body.classList.add('brp-deck-active');
        refreshAllListenProgress();
        updateGlobalBarVisibility();

        (function restoreDeckListenState() {
            if (playerActiveUrl()) {
                syncListFromPlayer();
                syncGlobalBarFromMeta();
                return;
            }

            if (root.classList.contains('latest-episodes--episode-page')) {
                var pageBtn = root.querySelector('[data-audio-url]');
                if (!pageBtn) return;
                var pageUrl = pageBtn.getAttribute('data-audio-url');
                if (!pageUrl) return;
                var lastEpisode = loadLastListened();
                var saved = getSavedProgressRow(pageUrl);
                var shouldPrime =
                    (lastEpisode && urlsMatch(lastEpisode.url, pageUrl)) ||
                    (saved && !isProgressComplete(saved) && saved.t >= MIN_RESUME_SEC);
                if (!shouldPrime) return;
                activateEpisode(pageBtn, { userGesture: false, play: false, kicker: 'Continue listening' }, deck);
                return;
            }

            var last = loadLastListened();
            if (!last || !last.url) return;
            if (isProgressComplete(getSavedProgressRow(last.url))) return;

            var btn = findButtonForStoredUrl(last.url);
            if (btn) {
                if (last.coverUrl && !btn.getAttribute('data-cover-url')) {
                    btn.setAttribute('data-cover-url', last.coverUrl);
                }
                activateEpisode(btn, { userGesture: false, play: false, kicker: 'Continue listening' }, deck);
                return;
            }

            var savedSeconds = getSavedProgressSeconds(last.url);
            if (savedSeconds == null && (!last.u || Date.now() - last.u > 1000 * 60 * 60 * 24 * 14)) return;

            applyMetaFully(
                {
                    episodeTitle: last.episodeTitle,
                    podcastTitle: last.podcastTitle,
                    coverUrl: last.coverUrl,
                },
                last.url
            );
            rememberEpisodeMeta(
                last.episodeTitle,
                last.podcastTitle,
                last.coverUrl,
                last.url,
                '',
                ''
            );
            resumeAppliedForSrc = '';
            setEpisodeSource(last.url);
            try {
                player.preload = 'metadata';
            } catch (e) {}
            syncGlobalBarFromMeta();
        })();

        return deck;
    }

    function createDeck(sectionId) {
        var root = document.getElementById(sectionId);
        if (!root || root.getAttribute('data-brp-deck-wired') === 'true') return null;

        if (root.classList.contains('latest-episodes--sticky-only')) {
            return wireStickyOnlyDeck(root);
        }

        var nowPlaying = root.querySelector('[data-now-playing]');
        var art = root.querySelector('[data-player-art]');
        var artWrap = root.querySelector('[data-player-art-wrap]');
        var transport = root.querySelector('[data-player-transport]');
        var deckPlay = root.querySelector('[data-deck-play]');
        var deckSkipBack = root.querySelector('[data-deck-skip-back]');
        var deckSkipForward = root.querySelector('[data-deck-skip-forward]');
        var scrubInput = root.querySelector('[data-player-scrub]');
        var scrubProgress = root.querySelector('[data-player-scrub-progress]');
        var currentEl = root.querySelector('[data-player-current]');
        var durationEl = root.querySelector('[data-player-duration]');
        var waveCanvas = root.querySelector('[data-player-waves]');

        if (!nowPlaying) return null;

        root.setAttribute('data-brp-deck-wired', 'true');

        var prefersReducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
        var waveUsesFallbackMotion = false;
        var currentLi = null;
        var scrubbing = false;
        var waveCtx = waveCanvas ? waveCanvas.getContext('2d') : null;
        var audioCtx = null;
        var analyser = null;
        var waveSource = null;
        var waveAnimId = null;
        var waveResizeObserver = null;
        var freqBuffer = null;
        var timeBuffer = null;
        var waveHeights = null;
        var waveColumnCount = 64;
        var waveTapReady = false;

        var deck = {
            root: root,
            currentLi: null,
            clearCurrent: clearCurrent,
            updateArt: updateArt,
            setNowPlaying: setNowPlaying,
            updateTransportTimes: updateTransportTimes,
            syncDeckPlayButton: syncDeckPlayButton,
            resetAudioGraph: resetAudioGraph,
            suspendWaveAudioContext: suspendWaveAudioContext,
            resumeWaveAudioContext: resumeWaveAudioContext,
            onPlayStateChange: onPlayStateChange,
            onTimeUpdate: onTimeUpdate,
            onEnded: onEnded,
        };

        function clearCurrent() {
            root.querySelectorAll('.latest-episodes__item--current').forEach(function (el) {
                el.classList.remove('latest-episodes__item--current', 'latest-episodes__item--playing');
            });
            root.querySelectorAll('.latest-episodes__play').forEach(function (el) {
                el.classList.remove('latest-episodes__play--playing');
                el.setAttribute('aria-pressed', 'false');
            });
            deck.currentLi = null;
        }

        function showTransport() {
            if (transport) transport.hidden = false;
        }

        function syncDeckPlayButton() {
            if (!deckPlay) return;
            var playing = !player.paused && !player.ended;
            deckPlay.classList.toggle('latest-episodes__deck-play--playing', playing);
            deckPlay.setAttribute('aria-pressed', playing ? 'true' : 'false');
            deckPlay.setAttribute('aria-label', playing ? 'Pause' : 'Play');
        }

        function resetAudioGraph() {
            stopWaveAnimation();
            waveTapReady = false;
            waveUsesFallbackMotion = false;
            if (waveSource) {
                try {
                    waveSource.disconnect();
                } catch (e) {}
                waveSource = null;
            }
            analyser = null;
            freqBuffer = null;
            timeBuffer = null;
            waveHeights = null;
        }

        function suspendWaveAudioContext() {
            if (!audioCtx || audioCtx.state !== 'running') return;
            audioCtx.suspend().catch(function () {});
        }

        function resumeWaveAudioContext() {
            if (!audioCtx || audioCtx.state !== 'suspended') return;
            audioCtx.resume().catch(function () {});
        }

        function ensureAudioContext() {
            if (audioCtx) return audioCtx;
            var AC = window.AudioContext || window.webkitAudioContext;
            if (!AC) return null;
            audioCtx = new AC();
            return audioCtx;
        }

        function buildAnalyserNode(ctx) {
            if (analyser && freqBuffer && timeBuffer && waveHeights) return;
            analyser = ctx.createAnalyser();
            analyser.fftSize = 512;
            analyser.smoothingTimeConstant = 0.52;
            analyser.minDecibels = -88;
            analyser.maxDecibels = -28;
            freqBuffer = new Uint8Array(analyser.frequencyBinCount);
            timeBuffer = new Uint8Array(analyser.fftSize);
            waveHeights = new Float32Array(waveColumnCount);
        }

        function connectStreamAnalyser(ctx) {
            if (waveSource) return true;
            var capture =
                typeof player.captureStream === 'function'
                    ? player.captureStream.bind(player)
                    : typeof player.mozCaptureStream === 'function'
                      ? player.mozCaptureStream.bind(player)
                      : null;
            if (!capture) return false;
            if (player.paused || player.ended) return false;
            try {
                var stream = capture();
                if (!stream || stream.getAudioTracks().length === 0) return false;
                waveSource = ctx.createMediaStreamSource(stream);
                waveSource.connect(analyser);
                return true;
            } catch (e) {
                return false;
            }
        }

        function ensureWaveAnalyser() {
            if (isIOS) return false;
            if (waveTapReady && analyser && waveSource) {
                resumeWaveAudioContext();
                return true;
            }
            var ctx = ensureAudioContext();
            if (!ctx) return false;
            buildAnalyserNode(ctx);
            if (connectStreamAnalyser(ctx)) {
                waveTapReady = true;
                waveUsesFallbackMotion = false;
                resumeWaveAudioContext();
                return true;
            }
            return false;
        }

        function refreshAudioSamples() {
            if (waveUsesFallbackMotion) return true;
            if (!analyser || !freqBuffer || !timeBuffer) return false;
            analyser.getByteFrequencyData(freqBuffer);
            analyser.getByteTimeDomainData(timeBuffer);
            return true;
        }

        function ensureWaveHeights() {
            if (!waveHeights) waveHeights = new Float32Array(waveColumnCount);
        }

        function updateWaveColumnsFallback() {
            ensureWaveHeights();
            var t = performance.now() / 1000;
            for (var c = 0; c < waveColumnCount; c++) {
                var nx = c / (waveColumnCount - 1);
                var target =
                    0.05 +
                    0.09 * Math.abs(Math.sin(t * 1.6 + nx * 5.1)) +
                    0.05 * Math.abs(Math.sin(t * 0.85 + nx * 2.4));
                var current = waveHeights[c];
                var k = target > current ? 0.55 : 0.42;
                waveHeights[c] = current + (target - current) * k;
            }
            return true;
        }

        function resizeWaveCanvas() {
            if (!waveCanvas || !waveCtx) return;
            var shell = waveCanvas.parentElement;
            if (!shell) return;
            var dpr = Math.min(window.devicePixelRatio || 1, 2);
            var w = shell.clientWidth;
            var h = shell.clientHeight;
            if (w <= 0 || h <= 0) return;
            waveCanvas.width = Math.round(w * dpr);
            waveCanvas.height = Math.round(h * dpr);
            waveCanvas.style.width = w + 'px';
            waveCanvas.style.height = h + 'px';
            waveCtx.setTransform(dpr, 0, 0, dpr, 0, 0);
        }

        function freqLevelAt(nx) {
            if (!freqBuffer || freqBuffer.length === 0) return 0;
            var t = nx * 0.72 + nx * nx * 0.28;
            var idx = Math.min(freqBuffer.length - 1, Math.floor(t * freqBuffer.length * 0.9));
            var sum = 0;
            var weight = 0;
            for (var i = -2; i <= 2; i++) {
                var j = idx + i;
                if (j < 0 || j >= freqBuffer.length) continue;
                var w = i === 0 ? 0.42 : 0.145;
                sum += freqBuffer[j] * w;
                weight += w;
            }
            return weight > 0 ? sum / weight / 255 : 0;
        }

        function compressWaveLevel(raw) {
            var x = Math.max(0, Math.min(1, raw));
            return Math.pow(x, 0.78) * 0.52;
        }

        function timeRmsLevel() {
            if (!timeBuffer || timeBuffer.length === 0) return 0;
            var rms = 0;
            for (var i = 0; i < timeBuffer.length; i++) {
                var sample = (timeBuffer[i] - 128) / 128;
                rms += sample * sample;
            }
            rms = Math.sqrt(rms / timeBuffer.length);
            return Math.min(1, rms * 2.1);
        }

        function updateWaveColumns() {
            ensureWaveHeights();
            if (waveUsesFallbackMotion) {
                updateWaveColumnsFallback();
                return;
            }
            if (!refreshAudioSamples()) return;
            var rms = timeRmsLevel();
            for (var c = 0; c < waveColumnCount; c++) {
                var nx = c / (waveColumnCount - 1);
                var freq = freqLevelAt(nx);
                var target = compressWaveLevel(freq * 0.9 + rms * 0.12);
                var current = waveHeights[c];
                var k = target > current ? 0.72 : 0.48;
                waveHeights[c] = current + (target - current) * k;
            }
        }

        function columnHeightAt(nx) {
            if (!waveHeights || waveHeights.length === 0) return 0;
            var pos = nx * (waveColumnCount - 1);
            var idx = Math.min(waveColumnCount - 1, Math.floor(pos));
            var next = Math.min(waveColumnCount - 1, idx + 1);
            var t = pos - idx;
            return waveHeights[idx] * (1 - t) + waveHeights[next] * t;
        }

        function drawWaves() {
            if (!waveCanvas || !waveCtx) return;
            var w = waveCanvas.clientWidth;
            var h = waveCanvas.clientHeight;
            if (w <= 0 || h <= 0) return;
            if (!waveTapReady) {
                ensureWaveAnalyser();
                if (!waveTapReady && !waveUsesFallbackMotion) {
                    waveUsesFallbackMotion = true;
                    ensureWaveHeights();
                }
            }
            updateWaveColumns();
            var layers = [
                { color: 'rgba(29, 29, 29, 0.05)', base: 0.9, lift: 0.24 },
                { color: 'rgba(30, 215, 96, 0.07)', base: 0.93, lift: 0.19 },
                { color: 'rgba(184, 67, 47, 0.04)', base: 0.96, lift: 0.14 },
            ];
            waveCtx.clearRect(0, 0, w, h);
            for (var li = 0; li < layers.length; li++) {
                var layer = layers[li];
                waveCtx.beginPath();
                waveCtx.moveTo(0, h);
                for (var x = 0; x <= w; x += 2) {
                    var nx = x / w;
                    var col = columnHeightAt(nx);
                    var y = h * layer.base - col * h * layer.lift;
                    waveCtx.lineTo(x, y);
                }
                waveCtx.lineTo(w, h);
                waveCtx.closePath();
                waveCtx.fillStyle = layer.color;
                waveCtx.fill();
            }
        }

        function stopWaveAnimation() {
            if (waveAnimId) {
                cancelAnimationFrame(waveAnimId);
                waveAnimId = null;
            }
            root.classList.remove('latest-episodes--waves-active');
            suspendWaveAudioContext();
            if (waveCtx && waveCanvas) {
                waveCtx.clearRect(0, 0, waveCanvas.clientWidth, waveCanvas.clientHeight);
            }
        }

        function startWaveAnimation() {
            if (prefersReducedMotion || !waveCanvas || !waveCtx) return;
            resizeWaveCanvas();
            root.classList.add('latest-episodes--waves-active');
            ensureWaveHeights();
            if (!isIOS) {
                if (!waveTapReady) {
                    ensureWaveAnalyser();
                    if (!waveTapReady) waveUsesFallbackMotion = true;
                } else {
                    resumeWaveAudioContext();
                }
            } else {
                waveUsesFallbackMotion = true;
            }
            if (waveAnimId) return;
            function loop() {
                if (player.paused || player.ended) {
                    stopWaveAnimation();
                    return;
                }
                if (!waveTapReady && !waveUsesFallbackMotion) ensureWaveAnalyser();
                drawWaves();
                waveAnimId = requestAnimationFrame(loop);
            }
            waveAnimId = requestAnimationFrame(loop);
        }

        if (waveCanvas && typeof ResizeObserver !== 'undefined') {
            var shell = waveCanvas.parentElement;
            if (shell) {
                waveResizeObserver = new ResizeObserver(function () {
                    if (root.classList.contains('latest-episodes--waves-active')) resizeWaveCanvas();
                });
                waveResizeObserver.observe(shell);
            }
        }

        function updateScrubVisual(pct) {
            var clamped = Math.min(100, Math.max(0, pct));
            if (scrubProgress) scrubProgress.style.width = clamped + '%';
        }

        function updateTransportTimes() {
            var dur = player.duration;
            var cur = player.currentTime;
            if (currentEl) currentEl.textContent = formatTime(cur);
            if (durationEl) durationEl.textContent = isFinite(dur) && dur > 0 ? formatTime(dur) : '0:00';
            if (scrubInput && isFinite(dur) && dur > 0 && !scrubbing) {
                var scaled = Math.round((cur / dur) * 1000);
                scrubInput.value = String(scaled);
                scrubInput.setAttribute('aria-valuenow', String(scaled));
                scrubInput.setAttribute('aria-valuetext', formatTime(cur) + ' of ' + formatTime(dur));
                updateScrubVisual((cur / dur) * 100);
            }
        }

        function setNowPlaying(episodeTitle, podcastTitle, kickerLabel, episodePageUrl, podcastPageUrl) {
            episodePageUrl = (episodePageUrl || currentMeta.episodePageUrl || '').trim();
            podcastPageUrl = (podcastPageUrl || currentMeta.podcastPageUrl || '').trim();
            var episodeHtml = metaLinkHtml(
                episodeTitle,
                episodePageUrl,
                'latest-episodes__now-playing-episode-link',
                'latest-episodes__now-playing-episode'
            );
            var showHtml = metaLinkHtml(
                podcastTitle,
                podcastPageUrl,
                'latest-episodes__now-playing-show-link',
                'latest-episodes__now-playing-show'
            );
            nowPlaying.classList.remove('latest-episodes__now-playing--idle');
            if (kickerLabel === false) {
                nowPlaying.innerHTML =
                    '<span class="latest-episodes__now-playing-line">' + episodeHtml + '</span>';
                showTransport();
                return;
            }
            kickerLabel = kickerLabel || 'Now playing';
            nowPlaying.innerHTML =
                '<span class="latest-episodes__now-playing-kicker">' +
                kickerLabel +
                '</span><span class="latest-episodes__now-playing-line">' +
                episodeHtml +
                '<span class="latest-episodes__now-playing-sep"> — </span>' +
                showHtml +
                '</span>';
            showTransport();
        }

        function updatePictureSource(url) {
            if (!art) return;
            var picture = art.closest('picture');
            if (!picture) return;
            var source = picture.querySelector('source');
            if (!source) return;
            var value = (url || '').trim();
            var path = '';
            try {
                path = value ? new URL(value, window.location.href).pathname : '';
            } catch (e) {
                path = String(value).split(/[?#]/)[0];
            }
            var srcset = '';
            if (value && path && !/\.webp$/i.test(path) && !/^[a-z][a-z0-9+.-]*:\/\//i.test(value)) {
                if (/\.(jpe?g|png)$/i.test(path)) {
                    srcset = value.replace(/\.(jpe?g|png)(?=([?#]|$))/i, '.webp');
                }
            }
            if (srcset) {
                source.setAttribute('type', 'image/webp');
                source.setAttribute('srcset', srcset);
            } else {
                source.removeAttribute('srcset');
            }
        }

        function updateArt(url) {
            if (!art || !artWrap) return;
            var effective = (url || '').trim();
            if (effective) {
                updatePictureSource(effective);
                art.src = effective;
                art.removeAttribute('hidden');
                artWrap.classList.remove('latest-episodes__player-art-wrap--empty');
            } else {
                updatePictureSource('');
                art.removeAttribute('src');
                art.setAttribute('hidden', '');
                artWrap.classList.add('latest-episodes__player-art-wrap--empty');
            }
        }

        function syncPlayingClass() {
            if (!deck.currentLi) return;
            if (!player.paused) {
                deck.currentLi.classList.add('latest-episodes__item--playing');
                var btn = deck.currentLi.querySelector('.latest-episodes__play');
                if (btn) {
                    btn.classList.add('latest-episodes__play--playing');
                    btn.setAttribute('aria-pressed', 'true');
                }
            } else {
                deck.currentLi.classList.remove('latest-episodes__item--playing');
                var btn2 = deck.currentLi.querySelector('.latest-episodes__play');
                if (btn2) {
                    btn2.classList.remove('latest-episodes__play--playing');
                    btn2.setAttribute('aria-pressed', 'false');
                }
            }
            syncDeckPlayButton();
        }

        function onPlayStateChange() {
            if (!deckOwnsActiveEpisode()) {
                root.classList.remove('latest-episodes--transport-active');
                stopWaveAnimation();
                syncGlobalBarFromMeta();
                return;
            }
            if (!player.paused) {
                root.classList.add('latest-episodes--transport-active');
                var kick = nowPlaying.querySelector('.latest-episodes__now-playing-kicker');
                if (kick && kick.textContent.trim() === 'Continue listening') {
                    kick.textContent = 'Now playing';
                }
                startWaveAnimation();
            } else {
                root.classList.remove('latest-episodes--transport-active');
                stopWaveAnimation();
            }
            syncPlayingClass();
            syncGlobalBarFromMeta();
        }

        function onTimeUpdate() {
            if (!deckOwnsActiveEpisode()) return;
            if (!scrubbing) updateTransportTimes();
            if (deck.currentLi) {
                var curBtn = deck.currentLi.querySelector('[data-audio-url]');
                if (curBtn) updateListenProgressForButton(curBtn);
            }
        }

        function onEnded() {
            root.classList.remove('latest-episodes--transport-active');
            stopWaveAnimation();
            if (deck.currentLi) {
                deck.currentLi.classList.remove('latest-episodes__item--playing');
                var b = deck.currentLi.querySelector('.latest-episodes__play');
                if (b) {
                    b.classList.remove('latest-episodes__play--playing');
                    b.setAttribute('aria-pressed', 'false');
                }
            }
            syncDeckPlayButton();
        }

        function resetDeckIdle() {
            clearCurrent();
            root.classList.remove('latest-episodes--transport-active');
            stopWaveAnimation();
            if (!isPlaybackActive() && !hasLoadedPlayback() && primeLatestEpisodePreview(deck, root)) {
                syncDeckPlayButton();
                return;
            }
            if (transport) transport.hidden = true;
            if (nowPlaying) {
                nowPlaying.classList.add('latest-episodes__now-playing--idle');
                nowPlaying.textContent = 'Choose an episode below to start listening.';
            }
            var defaultCover = artWrap ? artWrap.getAttribute('data-default-cover') || '' : '';
            updateArt(defaultCover);
            syncDeckPlayButton();
        }

        function deckOwnsActiveEpisode() {
            var url = playerActiveUrl();
            return !!(url && findButtonForStoredUrl(url));
        }

        function findButtonForStoredUrl(storedUrl) {
            return findPlayButtonForUrl(root, storedUrl);
        }

        function syncDeckFromPlayer() {
            var url = playerActiveUrl();
            if (!url) {
                resetDeckIdle();
                return;
            }
            var btn = findButtonForStoredUrl(url);
            if (!btn) {
                resetDeckIdle();
                refreshMediaSessionFromPlayback();
                renderGlobalBarFromMeta();
                return;
            }
            clearCurrent();
            deck.currentLi = btn.closest('.latest-episodes__item');
            if (deck.currentLi) deck.currentLi.classList.add('latest-episodes__item--current');
            var meta = metaFromPlayButton(btn, url);
            rememberEpisodeMeta(
                meta.episodeTitle,
                meta.podcastTitle,
                meta.coverUrl,
                meta.audioUrl,
                meta.episodePageUrl,
                meta.podcastPageUrl
            );
            updateArt(meta.coverUrl || coverUrlFromPlayButton(btn));
            setNowPlaying(
                meta.episodeTitle,
                meta.podcastTitle,
                player.paused ? 'Continue listening' : 'Now playing',
                meta.episodePageUrl,
                meta.podcastPageUrl
            );
            syncPlayingClass();
            updateTransportTimes();
            renderGlobalBarFromMeta();
        }

        if (deckPlay) {
            deckPlay.addEventListener('click', function () {
                if (!player.src || !deckOwnsActiveEpisode()) {
                    var previewBtn =
                        (deck.currentLi && deck.currentLi.querySelector('[data-audio-url]')) ||
                        findFirstListEpisodeButton(root);
                    if (previewBtn) {
                        activateEpisode(previewBtn, { userGesture: true, play: true }, deck);
                        return;
                    }
                }
                if (!player.src) return;
                if (!player.paused) player.pause();
                else playEpisode();
            });
        }

        if (deckSkipBack) {
            deckSkipBack.addEventListener('click', function () {
                if (!player.src) return;
                player.currentTime = Math.max(0, player.currentTime - SKIP_BACK_SEC);
                updateTransportTimes();
                updateGlobalTransportTimes();
                updateMediaSessionPosition();
            });
        }

        if (deckSkipForward) {
            deckSkipForward.addEventListener('click', function () {
                if (!player.src) return;
                var dur = player.duration;
                var next = player.currentTime + SKIP_FORWARD_SEC;
                if (isFinite(dur) && dur > 0) next = Math.min(next, dur);
                player.currentTime = next;
                updateTransportTimes();
                updateGlobalTransportTimes();
                updateMediaSessionPosition();
            });
        }

        if (scrubInput) {
            function commitDeckScrubSeek() {
                if (!scrubbing) return;
                var dur = player.duration;
                if (isFinite(dur) && dur > 0) {
                    player.currentTime = (Number(scrubInput.value) / 1000) * dur;
                }
                scrubbing = false;
                updateTransportTimes();
                updateGlobalTransportTimes();
                updateMediaSessionPosition();
                refreshAllListenProgress();
            }

            function cancelDeckScrubGesture() {
                scrubbing = false;
                updateTransportTimes();
                updateGlobalTransportTimes();
            }

            scrubInput.addEventListener('input', function () {
                scrubbing = true;
                var dur = player.duration;
                if (!isFinite(dur) || dur <= 0) return;
                var scaled = Number(scrubInput.value);
                updateScrubVisual(scaled / 10);
                if (currentEl) currentEl.textContent = formatTime((scaled / 1000) * dur);
            });
            scrubInput.addEventListener('change', commitDeckScrubSeek);
            scrubInput.addEventListener('pointerdown', function () {
                scrubbing = true;
            });
            scrubInput.addEventListener('pointerup', commitDeckScrubSeek);
            scrubInput.addEventListener('pointercancel', cancelDeckScrubGesture);
        }

        root.addEventListener('click', function (event) {
            var button = event.target.closest('[data-audio-url]');
            if (!button) return;
            event.preventDefault();
            event.stopPropagation();
            activateEpisode(button, { userGesture: true, play: true }, deck);
        });

        observeDeckShell(root);

        (function hydrateFromLastVisit() {
            if (playerActiveUrl()) {
                syncDeckFromPlayer();
                return;
            }
            if (root.classList.contains('latest-episodes--episode-page')) return;
            var last = loadLastListened();
            if (!shouldResumeLastEpisode(last, root)) return;
            var btn = findButtonForStoredUrl(last.url);
            if (!btn) return;
            if (last.coverUrl && !btn.getAttribute('data-cover-url')) {
                btn.setAttribute('data-cover-url', last.coverUrl);
            }
            activateEpisode(btn, { userGesture: false, play: false, kicker: 'Continue listening' }, deck);
        })();

        (function initEpisodePagePlayer() {
            if (!root.classList.contains('latest-episodes--episode-page')) return;
            if (playerActiveUrl()) {
                syncDeckFromPlayer();
                return;
            }
            var btn = root.querySelector('.latest-episodes__list--episode-page [data-audio-url]');
            if (!btn) return;
            activateEpisode(btn, { userGesture: false, play: false, kicker: false }, deck);
            try {
                player.preload = 'metadata';
            } catch (e) {}
        })();

        activeDeck = deck;
        document.body.classList.add('brp-deck-active');
        syncDeckFromPlayer();
        if (hasLoadedPlayback()) refreshMediaSessionFromPlayback();
        refreshAllListenProgress();
        updateGlobalBarVisibility();

        return deck;
    }

    function bindDom() {
        var roots = document.querySelectorAll('#brp-global-player');
        for (var i = 1; i < roots.length; i++) {
            roots[i].remove();
        }

        globalRoot = document.getElementById('brp-global-player');
        if (!globalRoot) return false;

        player = globalRoot.querySelector('#brp-global-audio');
        if (!player) return false;

        globalArt = globalRoot.querySelector('[data-global-player-art]');
        globalArtWrap = globalRoot.querySelector('[data-global-player-art-wrap]');
        globalTitle = globalRoot.querySelector('[data-global-player-title]');
        globalShow = globalRoot.querySelector('[data-global-player-show]');
        globalPlay = globalRoot.querySelector('[data-global-player-play]');
        globalScrub = globalRoot.querySelector('[data-global-player-scrub]');
        globalScrubProgress = globalRoot.querySelector('[data-global-player-scrub-progress]');
        globalCurrentEl = globalRoot.querySelector('[data-global-player-current]');
        globalDurationEl = globalRoot.querySelector('[data-global-player-duration]');

        var fullscreenRoots = document.querySelectorAll('#brp-player-fullscreen');
        for (var j = 1; j < fullscreenRoots.length; j++) {
            fullscreenRoots[j].remove();
        }

        fullscreenRoot = document.getElementById('brp-player-fullscreen');
        if (fullscreenRoot) {
            fullscreenArt = fullscreenRoot.querySelector('[data-fullscreen-art]');
            fullscreenArtWrap = fullscreenRoot.querySelector('[data-fullscreen-art-wrap]');
            fullscreenTitle = fullscreenRoot.querySelector('[data-fullscreen-title]');
            fullscreenShow = fullscreenRoot.querySelector('[data-fullscreen-show]');
            fullscreenEpisodeLink = fullscreenRoot.querySelector('[data-fullscreen-episode-link]');
            fullscreenPodcastLink = fullscreenRoot.querySelector('[data-fullscreen-podcast-link]');
            fullscreenPlay = fullscreenRoot.querySelector('[data-fullscreen-play]');
            fullscreenScrub = fullscreenRoot.querySelector('[data-fullscreen-scrub]');
            fullscreenScrubProgress = fullscreenRoot.querySelector('[data-fullscreen-scrub-progress]');
            fullscreenCurrentEl = fullscreenRoot.querySelector('[data-fullscreen-current]');
            fullscreenDurationEl = fullscreenRoot.querySelector('[data-fullscreen-duration]');
        }

        return true;
    }

    function initEngine() {
        if (!bindDom()) return;
        if (!engineReady) {
            engineReady = true;
            restorePlaybackHandoff();
        }
        wireEngineEvents();
        wireGlobalControls();
        syncGlobalBarFromMeta();
    }

    function scanForDecks() {
        document.querySelectorAll('[data-brp-player-deck]').forEach(function (el) {
            var sectionId = el.getAttribute('data-brp-player-deck') || el.id;
            if (sectionId) {
                createDeck(sectionId);
            }
        });
    }

    function refreshGlobalPlayerUi() {
        if (!bindDom()) return;
        reconcilePlaybackAfterNavigation();
        requestAnimationFrame(function () {
            if (bindDom()) reconcilePlaybackAfterNavigation();
        });
    }

    function onPageReady() {
        initEngine();
        if (playerActiveUrl()) {
            restorePlaybackMeta();
        }
        scanForDecks();
        reconcilePlaybackAfterNavigation();
        updateGlobalBarVisibility();
    }

    function onBeforeTurboRender() {
        persistPlaybackMeta();
        savePlaybackHandoff();
        closePlayerFullscreen(true);
        activeDeck = null;
        deckShellVisible = false;
        if (deckVisibilityObserver) {
            deckVisibilityObserver.disconnect();
            deckVisibilityObserver = null;
        }
        document.body.classList.remove('brp-deck-active');
    }

    window.BrpPlayer = {
        registerDeck: function (sectionId) {
            initEngine();
            return createDeck(sectionId);
        },
        getAudio: function () {
            return player;
        },
        isPlaying: function () {
            return player && !player.paused && !player.ended;
        },
        seekToSeconds: function (seconds, options) {
            initEngine();
            seekEpisodeToSeconds(seconds, options || {});
        },
        activateFromMeta: function (meta, options) {
            initEngine();
            return activateFromMeta(meta, options || {});
        },
        markAsPlayed: function (url, duration) {
            initEngine();
            var activeUrl = playerActiveUrl();
            var dur = duration;
            if (!isFinite(dur) || dur <= 0) {
                if (urlsMatch(url, activeUrl) && player && isFinite(player.duration) && player.duration > 0) {
                    dur = player.duration;
                }
            }
            markProgressComplete(url, dur);
            refreshAllListenProgress();
            notifyUserSync(true);
        },
        unmarkAsPlayed: function (url) {
            initEngine();
            removeProgressForUrl(url);
            refreshAllListenProgress();
            notifyUserSync(true);
        },
        isEpisodePlayed: function (url) {
            initEngine();
            var key = storageUrlKey(url);
            if (!key) return false;
            return isProgressComplete(loadProgressMap()[key]);
        },
        refreshListenProgress: function () {
            initEngine();
            refreshAllListenProgress();
        },
        getActiveEpisodeUrl: function () {
            initEngine();
            return playerActiveUrl();
        },
        metaFromButton: function (button) {
            return metaFromPlayButton(button);
        },
    };

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', onPageReady);
    } else {
        onPageReady();
    }

    document.addEventListener('turbo:load', onPageReady);
    document.addEventListener('turbo:render', refreshGlobalPlayerUi);
    document.addEventListener('turbo:before-render', onBeforeTurboRender);
    document.addEventListener('turbo:before-cache', function () {
        document.querySelectorAll('[data-brp-deck-wired="true"]').forEach(function (el) {
            el.removeAttribute('data-brp-deck-wired');
        });
    });
})();
