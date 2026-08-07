(function () {
    var CONFIG = window.BRP_SUPABASE_CONFIG || {};
    var SUPABASE_URL = (CONFIG.url || '').trim();
    var SUPABASE_ANON_KEY = (CONFIG.anonKey || '').trim();

    var STORAGE_KEY_PROGRESS = 'brp-listen-progress-v1';
    var STORAGE_KEY_LAST = 'brp-last-listened-v1';
    var STORAGE_KEY_QUEUE = 'brp-play-queue-v1';
    var STORAGE_KEY_EPISODE_META = 'brp-episode-meta-v1';
    var STORAGE_KEY_FAVORITES = 'brp-opml-favorites';
    var STORAGE_KEY_FAVORITES_META = 'brp-opml-favorites-u';
    var STORAGE_KEY_FILTER_PREFS = 'brp-filter-prefs-v1';
    var SAVE_DEBOUNCE_MS = 2000;

    var client = null;
    var session = null;
    var saveTimer = null;
    var syncing = false;
    var pendingCloudSave = false;
    var MOBILE_NAV_MQ = window.matchMedia('(max-width: 700px)');

    function isMobileNav() {
        return MOBILE_NAV_MQ.matches;
    }

    function isEnabled() {
        return !!(SUPABASE_URL && SUPABASE_ANON_KEY && window.supabase);
    }

    function readJson(key, fallback) {
        try {
            var raw = localStorage.getItem(key);
            if (!raw) {
                return fallback;
            }
            return JSON.parse(raw);
        } catch (e) {
            return fallback;
        }
    }

    function initClient() {
        if (!SUPABASE_URL || !SUPABASE_ANON_KEY || !window.supabase) {
            return null;
        }
        if (!client) {
            client = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
                auth: {
                    persistSession: true,
                    autoRefreshToken: true,
                    detectSessionInUrl: true,
                    flowType: 'pkce',
                },
            });
        }
        return client;
    }

    function isProgressTombstone(entry) {
        return entry && typeof entry === 'object' && entry.x === 1 && typeof entry.t !== 'number';
    }

    function isLastListenedEntry(value) {
        return value && typeof value === 'object' && typeof value.url === 'string' && value.url;
    }

    function isLastListenedClear(value) {
        return value && typeof value === 'object' && value.cleared === true;
    }

    function stripProgressTombstones(map) {
        var clean = {};
        var source = map && typeof map === 'object' ? map : {};

        Object.keys(source).forEach(function (key) {
            var entry = source[key];
            if (!isProgressTombstone(entry)) {
                clean[key] = entry;
            }
        });

        return clean;
    }

    function normalizeLastListenedForCloud(value) {
        if (isLastListenedEntry(value)) {
            return value;
        }
        return null;
    }

    function mergeProgressEntry(left, right) {
        var leftTomb = isProgressTombstone(left);
        var rightTomb = isProgressTombstone(right);

        if (!left && !right) {
            return undefined;
        }
        if (!left) {
            return rightTomb ? undefined : right;
        }
        if (!right) {
            return leftTomb ? undefined : left;
        }
        if (leftTomb && rightTomb) {
            return undefined;
        }
        if (leftTomb) {
            return (left.u || 0) >= (right.u || 0) ? undefined : right;
        }
        if (rightTomb) {
            return (right.u || 0) >= (left.u || 0) ? undefined : left;
        }
        return (left.u || 0) >= (right.u || 0) ? left : right;
    }

    function mergeProgressMaps(local, remote) {
        var merged = {};
        var keys = {};
        var localMap = local && typeof local === 'object' ? local : {};
        var remoteMap = remote && typeof remote === 'object' ? remote : {};

        Object.keys(localMap).forEach(function (key) {
            keys[key] = true;
        });
        Object.keys(remoteMap).forEach(function (key) {
            keys[key] = true;
        });

        Object.keys(keys).forEach(function (key) {
            var winner = mergeProgressEntry(localMap[key], remoteMap[key]);
            if (winner !== undefined) {
                merged[key] = winner;
            }
        });

        return merged;
    }

    function remoteUpdatedAtMs(remote) {
        if (!remote || !remote.updated_at) {
            return 0;
        }
        var parsed = Date.parse(remote.updated_at);
        return isNaN(parsed) ? 0 : parsed;
    }

    function mergeLastListened(local, remote, hasRemoteRow, remoteUpdatedAt) {
        var localEntry = isLastListenedEntry(local);
        var localClear = isLastListenedClear(local);
        var remoteEntry = isLastListenedEntry(remote);
        var remoteClear = hasRemoteRow && remote === null;

        if (localClear && (remoteClear || !remoteEntry)) {
            return null;
        }
        if (localClear && remoteEntry) {
            return (local.u || 0) >= (remoteEntry.u || 0) ? null : remoteEntry;
        }
        if (remoteClear && localEntry) {
            var remoteMs = remoteUpdatedAt || 0;
            return remoteMs && (local.u || 0) > remoteMs ? localEntry : null;
        }
        if (!localEntry && !localClear) {
            return remoteEntry || null;
        }
        if (!remoteEntry && !remoteClear) {
            return localEntry;
        }
        return (local.u || 0) >= (remoteEntry.u || 0) ? localEntry : remoteEntry;
    }

    function readFavoritesMeta() {
        var raw = readJson(STORAGE_KEY_FAVORITES_META, null);
        return raw && typeof raw.u === 'number' ? raw.u : 0;
    }

    function writeFavoritesMeta(u) {
        if (!u) {
            return;
        }
        try {
            localStorage.setItem(STORAGE_KEY_FAVORITES_META, JSON.stringify({ u: u }));
        } catch (e) {
            /* ignore quota errors */
        }
    }

    function normalizeFavoriteIds(ids) {
        return Array.isArray(ids) ? ids.filter(Boolean) : [];
    }

    function normalizeCloudFavorites(value, remoteUpdatedAt) {
        if (Array.isArray(value)) {
            return {
                ids: normalizeFavoriteIds(value),
                u: remoteUpdatedAt || 0,
            };
        }
        if (value && typeof value === 'object' && Array.isArray(value.ids)) {
            return {
                ids: normalizeFavoriteIds(value.ids),
                u: typeof value.u === 'number' ? value.u : remoteUpdatedAt || 0,
            };
        }
        return {
            ids: [],
            u: remoteUpdatedAt || 0,
        };
    }

    function serializeCloudFavorites(ids, updatedAt) {
        return {
            ids: normalizeFavoriteIds(ids),
            u: updatedAt || readFavoritesMeta() || Date.now(),
        };
    }

    function mergeFavorites(localIds, localUpdatedAt, remoteValue, remoteUpdatedAt) {
        var remote = normalizeCloudFavorites(remoteValue, remoteUpdatedAt);
        var local = normalizeFavoriteIds(localIds);
        var localU = localUpdatedAt || 0;
        var remoteU = remote.u || 0;

        if (localU === 0 && local.length === 0 && remote.ids.length > 0) {
            return { ids: remote.ids, u: remoteU || remoteUpdatedAt || Date.now() };
        }

        if (localU > remoteU) {
            return { ids: local, u: localU };
        }
        if (remoteU > localU) {
            return { ids: remote.ids, u: remoteU };
        }

        if (remote.ids.length > 0 && local.length === 0) {
            return { ids: remote.ids, u: remoteU || Date.now() };
        }
        return { ids: local, u: localU || Date.now() };
    }

    function mergeEpisodeMetaEntry(local, remote) {
        if (!local && !remote) {
            return undefined;
        }
        if (!local) {
            return remote;
        }
        if (!remote) {
            return local;
        }

        function pickString(primary, secondary, fallback) {
            var a = String(primary == null ? '' : primary).trim();
            if (a) return a;
            var b = String(secondary == null ? '' : secondary).trim();
            if (b) return b;
            return fallback;
        }

        function pickOptionalString(primary, secondary) {
            var a = String(primary == null ? '' : primary).trim();
            if (a) return a;
            return String(secondary == null ? '' : secondary).trim();
        }

        var primary = (local.u || 0) >= (remote.u || 0) ? local : remote;
        var secondary = primary === local ? remote : local;
        var localDuration = parseInt(local.durationSeconds, 10);
        var remoteDuration = parseInt(remote.durationSeconds, 10);
        var durationSeconds =
            isFinite(localDuration) && localDuration > 0
                ? localDuration
                : isFinite(remoteDuration) && remoteDuration > 0
                  ? remoteDuration
                  : null;

        return {
            episodeTitle: pickString(primary.episodeTitle, secondary.episodeTitle, 'Episode'),
            podcastTitle: pickString(primary.podcastTitle, secondary.podcastTitle, 'Podcast'),
            coverUrl: pickOptionalString(primary.coverUrl, secondary.coverUrl),
            audioUrl: pickString(primary.audioUrl, secondary.audioUrl, ''),
            episodePageUrl: pickOptionalString(primary.episodePageUrl, secondary.episodePageUrl),
            podcastPageUrl: pickOptionalString(primary.podcastPageUrl, secondary.podcastPageUrl),
            durationSeconds: durationSeconds,
            u: Math.max(local.u || 0, remote.u || 0) || Date.now(),
        };
    }

    function mergeEpisodeMetaMaps(local, remote) {
        var merged = {};
        var keys = {};
        var localMap = local && typeof local === 'object' ? local : {};
        var remoteMap = remote && typeof remote === 'object' ? remote : {};

        Object.keys(localMap).forEach(function (key) {
            keys[key] = true;
        });
        Object.keys(remoteMap).forEach(function (key) {
            keys[key] = true;
        });

        Object.keys(keys).forEach(function (key) {
            var winner = mergeEpisodeMetaEntry(localMap[key], remoteMap[key]);
            if (winner !== undefined) {
                merged[key] = winner;
            }
        });

        return merged;
    }

    function normalizeQueueState(value) {
        var state = value && typeof value === 'object' ? value : {};
        return {
            order: Array.isArray(state.order) ? state.order.filter(Boolean) : [],
            manual: state.manual && typeof state.manual === 'object' ? state.manual : {},
            dismissed: state.dismissed && typeof state.dismissed === 'object' ? state.dismissed : {},
            u: typeof state.u === 'number' && isFinite(state.u) ? state.u : 0,
        };
    }

    function mergeQueueState(local, remote) {
        local = normalizeQueueState(local);
        remote = normalizeQueueState(remote);

        var dismissed = {};
        Object.keys(local.dismissed).forEach(function (key) {
            dismissed[key] = true;
        });
        Object.keys(remote.dismissed).forEach(function (key) {
            dismissed[key] = true;
        });

        var manual = {};
        Object.keys(local.manual).forEach(function (key) {
            manual[key] = true;
        });
        Object.keys(remote.manual).forEach(function (key) {
            manual[key] = true;
        });

        var primary = local.u >= remote.u ? local : remote;
        var secondary = local.u >= remote.u ? remote : local;
        var order = [];
        primary.order.forEach(function (key) {
            if (!dismissed[key] && order.indexOf(key) === -1) {
                order.push(key);
            }
        });
        secondary.order.forEach(function (key) {
            if (!dismissed[key] && order.indexOf(key) === -1) {
                order.push(key);
            }
        });

        return {
            order: order,
            manual: manual,
            dismissed: dismissed,
            u: Math.max(local.u, remote.u) || Date.now(),
        };
    }

    function readLocalLibrary() {
        var favorites = readJson(STORAGE_KEY_FAVORITES, []);
        return {
            listen_progress: readJson(STORAGE_KEY_PROGRESS, {}),
            last_listened: readJson(STORAGE_KEY_LAST, null),
            play_queue: readJson(STORAGE_KEY_QUEUE, { order: [], manual: {}, dismissed: {} }),
            episode_meta: readJson(STORAGE_KEY_EPISODE_META, {}),
            favorites: normalizeFavoriteIds(favorites),
            favorites_u: readFavoritesMeta(),
            filter_prefs: readJson(STORAGE_KEY_FILTER_PREFS, {}),
        };
    }

    function writeLocalLibrary(library) {
        try {
            localStorage.setItem(
                STORAGE_KEY_PROGRESS,
                JSON.stringify(stripProgressTombstones(library.listen_progress || {}))
            );
            if (isLastListenedEntry(library.last_listened)) {
                localStorage.setItem(STORAGE_KEY_LAST, JSON.stringify(library.last_listened));
            } else {
                localStorage.removeItem(STORAGE_KEY_LAST);
            }
            localStorage.setItem(STORAGE_KEY_FAVORITES, JSON.stringify(library.favorites || []));
            if (typeof library.favorites_u === 'number' && library.favorites_u > 0) {
                writeFavoritesMeta(library.favorites_u);
            }
            if (library.filter_prefs !== undefined) {
                var existingPrefs = readJson(STORAGE_KEY_FILTER_PREFS, {});
                var mergedPrefs = mergeProgressMaps(existingPrefs, library.filter_prefs || {});
                localStorage.setItem(STORAGE_KEY_FILTER_PREFS, JSON.stringify(mergedPrefs));
            }
            if (library.play_queue !== undefined) {
                localStorage.setItem(
                    STORAGE_KEY_QUEUE,
                    JSON.stringify(normalizeQueueState(library.play_queue))
                );
            }
            if (library.episode_meta !== undefined) {
                var metaMap = library.episode_meta && typeof library.episode_meta === 'object' ? library.episode_meta : {};
                localStorage.setItem(STORAGE_KEY_EPISODE_META, JSON.stringify(metaMap));
            }
        } catch (e) {
            /* ignore quota errors */
        }
    }

    function dispatchSynced() {
        document.dispatchEvent(new CustomEvent('brp-user-synced'));
    }

    async function fetchRemoteLibrary(userId) {
        var response = await client
            .from('user_library')
            .select('listen_progress,last_listened,play_queue,episode_meta,favorites,filter_prefs,updated_at')
            .eq('user_id', userId)
            .maybeSingle();

        if (response.error) {
            throw response.error;
        }

        return response.data;
    }

    async function upsertRemoteLibrary(userId, library) {
        var response = await client.from('user_library').upsert(
            {
                user_id: userId,
                listen_progress: stripProgressTombstones(library.listen_progress),
                last_listened: normalizeLastListenedForCloud(library.last_listened),
                play_queue: normalizeQueueState(library.play_queue),
                episode_meta: library.episode_meta && typeof library.episode_meta === 'object' ? library.episode_meta : {},
                favorites: serializeCloudFavorites(library.favorites, library.favorites_u),
                filter_prefs: library.filter_prefs || {},
            },
            { onConflict: 'user_id' }
        );

        if (response.error) {
            throw response.error;
        }
    }

    function runCloudSave() {
        if (!session) {
            return Promise.resolve();
        }

        if (syncing) {
            pendingCloudSave = true;
            return Promise.resolve();
        }

        return upsertRemoteLibrary(session.user.id, readLocalLibrary()).catch(function (e) {
            console.warn('BrpUserSync: could not save library', e);
        });
    }

    function flushCloudSave() {
        if (!session) {
            return Promise.resolve();
        }

        clearTimeout(saveTimer);
        saveTimer = null;
        return runCloudSave();
    }

    function scheduleCloudSave(immediate) {
        if (!session) {
            return;
        }

        if (immediate) {
            flushCloudSave();
            return;
        }

        if (syncing) {
            pendingCloudSave = true;
            return;
        }

        clearTimeout(saveTimer);
        saveTimer = window.setTimeout(runCloudSave, SAVE_DEBOUNCE_MS);
    }

    async function syncFromCloud() {
        if (!session || syncing) {
            return;
        }

        syncing = true;
        try {
            var remote = null;

            try {
                remote = await fetchRemoteLibrary(session.user.id);
            } catch (e) {
                console.warn('BrpUserSync: could not load cloud library', e);
                return;
            }

            // Re-read local after the network round-trip so playback during sync is not lost.
            var local = readLocalLibrary();
            var remoteUpdatedAt = remoteUpdatedAtMs(remote);
            var favoritesMerge = mergeFavorites(
                local.favorites,
                local.favorites_u,
                remote && remote.favorites,
                remoteUpdatedAt
            );
            var merged = {
                listen_progress: mergeProgressMaps(local.listen_progress, remote && remote.listen_progress),
                last_listened: mergeLastListened(
                    local.last_listened,
                    remote ? remote.last_listened : undefined,
                    !!remote,
                    remoteUpdatedAt
                ),
                play_queue: mergeQueueState(local.play_queue, remote && remote.play_queue),
                episode_meta: mergeEpisodeMetaMaps(local.episode_meta, remote && remote.episode_meta),
                favorites: favoritesMerge.ids,
                favorites_u: favoritesMerge.u,
                filter_prefs: mergeProgressMaps(local.filter_prefs, remote && remote.filter_prefs),
            };

            var freshestFilterPrefs = readJson(STORAGE_KEY_FILTER_PREFS, {});
            merged.filter_prefs = mergeProgressMaps(freshestFilterPrefs, merged.filter_prefs);

            writeLocalLibrary(merged);

            try {
                await upsertRemoteLibrary(session.user.id, merged);
            } catch (e) {
                console.warn('BrpUserSync: could not save merged library', e);
            }

            dispatchSynced();
        } finally {
            syncing = false;
            if (pendingCloudSave) {
                pendingCloudSave = false;
                scheduleCloudSave();
            }
        }
    }

    function isOAuthCallback() {
        var search = window.location.search || '';
        return search.indexOf('code=') !== -1 || search.indexOf('error=') !== -1;
    }

    function pauseTurboForOAuthCallback() {
        if (!isOAuthCallback() || !window.Turbo || !window.Turbo.session) {
            return;
        }
        window.Turbo.session.drive = false;
    }

    function signInWithGoogle() {
        initClient();
        if (!client) {
            return;
        }

        client.auth.signInWithOAuth({
            provider: 'google',
            options: {
                redirectTo: window.location.origin + window.location.pathname + window.location.search,
            },
        });
    }

    async function signOut() {
        if (!client) {
            return;
        }

        closeAllAuthMenus();
        await client.auth.signOut();
    }

    function avatarUrlForUser(user) {
        if (!user) {
            return '';
        }
        var meta = user.user_metadata || {};
        return (meta.avatar_url || meta.picture || '').trim();
    }

    function closeAuthMenu(root) {
        if (!root) {
            return;
        }
        var toggle = root.querySelector('[data-user-auth-toggle]');
        var dropdown = root.querySelector('[data-user-auth-dropdown]');
        if (toggle) {
            toggle.setAttribute('aria-expanded', 'false');
        }
        if (dropdown) {
            dropdown.hidden = true;
        }
        root.classList.remove('is-open');
    }

    function closeAllAuthMenus() {
        document.querySelectorAll('[data-user-auth]').forEach(closeAuthMenu);
    }

    function setAuthMenuOpen(root, open) {
        if (!root) {
            return;
        }
        var toggle = root.querySelector('[data-user-auth-toggle]');
        var dropdown = root.querySelector('[data-user-auth-dropdown]');
        if (!toggle || !dropdown) {
            return;
        }
        root.classList.toggle('is-open', open);
        toggle.setAttribute('aria-expanded', open ? 'true' : 'false');
        dropdown.hidden = !open;
    }

    function syncMobileAuthPresentation() {
        document.querySelectorAll('[data-user-auth]').forEach(function (root) {
            var toggle = root.querySelector('[data-user-auth-toggle]');
            var dropdown = root.querySelector('[data-user-auth-dropdown]');
            if (!toggle || !dropdown) {
                return;
            }

            var mobile = isMobileNav();
            var signedIn = root.classList.contains('user-auth--signed-in');

            root.classList.toggle('user-auth--mobile-nav', mobile);
            root.classList.toggle('user-auth--mobile-nav-flat', mobile && signedIn);

            if (mobile && signedIn) {
                dropdown.hidden = false;
                toggle.setAttribute('aria-expanded', 'true');
                root.classList.remove('is-open');
                return;
            }

            closeAuthMenu(root);
        });
    }

    function updateAuthUi() {
        document.querySelectorAll('[data-user-auth]').forEach(function (root) {
            var signedIn = !!session;
            var guestAvatar = root.querySelector('[data-user-auth-guest]');
            var photoAvatar = root.querySelector('[data-user-auth-photo]');
            var emailEl = root.querySelector('[data-user-auth-email]');
            var signInBtn = root.querySelector('[data-user-auth-sign-in]');
            var signOutBtn = root.querySelector('[data-user-auth-sign-out]');
            var toggle = root.querySelector('[data-user-auth-toggle]');
            var avatarUrl = signedIn ? avatarUrlForUser(session.user) : '';

            root.classList.toggle('user-auth--signed-in', signedIn);
            root.classList.toggle('user-auth--signed-out', !signedIn);

            if (guestAvatar) {
                guestAvatar.hidden = signedIn && !!avatarUrl;
            }
            if (photoAvatar) {
                if (signedIn && avatarUrl) {
                    photoAvatar.src = avatarUrl;
                    photoAvatar.alt = session.user.email ? session.user.email + ' profile picture' : 'Your profile picture';
                    photoAvatar.hidden = false;
                } else {
                    photoAvatar.removeAttribute('src');
                    photoAvatar.alt = '';
                    photoAvatar.hidden = true;
                }
            }
            if (emailEl) {
                var email = signedIn && session.user ? session.user.email : '';
                if (email) {
                    emailEl.textContent = email;
                    emailEl.hidden = false;
                } else {
                    emailEl.textContent = '';
                    emailEl.hidden = true;
                }
            }
            if (signInBtn) {
                signInBtn.hidden = signedIn;
            }
            var signInPanel = root.querySelector('[data-user-auth-sign-in-panel]');
            if (signInPanel) {
                signInPanel.hidden = signedIn;
            }
            if (signOutBtn) {
                signOutBtn.hidden = !signedIn;
            }
            if (toggle) {
                toggle.setAttribute(
                    'aria-label',
                    signedIn
                        ? 'Account menu for ' + (session.user.email || 'signed-in user')
                        : 'Account menu — sign in'
                );
            }

            if (!signedIn && !root.classList.contains('is-open')) {
                closeAuthMenu(root);
            }
        });

        syncMobileAuthPresentation();
    }

    function wireAuthMenus() {
        document.querySelectorAll('[data-user-auth]').forEach(function (root) {
            var toggle = root.querySelector('[data-user-auth-toggle]');
            if (!toggle || toggle.getAttribute('data-user-auth-wired') === 'true') {
                return;
            }
            toggle.setAttribute('data-user-auth-wired', 'true');
            toggle.addEventListener('click', function (e) {
                e.stopPropagation();
                var open = !root.classList.contains('is-open');
                closeAllAuthMenus();
                setAuthMenuOpen(root, open);
            });
        });

        if (!document.body.getAttribute('data-user-auth-global-wired')) {
            document.body.setAttribute('data-user-auth-global-wired', 'true');

            document.addEventListener('click', function (e) {
                document.querySelectorAll('[data-user-auth].is-open').forEach(function (root) {
                    if (!root.contains(e.target)) {
                        closeAuthMenu(root);
                    }
                });
            });

            document.addEventListener('keydown', function (e) {
                if (e.key !== 'Escape') {
                    return;
                }
                closeAllAuthMenus();
            });
        }
    }

    function wireAuthButtons() {
        wireAuthMenus();

        document.querySelectorAll('[data-user-auth-sign-in]').forEach(function (btn) {
            if (btn.getAttribute('data-user-auth-wired') === 'true') {
                return;
            }
            btn.setAttribute('data-user-auth-wired', 'true');
            btn.addEventListener('click', function () {
                closeAllAuthMenus();
                signInWithGoogle();
            });
        });

        document.querySelectorAll('[data-user-auth-sign-out]').forEach(function (btn) {
            if (btn.getAttribute('data-user-auth-wired') === 'true') {
                return;
            }
            btn.setAttribute('data-user-auth-wired', 'true');
            btn.addEventListener('click', function () {
                closeAllAuthMenus();
                signOut();
            });
        });

        document.querySelectorAll('[data-user-auth-menu-link]').forEach(function (link) {
            if (link.getAttribute('data-user-auth-wired') === 'true') {
                return;
            }
            link.setAttribute('data-user-auth-wired', 'true');
            link.addEventListener('click', function () {
                closeAllAuthMenus();
            });
        });
    }

    async function init() {
        pauseTurboForOAuthCallback();
        wireAuthButtons();
        syncMobileAuthPresentation();

        if (typeof MOBILE_NAV_MQ.addEventListener === 'function') {
            MOBILE_NAV_MQ.addEventListener('change', syncMobileAuthPresentation);
        } else if (typeof MOBILE_NAV_MQ.addListener === 'function') {
            MOBILE_NAV_MQ.addListener(syncMobileAuthPresentation);
        }

        if (!SUPABASE_URL || !SUPABASE_ANON_KEY) {
            return;
        }

        if (!window.supabase) {
            console.warn('BrpUserSync: Supabase SDK not loaded');
            return;
        }

        initClient();
        if (!client) {
            return;
        }

        var sessionResponse = await client.auth.getSession();
        session = sessionResponse.data.session;
        updateAuthUi();

        if (session) {
            await syncFromCloud();
        }

        client.auth.onAuthStateChange(async function (event, newSession) {
            session = newSession;
            updateAuthUi();

            if ((event === 'SIGNED_IN' || event === 'INITIAL_SESSION') && newSession) {
                await syncFromCloud();
            }
        });

        window.addEventListener('pagehide', flushCloudSave);
        document.addEventListener('visibilitychange', function () {
            if (document.visibilityState === 'hidden') {
                flushCloudSave();
            }
        });
    }

    window.BrpUserSync = {
        isEnabled: function () {
            return !!(SUPABASE_URL && SUPABASE_ANON_KEY);
        },
        isSignedIn: function () {
            return !!session;
        },
        notifyLocalChange: scheduleCloudSave,
        flushLocalChange: flushCloudSave,
        closeAllAuthMenus: closeAllAuthMenus,
    };

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', init);
    } else {
        init();
    }
})();
