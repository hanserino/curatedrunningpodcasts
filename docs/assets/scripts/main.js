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

var LANG_FILTER_STORAGE_KEY = 'brp-language-filter';

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

function browserPrefersEnglish() {
    var langs =
        navigator.languages && navigator.languages.length
            ? Array.prototype.slice.call(navigator.languages)
            : [navigator.language || ''];

    return langs.some(function (lang) {
        return /^en(-|$)/i.test(String(lang).trim());
    });
}

function readStoredLanguageFilter() {
    try {
        var stored = sessionStorage.getItem(LANG_FILTER_STORAGE_KEY);
        return stored === null ? null : stored;
    } catch (_e) {
        return null;
    }
}

function writeStoredLanguageFilter(value) {
    try {
        sessionStorage.setItem(LANG_FILTER_STORAGE_KEY, value);
    } catch (_e) {
        /* ignore */
    }
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

function initLanguageFilterPreference() {
    if (!document.getElementById('lang-english')) {
        return;
    }

    var stored = readStoredLanguageFilter();
    if (stored !== null) {
        setLanguageFilterValue(stored);
        return;
    }

    if (browserPrefersEnglish()) {
        setLanguageFilterValue('english');
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

    var categoryInputs = document.querySelectorAll('input[name="category"]:checked');
    for (var i = 0; i < categoryInputs.length; i++) {
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

    if (!selector) {
        allItems.forEach(function (li) {
            setFilterItemVisible(li, true);
        });
        restorePodcastLoopOrder();
        resetBtns.forEach(function (btn) {
            btn.classList.add('checked');
            btn.setAttribute('aria-pressed', 'true');
        });
    } else {
        allItems.forEach(function (li) {
            setFilterItemVisible(li, false);
        });

        try {
            var matches = document.querySelectorAll(config.itemSelector + selector);
            for (var j = 0; j < matches.length; j++) {
                setFilterItemVisible(matches[j], true);
            }
        } catch (_e) {
            /* malformed selector fallback: show nothing filtered */
        }

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
}

function resetAllFilters() {
    document.querySelectorAll('input[name="category"]').forEach(function (inp) {
        inp.checked = false;
    });

    setLanguageFilterValue('');
    writeStoredLanguageFilter('');

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
    initLanguageFilterPreference();

    document.addEventListener('change', function (e) {
        var target = e.target;
        if (!target) {
            return;
        }
        if (target.name === 'category') {
            applyDirectoryFilter();
        }
        if (target.name === 'language_filter') {
            writeStoredLanguageFilter(target.value);
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
