(function () {
    var STORAGE_META = 'brp-episode-meta-v1';
    var STORAGE_QUEUE = 'brp-play-queue-v1';
    var STORAGE_PROGRESS = 'brp-listen-progress-v1';
    var MIN_RESUME_SEC = 5;
    var END_MARGIN_SEC = 15;
    var MOBILE_MQ = window.matchMedia('(max-width: 720px)');

    function readJson(key, fallback) {
        try {
            var raw = localStorage.getItem(key);
            if (!raw) return fallback;
            return JSON.parse(raw);
        } catch (e) {
            return fallback;
        }
    }

    function writeJson(key, value) {
        try {
            localStorage.setItem(key, JSON.stringify(value));
        } catch (e) {}
    }

    function urlKey(url) {
        if (!url) return '';
        try {
            return new URL(url, window.location.href).href;
        } catch (e) {
            return String(url).trim();
        }
    }

    function progressRow(url) {
        var key = urlKey(url);
        if (!key) return null;
        return loadProgressMap()[key] || null;
    }

    function isEpisodePlayedLocally(url) {
        return isProgressComplete(progressRow(url));
    }

    function notifyCloudSync(immediate) {
        if (window.BrpUserSync && window.BrpUserSync.notifyLocalChange) {
            window.BrpUserSync.notifyLocalChange(!!immediate);
        }
    }

    function markEpisodePlayedLocally(url) {
        var key = urlKey(url);
        if (!key) return;
        var map = loadProgressMap();
        map[key] = { c: true, u: Date.now() };
        writeJson(STORAGE_PROGRESS, map);
        notifyCloudSync(true);
    }

    function unmarkEpisodePlayedLocally(url) {
        var key = urlKey(url);
        if (!key) return;
        var map = loadProgressMap();
        map[key] = { x: 1, u: Date.now() };
        writeJson(STORAGE_PROGRESS, map);
        notifyCloudSync(true);
    }

    function formatDurationSeconds(seconds) {
        var total = Math.round(Number(seconds) || 0);
        if (total <= 0) return '';
        var h = Math.floor(total / 3600);
        var m = Math.floor((total % 3600) / 60);
        var s = total % 60;
        if (h > 0) {
            return h + ':' + String(m).padStart(2, '0') + ':' + String(s).padStart(2, '0');
        }
        return m + ':' + String(s).padStart(2, '0');
    }

    function durationHtmlFromMeta(meta) {
        if (!meta || !meta.durationSeconds) return '';
        var label = formatDurationSeconds(meta.durationSeconds);
        if (!label) return '';
        return (
            '<span class="latest-episodes__episode-duration" aria-label="Duration ' +
            escapeHtml(label) +
            '">' +
            escapeHtml(label) +
            '</span>'
        );
    }

    function loadMetaMap() {
        var map = readJson(STORAGE_META, {});
        return map && typeof map === 'object' && !Array.isArray(map) ? map : {};
    }

    function saveEpisodeMeta(meta) {
        if (!meta || !meta.audioUrl) return;
        var key = urlKey(meta.audioUrl);
        if (!key) return;
        var map = loadMetaMap();
        map[key] = {
            episodeTitle: meta.episodeTitle || 'Episode',
            podcastTitle: meta.podcastTitle || 'Podcast',
            coverUrl: meta.coverUrl || '',
            audioUrl: meta.audioUrl,
            episodePageUrl: meta.episodePageUrl || '',
            podcastPageUrl: meta.podcastPageUrl || '',
            durationSeconds: meta.durationSeconds || null,
            u: Date.now(),
        };
        writeJson(STORAGE_META, map);
        notifyCloudSync(false);
    }

    function getEpisodeMeta(url) {
        var key = urlKey(url);
        if (!key) return null;
        return loadMetaMap()[key] || null;
    }

    function metaFromItemElement(item) {
        if (!item) return null;
        var play = item.querySelector('[data-audio-url]');
        if (play && window.BrpPlayer && window.BrpPlayer.metaFromButton) {
            return window.BrpPlayer.metaFromButton(play);
        }
        var audioUrl = item.getAttribute('data-audio-url') || (play && play.getAttribute('data-audio-url'));
        if (!audioUrl) return null;
        return {
            audioUrl: audioUrl,
            episodeTitle: item.getAttribute('data-episode-title') || (play && play.getAttribute('data-episode-title')) || 'Episode',
            podcastTitle: item.getAttribute('data-podcast-title') || (play && play.getAttribute('data-podcast-title')) || 'Podcast',
            coverUrl: item.getAttribute('data-cover-url') || (play && play.getAttribute('data-cover-url')) || '',
            episodePageUrl: item.getAttribute('data-episode-url') || (play && play.getAttribute('data-episode-url')) || '',
            podcastPageUrl: item.getAttribute('data-podcast-url') || (play && play.getAttribute('data-podcast-url')) || '',
            durationSeconds: readDurationSecondsFromButton(play),
        };
    }

    function readDurationSecondsFromButton(button) {
        if (!button) return null;
        var raw = button.getAttribute('data-duration-seconds');
        if (!raw) return null;
        var seconds = parseInt(raw, 10);
        return isFinite(seconds) && seconds > 0 ? seconds : null;
    }

    function loadQueueState() {
        var state = readJson(STORAGE_QUEUE, { order: [], manual: {}, dismissed: {} });
        if (!state || typeof state !== 'object') return { order: [], manual: {}, dismissed: {} };
        if (!Array.isArray(state.order)) state.order = [];
        if (!state.manual || typeof state.manual !== 'object') state.manual = {};
        if (!state.dismissed || typeof state.dismissed !== 'object') state.dismissed = {};
        return state;
    }

    function saveQueueState(state) {
        state.u = Date.now();
        writeJson(STORAGE_QUEUE, state);
        notifyLibraryChange();
        notifyCloudSync(false);
    }

    function loadProgressMap() {
        return readJson(STORAGE_PROGRESS, {}) || {};
    }

    function isProgressComplete(row) {
        if (!row) return false;
        if (row.c === true) return true;
        if (!isFinite(row.d) || row.d <= 0) return false;
        return isFinite(row.t) && row.t >= row.d - END_MARGIN_SEC;
    }

    function isInProgress(row) {
        if (!row || typeof row.t !== 'number' || !isFinite(row.t)) return false;
        if (isProgressComplete(row)) return false;
        return row.t >= MIN_RESUME_SEC;
    }

    function queueContains(state, key) {
        return state.order.indexOf(key) !== -1;
    }

    function enqueueEpisode(meta, manual) {
        if (!meta || !meta.audioUrl) return;
        saveEpisodeMeta(meta);
        var key = urlKey(meta.audioUrl);
        var state = loadQueueState();
        if (!queueContains(state, key)) {
            state.order.push(key);
        }
        if (manual) state.manual[key] = true;
        delete state.dismissed[key];
        saveQueueState(state);
    }

    function removeFromQueue(url) {
        var key = urlKey(url);
        if (!key) return;
        var state = loadQueueState();
        state.order = state.order.filter(function (k) {
            return k !== key;
        });
        delete state.manual[key];
        saveQueueState(state);
    }

    function dismissFromUpNext(url) {
        var key = urlKey(url);
        if (!key) return;
        var state = loadQueueState();
        state.order = state.order.filter(function (k) {
            return k !== key;
        });
        delete state.manual[key];
        state.dismissed[key] = true;
        saveQueueState(state);
    }

    function moveQueueItem(url, direction) {
        var key = urlKey(url);
        if (!key || (direction !== 'up' && direction !== 'down')) return;
        var activeUrl = window.BrpPlayer && window.BrpPlayer.getActiveEpisodeUrl ? window.BrpPlayer.getActiveEpisodeUrl() : '';
        var keys = getUpNextKeys(activeUrl);
        var index = keys.indexOf(key);
        if (index === -1) return;
        var targetIndex = direction === 'up' ? index - 1 : index + 1;
        if (targetIndex < 0 || targetIndex >= keys.length) return;

        var nextOrder = keys.slice();
        var swapKey = nextOrder[targetIndex];
        nextOrder[targetIndex] = key;
        nextOrder[index] = swapKey;

        var state = loadQueueState();
        state.order = nextOrder;
        nextOrder.forEach(function (queueKey) {
            state.manual[queueKey] = true;
        });
        saveQueueState(state);
    }

    function touchInProgressQueue(url) {
        var key = urlKey(url);
        if (!key) return;
        var row = loadProgressMap()[key];
        if (!isInProgress(row)) return;
        var meta = getEpisodeMeta(key);
        if (!meta) return;
        var state = loadQueueState();
        if (!queueContains(state, key)) {
            state.order.push(key);
            saveQueueState(state);
        }
    }

    function getUpNextKeys(excludeUrl) {
        var state = loadQueueState();
        var progress = loadProgressMap();
        var keys = state.order.slice();
        var exclude = urlKey(excludeUrl);

        Object.keys(progress).forEach(function (key) {
            if (key === exclude) return;
            if (keys.indexOf(key) !== -1) return;
            if (isInProgress(progress[key]) && getEpisodeMeta(key)) {
                keys.push(key);
            }
        });

        return keys.filter(function (key) {
            if (key === exclude) return false;
            if (state.dismissed && state.dismissed[key]) return false;
            if (isProgressComplete(progress[key])) return false;
            return !!getEpisodeMeta(key);
        });
    }

    function playNextInQueue(finishedUrl) {
        if (!window.BrpPlayer || !window.BrpPlayer.activateFromMeta) return false;
        removeFromQueue(finishedUrl);
        var keys = getUpNextKeys('');
        if (!keys.length) return false;
        var nextMeta = getEpisodeMeta(keys[0]);
        if (!nextMeta) return false;
        removeFromQueue(nextMeta.audioUrl);
        return window.BrpPlayer.activateFromMeta(nextMeta, { play: true, userGesture: false });
    }

    function notifyLibraryChange() {
        try {
            document.dispatchEvent(new CustomEvent('brp-library-changed'));
        } catch (e) {}
    }

    function escapeHtml(text) {
        return String(text || '')
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/"/g, '&quot;');
    }

    function buildSyntheticQueueItem(meta) {
        var li = document.createElement('li');
        li.className = 'latest-episodes__item latest-episodes__item--queue';
        li.setAttribute('data-audio-url', meta.audioUrl);
        li.setAttribute('data-episode-title', meta.episodeTitle || '');
        li.setAttribute('data-podcast-title', meta.podcastTitle || '');
        if (meta.episodePageUrl) li.setAttribute('data-episode-url', meta.episodePageUrl);
        if (meta.podcastPageUrl) li.setAttribute('data-podcast-url', meta.podcastPageUrl);

        var coverHtml = meta.coverUrl
            ? '<img class="latest-episodes__cover" src="' + escapeHtml(meta.coverUrl) + '" alt="" width="96" height="96" loading="lazy" decoding="async">'
            : '<span class="latest-episodes__episode-art-placeholder"></span>';

        var podcastHtml = meta.podcastPageUrl
            ? '<a href="' + escapeHtml(meta.podcastPageUrl) + '" class="latest-episodes__podcast-link latest-episodes__podcast-link--feed">' + escapeHtml(meta.podcastTitle) + '</a>'
            : '<span class="latest-episodes__podcast-label latest-episodes__podcast-label--feed">' + escapeHtml(meta.podcastTitle) + '</span>';

        var hitHtml = meta.episodePageUrl
            ? '<a href="' + escapeHtml(meta.episodePageUrl) + '" class="latest-episodes__episode-hit" aria-label="Open episode: ' + escapeHtml(meta.episodeTitle) + '"></a>'
            : '';

        li.innerHTML =
            '<article class="latest-episodes__episode-card' +
            (meta.episodePageUrl ? ' latest-episodes__episode-card--linked' : '') +
            '">' +
            hitHtml +
            '<div class="latest-episodes__episode-art" aria-hidden="true">' +
            coverHtml +
            '</div>' +
            '<div class="latest-episodes__episode-titles">' +
            '<span class="latest-episodes__episode-title latest-episodes__episode-title--feed">' +
            escapeHtml(meta.episodeTitle) +
            '</span>' +
            '<div class="latest-episodes__podcast-line">' +
            podcastHtml +
            durationHtmlFromMeta(meta) +
            '</div>' +
            '<button type="button" class="latest-episodes__play latest-episodes__play--feed" aria-pressed="false" aria-label="Play episode: ' +
            escapeHtml(meta.episodeTitle) +
            '" data-audio-url="' +
            escapeHtml(meta.audioUrl) +
            '" data-episode-title="' +
            escapeHtml(meta.episodeTitle) +
            '" data-podcast-title="' +
            escapeHtml(meta.podcastTitle) +
            '"' +
            (meta.coverUrl ? ' data-cover-url="' + escapeHtml(meta.coverUrl) + '"' : '') +
            (meta.episodePageUrl ? ' data-episode-url="' + escapeHtml(meta.episodePageUrl) + '"' : '') +
            (meta.podcastPageUrl ? ' data-podcast-url="' + escapeHtml(meta.podcastPageUrl) + '"' : '') +
            (meta.durationSeconds ? ' data-duration-seconds="' + escapeHtml(String(meta.durationSeconds)) + '"' : '') +
            '><span class="latest-episodes__play-glyph" aria-hidden="true"></span></button>' +
            '</div></article>' +
            '<div class="latest-episodes__listen-track" data-listen-progress-track hidden><div class="latest-episodes__listen-fill" data-listen-progress style="width: 0%"></div></div>';

        appendEpisodeActions(li);
        return li;
    }

    function cloneFeedItemForQueue(url) {
        var play = null;
        var buttons = document.querySelectorAll('[data-audio-url]');
        for (var i = 0; i < buttons.length; i++) {
            if (urlKey(buttons[i].getAttribute('data-audio-url')) === urlKey(url)) {
                play = buttons[i];
                break;
            }
        }
        if (play) {
            var li = play.closest('.latest-episodes__item');
            if (li && !li.classList.contains('latest-episodes__item--queue-section')) {
                var clone = li.cloneNode(true);
                clone.classList.add('latest-episodes__item--queue');
                if (!clone.querySelector('[data-episode-actions]')) appendEpisodeActions(clone);
                return clone;
            }
        }
        var meta = getEpisodeMeta(url);
        return meta ? buildSyntheticQueueItem(meta) : null;
    }

    var ICON_PLUS =
        '<svg class="latest-episodes__action-icon" viewBox="0 0 24 24" width="16" height="16" aria-hidden="true" focusable="false">' +
        '<path fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" d="M12 5v14M5 12h14"/></svg>';
    var ICON_CHECK =
        '<svg class="latest-episodes__action-icon" viewBox="0 0 24 24" width="16" height="16" aria-hidden="true" focusable="false">' +
        '<path fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" d="M5 13l4 4L19 7"/></svg>';
    var ICON_X =
        '<svg class="latest-episodes__action-icon" viewBox="0 0 24 24" width="16" height="16" aria-hidden="true" focusable="false">' +
        '<path fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" d="M6 6l12 12M18 6L6 18"/></svg>';
    var ICON_UP =
        '<svg class="latest-episodes__action-icon" viewBox="0 0 24 24" width="16" height="16" aria-hidden="true" focusable="false">' +
        '<path fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" d="M12 17V7M7 11l5-5 5 5"/></svg>';
    var ICON_DOWN =
        '<svg class="latest-episodes__action-icon" viewBox="0 0 24 24" width="16" height="16" aria-hidden="true" focusable="false">' +
        '<path fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" d="M12 7v10M7 13l5 5 5-5"/></svg>';

    function ensureEpisodeControls(titles) {
        if (!titles) return null;
        var existing = titles.querySelector(':scope > .latest-episodes__episode-controls');
        if (existing) {
            var strayActions = titles.querySelector(':scope > [data-episode-actions]');
            if (strayActions && !existing.contains(strayActions)) {
                existing.appendChild(strayActions);
            }
            return existing;
        }
        var play = titles.querySelector(':scope > .latest-episodes__play--feed, :scope > .latest-episodes__play');
        if (!play) return null;
        var controls = document.createElement('div');
        controls.className = 'latest-episodes__episode-controls';
        titles.insertBefore(controls, play);
        controls.appendChild(play);
        var actions = titles.querySelector(':scope > [data-episode-actions]');
        if (actions) controls.appendChild(actions);
        return controls;
    }

    function appendEpisodeActions(item) {
        if (!item) return;
        var titles = item.querySelector('.latest-episodes__episode-titles');
        if (titles) ensureEpisodeControls(titles);
        if (item.querySelector('[data-episode-actions]')) {
            refreshActionLabels(item);
            return;
        }
        var wrap = document.createElement('div');
        wrap.className = 'latest-episodes__actions';
        wrap.setAttribute('data-episode-actions', '');
        wrap.innerHTML =
            '<div class="latest-episodes__actions-inline">' +
            '<button type="button" class="latest-episodes__action latest-episodes__action--icon" data-brp-queue-add title="Add to queue" aria-label="Add to queue">' +
            ICON_PLUS +
            '</button>' +
            '<button type="button" class="latest-episodes__action latest-episodes__action--icon" data-brp-mark-played title="Mark as played" aria-label="Mark as played">' +
            ICON_CHECK +
            '</button>' +
            '</div>';
        var controls = titles && titles.querySelector('.latest-episodes__episode-controls');
        if (controls) {
            controls.appendChild(wrap);
        } else {
            var host =
                item.querySelector('.latest-episodes__episode-card') ||
                item.querySelector('.latest-episodes__row--episode') ||
                item.querySelector('.latest-episodes__row');
            if (host) {
                host.appendChild(wrap);
            } else {
                item.appendChild(wrap);
            }
        }
        refreshActionLabels(item);
    }

    function appendQueueRemoveButton(item) {
        if (!item || item.querySelector('[data-brp-queue-remove]')) return;
        var inline =
            item.querySelector('.latest-episodes__actions-inline') ||
            (item.querySelector('[data-episode-actions]') &&
                item.querySelector('[data-episode-actions]').querySelector('.latest-episodes__actions-inline'));
        var btn = document.createElement('button');
        btn.type = 'button';
        btn.className = 'latest-episodes__action latest-episodes__action--icon latest-episodes__action--queue-remove';
        btn.setAttribute('data-brp-queue-remove', '');
        btn.title = 'Remove from queue';
        btn.setAttribute('aria-label', 'Remove from queue');
        btn.innerHTML = ICON_X;
        if (inline) {
            inline.appendChild(btn);
            return;
        }
        var card = item.querySelector('.latest-episodes__episode-card') || item.querySelector('.latest-episodes__row--episode');
        if (card) card.appendChild(btn);
    }

    function appendQueueMoveButtons(item, index, total) {
        if (!item || item.querySelector('[data-brp-queue-move]')) return;
        var inline =
            item.querySelector('.latest-episodes__actions-inline') ||
            (item.querySelector('[data-episode-actions]') &&
                item.querySelector('[data-episode-actions]').querySelector('.latest-episodes__actions-inline'));
        if (!inline) return;

        var upBtn = document.createElement('button');
        upBtn.type = 'button';
        upBtn.className = 'latest-episodes__action latest-episodes__action--icon latest-episodes__action--queue-move';
        upBtn.setAttribute('data-brp-queue-move', 'up');
        upBtn.title = 'Move up in queue';
        upBtn.setAttribute('aria-label', 'Move up in queue');
        upBtn.innerHTML = ICON_UP;
        upBtn.disabled = index <= 0;

        var downBtn = document.createElement('button');
        downBtn.type = 'button';
        downBtn.className = 'latest-episodes__action latest-episodes__action--icon latest-episodes__action--queue-move';
        downBtn.setAttribute('data-brp-queue-move', 'down');
        downBtn.title = 'Move down in queue';
        downBtn.setAttribute('aria-label', 'Move down in queue');
        downBtn.innerHTML = ICON_DOWN;
        downBtn.disabled = index >= total - 1;

        inline.insertBefore(upBtn, inline.firstChild);
        inline.insertBefore(downBtn, upBtn.nextSibling);
    }

    function isListenHistoryItem(item) {
        if (!item) return false;
        return item.hasAttribute('data-brp-history-item') || !!item.closest('[data-brp-listen-history]');
    }

    function customizeListenHistoryActions(root) {
        root = root || document;
        var items =
            root.matches && root.matches('[data-brp-history-item]')
                ? [root]
                : Array.prototype.slice.call(root.querySelectorAll('[data-brp-history-item]'));
        items.forEach(function (item) {
            item.querySelectorAll('[data-brp-mark-played]').forEach(function (btn) {
                btn.removeAttribute('data-brp-mark-played');
                btn.removeAttribute('aria-pressed');
                btn.setAttribute('data-brp-history-remove', '');
                btn.classList.remove('latest-episodes__action--active');
                btn.classList.add('latest-episodes__action--history-remove');
                btn.innerHTML = ICON_X;
                btn.title = 'Remove from history';
                btn.setAttribute('aria-label', 'Remove from history');
            });
        });
    }

    function removeFromListenHistory(url) {
        if (window.BrpPlayer && window.BrpPlayer.unmarkAsPlayed) {
            window.BrpPlayer.unmarkAsPlayed(url);
        } else {
            unmarkEpisodePlayedLocally(url);
        }
        refreshActionLabels(document);
        renderListenHistory();
        if (window.BrpPlayer && typeof window.BrpPlayer.refreshListenProgress === 'function') {
            window.BrpPlayer.refreshListenProgress();
        }
    }

    function refreshActionLabels(scope) {
        var root = scope || document;
        root.querySelectorAll('[data-episode-actions]').forEach(function (actions) {
            var item = actions.closest('.latest-episodes__item') || actions.closest('[data-brp-history-item]');
            var meta = metaFromItemElement(item);
            if (!meta) return;
            var played = isEpisodePlayedLocally(meta.audioUrl);
            if (item && item.classList.contains('latest-episodes__item')) {
                if (isListenHistoryItem(item)) {
                    item.classList.remove('latest-episodes__item--played');
                } else {
                    item.classList.toggle('latest-episodes__item--played', played);
                }
            }
            actions.querySelectorAll('[data-brp-mark-played]').forEach(function (btn) {
                if (isListenHistoryItem(item)) return;
                var label = played ? 'Mark unplayed' : 'Mark as played';
                btn.title = label;
                btn.setAttribute('aria-label', label);
                btn.classList.toggle('latest-episodes__action--active', played);
                btn.setAttribute('aria-pressed', played ? 'true' : 'false');
            });
            var inQueue = queueContains(loadQueueState(), urlKey(meta.audioUrl));
            actions.querySelectorAll('[data-brp-queue-add]').forEach(function (btn) {
                var label = inQueue ? 'In queue' : 'Add to queue';
                btn.title = label;
                btn.setAttribute('aria-label', label);
                btn.classList.toggle('latest-episodes__action--active', inQueue);
                btn.disabled = inQueue;
            });
        });
    }

    function wireEpisodeActions(root) {
        root = root || document;
        root.querySelectorAll('.latest-episodes__item:not([data-brp-actions-wired])').forEach(function (item) {
            if (item.classList.contains('latest-episodes__item--promo')) return;
            if (item.classList.contains('latest-episodes__feed-day')) return;
            if (item.classList.contains('latest-episodes__empty')) return;
            // Episode-page solo listen button has no actions host — injecting here
            // stacks queue/mark-played under the big play control.
            if (item.classList.contains('latest-episodes__item--solo')) return;
            if (item.closest('.latest-episodes--episode-page')) return;
            if (!item.querySelector('[data-audio-url]')) return;
            item.setAttribute('data-brp-actions-wired', 'true');
            appendEpisodeActions(item);
        });
    }

    function handleActionClick(event) {
        var moveBtn = event.target.closest('[data-brp-queue-move]');
        var removeBtn = event.target.closest('[data-brp-queue-remove]');
        var queueBtn = event.target.closest('[data-brp-queue-add]');
        var playedBtn = event.target.closest('[data-brp-mark-played]');
        var historyRemoveBtn = event.target.closest('[data-brp-history-remove]');
        if (!moveBtn && !removeBtn && !queueBtn && !playedBtn && !historyRemoveBtn) return;

        var item = event.target.closest('.latest-episodes__item, [data-brp-history-item]');
        var meta = metaFromItemElement(item);
        if (!meta) return;

        event.preventDefault();
        event.stopPropagation();

        if (moveBtn) {
            moveQueueItem(meta.audioUrl, moveBtn.getAttribute('data-brp-queue-move'));
            renderUpNextSection();
            return;
        }

        if (removeBtn) {
            dismissFromUpNext(meta.audioUrl);
            refreshActionLabels(document);
            renderUpNextSection();
            return;
        }

        if (historyRemoveBtn) {
            removeFromListenHistory(meta.audioUrl);
            return;
        }

        if (queueBtn) {
            enqueueEpisode(meta, true);
            refreshActionLabels(item);
            renderUpNextSection();
            return;
        }

        if (playedBtn) {
            saveEpisodeMeta(meta);
            if (isEpisodePlayedLocally(meta.audioUrl)) {
                if (window.BrpPlayer && window.BrpPlayer.unmarkAsPlayed) {
                    window.BrpPlayer.unmarkAsPlayed(meta.audioUrl);
                } else {
                    unmarkEpisodePlayedLocally(meta.audioUrl);
                }
            } else {
                if (window.BrpPlayer && window.BrpPlayer.markAsPlayed) {
                    window.BrpPlayer.markAsPlayed(meta.audioUrl);
                } else {
                    markEpisodePlayedLocally(meta.audioUrl);
                }
                removeFromQueue(meta.audioUrl);
            }
            refreshActionLabels(document);
            renderUpNextSection();
            renderListenHistory();
            if (window.BrpPlayer && typeof window.BrpPlayer.refreshListenProgress === 'function') {
                window.BrpPlayer.refreshListenProgress();
            }
        }
    }

    function ensureUpNextSection() {
        var deck = document.getElementById('latest-episodes-page');
        if (!deck) return null;
        var existing = deck.querySelector('[data-brp-up-next]');
        if (existing) return existing;

        var section = document.createElement('div');
        section.className = 'brp-up-next';
        section.setAttribute('data-brp-up-next', '');
        section.hidden = true;
        section.innerHTML =
            '<div class="brp-up-next__block" data-brp-now-playing-block hidden>' +
            '<h2 class="brp-up-next__heading">Now playing</h2>' +
            '<ol class="latest-episodes__list latest-episodes__list--feed brp-up-next__list" data-brp-now-playing-list></ol>' +
            '</div>' +
            '<div class="brp-up-next__block" data-brp-queue-block hidden>' +
            '<h2 class="brp-up-next__heading">Up next</h2>' +
            '<p class="brp-up-next__hint">Queued episodes and ones you started but have not finished play automatically when the current episode ends.</p>' +
            '<ol class="latest-episodes__list latest-episodes__list--feed brp-up-next__list" data-brp-queue-list></ol>' +
            '</div>';

        var feedList = deck.querySelector('.latest-episodes__list--feed');
        if (feedList) {
            deck.insertBefore(section, feedList);
        } else {
            deck.appendChild(section);
        }
        return section;
    }

    function renderUpNextSection() {
        var section = ensureUpNextSection();
        if (!section) return;

        var activeUrl = window.BrpPlayer ? window.BrpPlayer.getActiveEpisodeUrl() : '';
        var nowList = section.querySelector('[data-brp-now-playing-list]');
        var nowBlock = section.querySelector('[data-brp-now-playing-block]');
        var queueList = section.querySelector('[data-brp-queue-list]');
        var queueBlock = section.querySelector('[data-brp-queue-block]');

        nowList.innerHTML = '';
        queueList.innerHTML = '';

        if (activeUrl && window.BrpPlayer && (window.BrpPlayer.isPlaying() || activeUrl)) {
            var nowItem = cloneFeedItemForQueue(activeUrl) || (getEpisodeMeta(activeUrl) && buildSyntheticQueueItem(getEpisodeMeta(activeUrl)));
            if (nowItem) {
                nowItem.classList.add('latest-episodes__item--now-playing');
                nowList.appendChild(nowItem);
                nowBlock.hidden = false;
            } else {
                nowBlock.hidden = true;
            }
        } else {
            nowBlock.hidden = true;
        }

        var upNext = getUpNextKeys(activeUrl);
        upNext.forEach(function (key, index) {
            if (activeUrl && urlKey(activeUrl) === urlKey(key)) return;
            var node = cloneFeedItemForQueue(key);
            if (node) {
                queueList.appendChild(node);
                appendQueueMoveButtons(node, index, upNext.length);
                appendQueueRemoveButton(node);
            }
        });

        queueBlock.hidden = upNext.length === 0;
        section.hidden = nowBlock.hidden && queueBlock.hidden;

        wireEpisodeActions(section);
        refreshActionLabels(section);
    }

    function collectPlayedHistory() {
        var progress = loadProgressMap();
        var items = [];
        Object.keys(progress).forEach(function (key) {
            var row = progress[key];
            if (!isProgressComplete(row)) return;
            var meta = getEpisodeMeta(key);
            if (!meta) {
                meta = {
                    audioUrl: key,
                    episodeTitle: 'Episode',
                    podcastTitle: 'Podcast',
                    coverUrl: '',
                    episodePageUrl: '',
                    podcastPageUrl: '',
                };
            }
            items.push({
                meta: meta,
                playedAt: row.u || 0,
            });
        });
        items.sort(function (a, b) {
            return b.playedAt - a.playedAt;
        });
        return items;
    }

    function renderListenHistory() {
        var root = document.querySelector('[data-brp-listen-history]') || document.getElementById('listen-history-player');
        if (!root) return;
        var list = root.querySelector('[data-brp-history-list]');
        var empty = root.querySelector('[data-brp-history-empty]');
        if (!list) return;

        var items = collectPlayedHistory();
        list.innerHTML = '';

        if (!items.length) {
            if (empty) empty.hidden = false;
            list.hidden = true;
            return;
        }

        if (empty) empty.hidden = true;
        list.hidden = false;

        items.forEach(function (entry) {
            var meta = entry.meta;
            var li = buildSyntheticQueueItem(meta);
            li.setAttribute('data-brp-history-item', '');
            list.appendChild(li);
        });

        wireEpisodeActions(list);
        customizeListenHistoryActions(list);
        refreshActionLabels(list);
    }

    function onPageReady() {
        wireEpisodeActions(document);
        renderUpNextSection();
        renderListenHistory();
        refreshActionLabels(document);
    }

    document.addEventListener('click', handleActionClick, true);

    document.addEventListener('brp-episode-activated', function (event) {
        var meta = event.detail && event.detail.meta;
        if (!meta) return;
        saveEpisodeMeta(meta);
        touchInProgressQueue(meta.audioUrl);
        renderUpNextSection();
        refreshActionLabels(document);
    });

    document.addEventListener('brp-playback-ended', function (event) {
        var detail = event.detail || {};
        if (detail.meta) saveEpisodeMeta(detail.meta);
        var url = detail.url;
        renderListenHistory();
        refreshActionLabels(document);
        if (window.BrpPlayer && typeof window.BrpPlayer.refreshListenProgress === 'function') {
            window.BrpPlayer.refreshListenProgress();
        }
        window.setTimeout(function () {
            if (!playNextInQueue(url)) {
                renderUpNextSection();
            }
        }, 400);
    });

    document.addEventListener('brp-library-changed', function () {
        renderUpNextSection();
        renderListenHistory();
        refreshActionLabels(document);
    });

    document.addEventListener('brp-user-synced', function () {
        renderUpNextSection();
        renderListenHistory();
        refreshActionLabels(document);
    });

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', onPageReady);
    } else {
        onPageReady();
    }
    document.addEventListener('turbo:load', onPageReady);
    document.addEventListener('turbo:render', function () {
        wireEpisodeActions(document);
        renderUpNextSection();
        renderListenHistory();
        refreshActionLabels(document);
    });

    window.BrpLibrary = {
        enqueue: function (meta) {
            enqueueEpisode(meta, true);
            renderUpNextSection();
        },
        getQueue: function () {
            return loadQueueState().order.slice();
        },
    };
})();
