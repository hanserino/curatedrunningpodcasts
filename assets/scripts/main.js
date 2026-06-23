var isTouchDevice = function () {
    return (
        !!(typeof window !== 'undefined' &&
            ('ontouchstart' in window ||
                (window.DocumentTouch &&
                    typeof document !== 'undefined' &&
                    document instanceof window.DocumentTouch))) ||
        !!(typeof navigator !== 'undefined' &&
            (navigator.maxTouchPoints || navigator.msMaxTouchPoints))
    );
};

var OPML_FAVORITES_STORAGE_KEY = 'brp-opml-favorites';

function init() {}

function wireHeaderNav() {
    document.querySelectorAll('[data-header-actions]').forEach(function (shell) {
        var btn = shell.querySelector('.header__menu-toggle');
        if (!btn) {
            return;
        }

        function setOpen(open) {
            shell.classList.toggle('is-open', open);
            btn.setAttribute('aria-expanded', open ? 'true' : 'false');
            btn.setAttribute('aria-label', open ? 'Close menu' : 'Open menu');
        }

        btn.addEventListener('click', function (e) {
            e.stopPropagation();
            setOpen(!shell.classList.contains('is-open'));
        });

        document.addEventListener('click', function (e) {
            if (!shell.classList.contains('is-open')) {
                return;
            }
            if (shell.contains(e.target)) {
                return;
            }
            setOpen(false);
        });

        document.addEventListener('keydown', function (e) {
            if (e.key !== 'Escape') {
                return;
            }
            if (!shell.classList.contains('is-open')) {
                return;
            }
            setOpen(false);
            btn.focus();
        });

        shell.querySelectorAll('.main-nav__link').forEach(function (link) {
            link.addEventListener('click', function () {
                setOpen(false);
            });
        });
    });
}

function syncGridAria() {
    var isGrid = document.body.getAttribute('data-box-grid') === 'true';
    var el = document.getElementById('grid-switch');
    if (el) {
        el.setAttribute('aria-pressed', isGrid ? 'true' : 'false');
    }
}

var filterTotalItems = 0;
var podcastLoopInitialOrder = null;

function getFilterRoot() {
    return document.getElementById('filter');
}

function getFilterConfig() {
    var filter = getFilterRoot();
    var itemSelector = '.podcast-loop__item:not(.no-podcast-found)';
    var noun = 'podcast';

    if (filter) {
        if (filter.getAttribute('data-filter-item')) {
            itemSelector = filter.getAttribute('data-filter-item');
        }
        if (filter.getAttribute('data-filter-noun')) {
            noun = filter.getAttribute('data-filter-noun');
        }
    }

    return { itemSelector: itemSelector, noun: noun };
}

function getPodcastLoop() {
    return document.querySelector('.podcast-loop');
}

function filterListItems() {
    return Array.prototype.slice.call(document.querySelectorAll(getFilterConfig().itemSelector));
}

function getOpmlPodcastFromItem(li) {
    var rssFeed = li ? (li.getAttribute('data-rss-feed') || '').trim() : '';
    if (!rssFeed) {
        return null;
    }

    return {
        title: (li.getAttribute('data-podcast-title') || '').trim(),
        rssFeed: rssFeed,
        url: (li.getAttribute('data-podcast-url') || '').trim()
    };
}

function escapeOpml(value) {
    return String(value || '')
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&apos;');
}

function absolutePodcastUrl(url) {
    if (!url) {
        return '';
    }

    try {
        return new URL(url, window.location.origin).href;
    } catch (_e) {
        return url;
    }
}

function buildOpml(podcasts) {
    var createdAt = new Date().toUTCString();
    var title = 'Best Running Podcasts export';
    var lines = [
        '<?xml version="1.0" encoding="UTF-8"?>',
        '<opml version="2.0">',
        '  <head>',
        '    <title>' + escapeOpml(title) + '</title>',
        '    <dateCreated>' + escapeOpml(createdAt) + '</dateCreated>',
        '  </head>',
        '  <body>'
    ];

    podcasts.forEach(function (podcast) {
        var text = podcast.title || podcast.rssFeed;
        var htmlUrl = absolutePodcastUrl(podcast.url);
        var attrs =
            ' text="' +
            escapeOpml(text) +
            '" title="' +
            escapeOpml(text) +
            '" type="rss" xmlUrl="' +
            escapeOpml(podcast.rssFeed) +
            '"';

        if (htmlUrl) {
            attrs += ' htmlUrl="' + escapeOpml(htmlUrl) + '"';
        }

        lines.push('    <outline' + attrs + ' />');
    });

    lines.push('  </body>', '</opml>', '');
    return lines.join('\n');
}

function downloadTextFile(filename, text, mimeType) {
    var blob = new Blob([text], { type: mimeType });
    var url = URL.createObjectURL(blob);
    var link = document.createElement('a');

    link.href = url;
    link.download = filename;
    link.style.display = 'none';
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);

    window.setTimeout(function () {
        URL.revokeObjectURL(url);
    }, 0);
}

function getOpmlFavoriteId(li) {
    return li ? (li.getAttribute('data-podcast-url') || li.getAttribute('data-podcast-title') || '').trim() : '';
}

function readOpmlFavoriteIds() {
    try {
        var raw = localStorage.getItem(OPML_FAVORITES_STORAGE_KEY);
        var parsed = raw ? JSON.parse(raw) : [];
        return Array.isArray(parsed) ? parsed.filter(Boolean) : [];
    } catch (_e) {
        return [];
    }
}

function writeOpmlFavoriteIds(ids) {
    try {
        localStorage.setItem(OPML_FAVORITES_STORAGE_KEY, JSON.stringify(ids));
    } catch (_e) {
        /* ignore */
    }
}

function getOpmlFavoriteItems() {
    var favoriteIds = readOpmlFavoriteIds();
    return favoriteIds
        .map(function (id) {
            return filterListItems().find(function (li) {
                return getOpmlFavoriteId(li) === id;
            });
        })
        .filter(function (li) {
            return !!getOpmlPodcastFromItem(li);
        });
}

function getOpmlFavoritePodcasts() {
    return getOpmlFavoriteItems().map(getOpmlPodcastFromItem).filter(Boolean);
}

function saveCurrentOpmlFavorites() {
    var ids = filterListItems()
        .filter(function (li) {
            return li.classList.contains('is-opml-favorite') && !!getOpmlPodcastFromItem(li);
        })
        .map(getOpmlFavoriteId);

    writeOpmlFavoriteIds(ids);
}

function setOpmlFavorite(li, favorited) {
    var btn = li ? li.querySelector('[data-opml-favorite]') : null;
    var podcast = getOpmlPodcastFromItem(li);
    if (!li || !btn || !podcast || btn.disabled) {
        return;
    }

    li.classList.toggle('is-opml-favorite', favorited);
    btn.setAttribute('aria-pressed', favorited ? 'true' : 'false');
    btn.setAttribute(
        'aria-label',
        (favorited ? 'Remove ' : 'Add ') + podcast.title + (favorited ? ' from' : ' to') + ' OPML favorites'
    );
    btn.setAttribute('title', favorited ? 'Remove from OPML favorites' : 'Add to OPML favorites');

    var star = btn.querySelector('.podcast-loop__favorite-star');
    if (star) {
        star.textContent = favorited ? '★' : '☆';
    }
    var text = btn.querySelector('[data-opml-favorite-text]');
    if (text) {
        text.textContent = favorited ? 'Remove from OPML favorites' : 'Add to OPML favorites';
    }
}

function renderOpmlFavoritesList(podcasts) {
    var list = document.querySelector('[data-opml-favorites-list]');
    var empty = document.querySelector('[data-opml-favorites-empty]');
    if (!list) {
        return;
    }

    list.innerHTML = '';
    list.hidden = podcasts.length === 0;
    if (empty) {
        empty.hidden = podcasts.length > 0;
    }

    podcasts.forEach(function (podcast) {
        var li = document.createElement('li');
        var title = document.createElement('span');
        var remove = document.createElement('button');

        li.className = 'filter__opml-list-item';
        title.textContent = podcast.title || podcast.rssFeed;
        remove.type = 'button';
        remove.className = 'filter__opml-remove';
        remove.setAttribute('data-opml-remove', podcast.url);
        remove.setAttribute('aria-label', 'Remove ' + title.textContent + ' from OPML favorites');
        remove.textContent = 'x';

        li.appendChild(title);
        li.appendChild(remove);
        list.appendChild(li);
    });
}

function updateOpmlFavoritesUi() {
    var podcasts = getOpmlFavoritePodcasts();
    var panel = document.querySelector('[data-opml-favorites]');
    var exportBtn = document.querySelector('[data-opml-export]');
    var clearBtn = document.querySelector('[data-opml-clear]');
    var countEl = document.querySelector('[data-opml-favorites-count]');
    var count = podcasts.length;
    var hasFavorites = count > 0;

    if (panel) {
        panel.hidden = !hasFavorites;
    }
    if (countEl) {
        countEl.textContent = String(count);
    }
    if (exportBtn) {
        exportBtn.disabled = !hasFavorites;
        exportBtn.setAttribute('aria-disabled', hasFavorites ? 'false' : 'true');
        exportBtn.setAttribute(
            'title',
            hasFavorites
                ? 'Export ' + count + ' favorite podcast' + (count === 1 ? '' : 's') + ' as OPML'
                : 'Star at least one podcast to export'
        );
    }
    if (clearBtn) {
        clearBtn.disabled = !hasFavorites;
        clearBtn.setAttribute('aria-disabled', hasFavorites ? 'false' : 'true');
    }

    renderOpmlFavoritesList(podcasts);
}

function syncOpmlFavoritesFromStorage() {
    var favoriteIds = readOpmlFavoriteIds();
    filterListItems().forEach(function (li) {
        setOpmlFavorite(li, favoriteIds.indexOf(getOpmlFavoriteId(li)) !== -1);
    });
    saveCurrentOpmlFavorites();
    updateOpmlFavoritesUi();
}

function toggleOpmlFavorite(li) {
    if (!getOpmlPodcastFromItem(li)) {
        return;
    }

    setOpmlFavorite(li, !li.classList.contains('is-opml-favorite'));
    saveCurrentOpmlFavorites();
    updateOpmlFavoritesUi();
}

function removeOpmlFavoriteById(id) {
    filterListItems().forEach(function (li) {
        if (getOpmlFavoriteId(li) === id) {
            setOpmlFavorite(li, false);
        }
    });
    saveCurrentOpmlFavorites();
    updateOpmlFavoritesUi();
}

function clearOpmlFavorites() {
    filterListItems().forEach(function (li) {
        setOpmlFavorite(li, false);
    });
    saveCurrentOpmlFavorites();
    updateOpmlFavoritesUi();
}

function exportFavoritePodcastsAsOpml() {
    var podcasts = getOpmlFavoritePodcasts();
    if (!podcasts.length) {
        updateOpmlFavoritesUi();
        return;
    }

    downloadTextFile(
        'best-running-podcasts.opml',
        buildOpml(podcasts),
        'text/x-opml;charset=utf-8'
    );
}

function wireOpmlExport() {
    if (!document.querySelector('[data-opml-favorites]')) {
        return;
    }

    document.querySelector('[data-opml-clear]').addEventListener('click', clearOpmlFavorites);
    document.querySelector('[data-opml-export]').addEventListener('click', exportFavoritePodcastsAsOpml);

    document.addEventListener('click', function (e) {
        var target = e.target;
        var favoriteBtn = target ? target.closest('[data-opml-favorite]') : null;
        var removeBtn = target ? target.closest('[data-opml-remove]') : null;

        if (favoriteBtn) {
            toggleOpmlFavorite(favoriteBtn.closest('.podcast-loop__item'));
            return;
        }

        if (removeBtn) {
            removeOpmlFavoriteById(removeBtn.getAttribute('data-opml-remove'));
        }
    });

    syncOpmlFavoritesFromStorage();
}

function pluralFilterNoun(noun, count) {
    if (count === 1) {
        return noun;
    }
    if (noun === 'episode') {
        return 'episodes';
    }
    return noun + 's';
}

function isFeaturedPodcastItem(li) {
    return li && li.getAttribute('data-featured') === 'true';
}

function cachePodcastLoopOrder() {
    if (!getPodcastLoop()) {
        return;
    }
    podcastLoopInitialOrder = filterListItems().slice();
}

function restorePodcastLoopOrder() {
    var loop = getPodcastLoop();
    if (!loop || !podcastLoopInitialOrder) {
        return;
    }

    podcastLoopInitialOrder.forEach(function (li) {
        loop.appendChild(li);
    });
}

/** Keep visible featured picks first; hidden items stay after visible ones. */
function reorderVisiblePodcastsWithFeaturedFirst() {
    var loop = getPodcastLoop();
    if (!loop) {
        return;
    }

    var visibleFeatured = [];
    var visibleOther = [];
    var hidden = [];

    filterListItems().forEach(function (li) {
        if (!isItemVisible(li)) {
            hidden.push(li);
            return;
        }

        if (isFeaturedPodcastItem(li)) {
            visibleFeatured.push(li);
        } else {
            visibleOther.push(li);
        }
    });

    visibleFeatured.concat(visibleOther).concat(hidden).forEach(function (li) {
        loop.appendChild(li);
    });
}

function setFilterItemVisible(li, visible) {
    li.style.display = visible ? '' : 'none';
}

function itemMatchesOpmlFavorites(li, favoriteIds) {
    var url = li ? (li.getAttribute('data-podcast-url') || '').trim() : '';
    return !!url && favoriteIds.indexOf(url) !== -1;
}

/** True when element is displayed (respects inline display:none from filtering). */
function isItemVisible(li) {
    return window.getComputedStyle(li).display !== 'none';
}

function escapeAttrSel(value) {
    if (typeof CSS !== 'undefined' && typeof CSS.escape === 'function') {
        return CSS.escape(value);
    }
    return String(value).replace(/\\/g, '\\\\').replace(/"/g, '\\"');
}

function setLanguageFilterValue(value) {
    var langAll = document.getElementById('lang-all');
    var radios = document.querySelectorAll('input[name="language_filter"]');
    var matched = false;

    radios.forEach(function (radio) {
        var isMatch = radio.value === value;
        radio.checked = isMatch;
        if (isMatch) {
            matched = true;
        }
    });

    if (!matched && langAll) {
        langAll.checked = true;
    }
}

function updateFilterResultsCount() {
    var el = document.getElementById('filter-results');
    if (!el) {
        return;
    }

    var config = getFilterConfig();
    var allItems = filterListItems();
    if (!filterTotalItems) {
        filterTotalItems = allItems.length;
    }

    var visible = allItems.reduce(function (n, li) {
        return n + (isItemVisible(li) ? 1 : 0);
    }, 0);

    var hasCategory = !!document.querySelector('input[name="category"]:checked');
    var langInput = document.querySelector('input[name="language_filter"]:checked');
    var hasLang = !!(langInput && langInput.value);
    var filtered = hasCategory || hasLang;
    var noun = config.noun;
    var plural = pluralFilterNoun(noun, filterTotalItems);
    var visiblePlural = pluralFilterNoun(noun, visible);

    el.classList.remove('filter__results--active', 'filter__results--empty');

    if (visible === 0) {
        el.textContent = 'No matches — try fewer filters or clear all.';
        el.classList.add('filter__results--empty');
    } else if (filtered) {
        el.textContent =
            'Showing ' + visible + ' of ' + filterTotalItems + ' ' + visiblePlural;
        el.classList.add('filter__results--active');
    } else if (noun === 'episode') {
        el.textContent = filterTotalItems + ' ' + plural + ' from the directory';
    } else {
        el.textContent = filterTotalItems + ' ' + plural + ' in the directory';
    }

    updateFilterChrome();
}

function getActiveFilterCount() {
    var count = document.querySelectorAll('input[name="category"]:checked').length;
    var langInput = document.querySelector('input[name="language_filter"]:checked');
    if (langInput && langInput.value) {
        count += 1;
    }
    return count;
}

function updateFilterChrome() {
    var filter = getFilterRoot();
    var clearBtn = document.querySelector('.filter__clear-all');
    var toggleText = document.querySelector('.filter__toggle-text');
    var panel = document.getElementById('filter-body');
    var activeCount = getActiveFilterCount();
    var hasFilters = activeCount > 0;

    if (filter) {
        filter.classList.toggle('filter--active', hasFilters);
    }

    if (clearBtn) {
        clearBtn.hidden = !hasFilters;
    }

    if (toggleText && panel) {
        var open = !panel.hidden;
        if (open) {
            toggleText.textContent = 'Hide filters';
        } else if (hasFilters) {
            toggleText.textContent = 'Filters (' + activeCount + ')';
        } else {
            toggleText.textContent = 'Show filters';
        }
    }
}

/**
 * Build CSS selector: AND of selected category tag ids + optional single language.
 * data-category on each item lists space-separated tag and language slugs.
 */
function applyDirectoryFilter() {
    var config = getFilterConfig();
    var allItems = filterListItems();
    var selector = '';
    var filterFavorites = false;

    var categoryInputs = document.querySelectorAll('input[name="category"]:checked');
    for (var i = 0; i < categoryInputs.length; i++) {
        if (categoryInputs[i].hasAttribute('data-filter-favorites')) {
            filterFavorites = true;
            continue;
        }
        var id = categoryInputs[i].id;
        if (id) {
            selector += "[data-category~='" + escapeAttrSel(id) + "']";
        }
    }

    var langInput = document.querySelector('input[name="language_filter"]:checked');
    var lang = langInput ? langInput.value : '';
    if (lang) {
        selector += "[data-category~='" + escapeAttrSel(lang) + "']";
    }

    var resetBtns = document.querySelectorAll('.filter__reset');

    if (!selector && !filterFavorites) {
        allItems.forEach(function (li) {
            setFilterItemVisible(li, true);
        });
        restorePodcastLoopOrder();
        resetBtns.forEach(function (btn) {
            btn.classList.add('checked');
            btn.setAttribute('aria-pressed', 'true');
        });
    } else {
        var favoriteIds = filterFavorites ? readOpmlFavoriteIds() : [];
        allItems.forEach(function (li) {
            setFilterItemVisible(li, false);
        });

        allItems.forEach(function (li) {
            var matchesSelector = !selector;
            if (selector) {
                try {
                    matchesSelector = li.matches(selector);
                } catch (_e) {
                    matchesSelector = false;
                }
            }

            var matchesFavorites = !filterFavorites || itemMatchesOpmlFavorites(li, favoriteIds);
            setFilterItemVisible(li, matchesSelector && matchesFavorites);
        });

        if (getPodcastLoop()) {
            reorderVisiblePodcastsWithFeaturedFirst();
        }

        resetBtns.forEach(function (btn) {
            btn.classList.remove('checked');
            btn.setAttribute('aria-pressed', 'false');
        });
    }

    var visibleCount = filterListItems().filter(isItemVisible).length;
    var emptyLatest = document.querySelector('.latest-episodes__empty');
    if (emptyLatest) {
        emptyLatest.hidden = visibleCount >= 1;
    }

    if (getPodcastLoop()) {
        if (visibleCount >= 1) {
            document.body.classList.remove('no-podcasts');
        } else {
            document.body.classList.add('no-podcasts');
        }
    }

    updateFilterResultsCount();
    updateOpmlFavoritesUi();
}

function resetAllFilters() {
    document.querySelectorAll('input[name="category"]').forEach(function (inp) {
        inp.checked = false;
    });

    setLanguageFilterValue('');

    filterListItems().forEach(function (li) {
        setFilterItemVisible(li, true);
    });

    restorePodcastLoopOrder();

    document.querySelectorAll('.filter__reset').forEach(function (btn) {
        btn.classList.add('checked');
        btn.setAttribute('aria-pressed', 'true');
    });

    document.body.classList.remove('no-podcasts');
    var emptyLatest = document.querySelector('.latest-episodes__empty');
    if (emptyLatest) {
        emptyLatest.hidden = true;
    }

    updateFilterResultsCount();
    updateOpmlFavoritesUi();
}

function setInitialGridModeByViewport() {
    if (typeof window === 'undefined' || typeof document === 'undefined') {
        return;
    }

    if (!document.getElementById('grid-switch')) {
        return;
    }

    var desktopLike = window.matchMedia && window.matchMedia('(min-width: 700px)').matches;
    document.body.setAttribute('data-box-grid', desktopLike ? 'true' : 'false');
}

function wireFilterCollapse() {
    var toggle = document.getElementById('filter-toggle');
    var panel = document.getElementById('filter-body');
    if (!toggle || !panel) {
        return;
    }

    function isDesktopFilters() {
        return window.matchMedia && window.matchMedia('(min-width: 700px)').matches;
    }

    function setOpen(open) {
        if (isDesktopFilters()) {
            panel.hidden = false;
            toggle.setAttribute('aria-expanded', 'true');
            return;
        }

        panel.hidden = !open;
        toggle.setAttribute('aria-expanded', open ? 'true' : 'false');
        updateFilterChrome();
    }

    toggle.addEventListener('click', function () {
        setOpen(panel.hidden);
    });

    document.addEventListener('keydown', function (e) {
        if (e.key !== 'Escape') {
            return;
        }
        if (isDesktopFilters() || panel.hidden) {
            return;
        }
        setOpen(false);
        toggle.focus();
    });

    window.addEventListener('resize', function () {
        if (isDesktopFilters()) {
            setOpen(true);
        }
    });

    setOpen(!isDesktopFilters() ? false : true);
}

function wireFilterAndGrid() {
    if (!getFilterRoot()) {
        return;
    }

    setInitialGridModeByViewport();
    var boxGrid = document.body.getAttribute('data-box-grid');

    syncGridAria();
    cachePodcastLoopOrder();
    wireFilterCollapse();
    wireOpmlExport();

    document.addEventListener('change', function (e) {
        var target = e.target;
        if (!target) {
            return;
        }
        if (target.name === 'category') {
            applyDirectoryFilter();
        }
        if (target.name === 'language_filter') {
            applyDirectoryFilter();
        }
    });

    document.querySelectorAll('.filter__reset, .filter__clear-all').forEach(function (el) {
        el.addEventListener('click', resetAllFilters);
    });

    var gridSwitch = document.getElementById('grid-switch');
    if (gridSwitch) {
        gridSwitch.addEventListener('click', function () {
            boxGrid = boxGrid === 'true' ? 'false' : 'true';
            document.body.setAttribute('data-box-grid', boxGrid);
            syncGridAria();
        });
    }

    applyDirectoryFilter();
}

function wireDomReady() {
    wireFilterAndGrid();
    wireHeaderNav();
}

if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', wireDomReady);
} else {
    wireDomReady();
}

window.onload = function () {
    init();

    var touchClass = isTouchDevice() ? 'touch' : 'no-touch';
    document.body.classList.add(touchClass);
    document.body.classList.add('loaded');
};
