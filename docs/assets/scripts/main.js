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

function init() {}

function syncGridAria() {
    var isGrid = document.body.getAttribute('data-box-grid') === 'true';
    var el = document.getElementById('grid-switch');
    if (el) {
        el.setAttribute('aria-pressed', isGrid ? 'true' : 'false');
    }
}

var filterTotalItems = 0;

function podcastListItems() {
    return Array.prototype.slice.call(
        document.querySelectorAll('.podcast-loop__item:not(.no-podcast-found)')
    );
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

function updateFilterResultsCount() {
    var el = document.getElementById('filter-results');
    if (!el) {
        return;
    }

    var allItems = podcastListItems();
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

    if (visible === 0) {
        el.textContent = 'No podcasts match these filters. Reset or pick other options below.';
    } else if (filtered) {
        el.textContent =
            'Showing ' + visible + ' of ' + filterTotalItems + ' podcast' + (filterTotalItems === 1 ? '' : 's');
    } else {
        el.textContent = filterTotalItems + ' podcast' + (filterTotalItems === 1 ? '' : 's') + ' in the list';
    }
}

/**
 * Build CSS selector: AND of selected category tag ids + optional single language.
 * data-category on each item lists space-separated tag and language slugs.
 */
function applyPodcastFilter() {
    var allItems = podcastListItems();
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
            li.style.display = '';
        });
        resetBtns.forEach(function (btn) {
            btn.classList.add('checked');
            btn.setAttribute('aria-pressed', 'true');
        });
    } else {
        allItems.forEach(function (li) {
            li.style.display = 'none';
        });

        try {
            var matches = document.querySelectorAll('.podcast-loop__item:not(.no-podcast-found)' + selector);
            for (var j = 0; j < matches.length; j++) {
                matches[j].style.display = '';
            }
        } catch (_e) {
            /* malformed selector fallback: show nothing filtered */
        }

        resetBtns.forEach(function (btn) {
            btn.classList.remove('checked');
            btn.setAttribute('aria-pressed', 'false');
        });
    }

    var visibleCount = podcastListItems().filter(isItemVisible).length;
    if (visibleCount >= 1) {
        document.body.classList.remove('no-podcasts');
    } else {
        document.body.classList.add('no-podcasts');
    }

    updateFilterResultsCount();
}

function resetAllFilters() {
    document.querySelectorAll('input[name="category"]').forEach(function (inp) {
        inp.checked = false;
    });

    var langAll = document.getElementById('lang-all');
    if (langAll) {
        langAll.checked = true;
    }

    podcastListItems().forEach(function (li) {
        li.style.display = '';
    });

    document.querySelectorAll('.filter__reset').forEach(function (btn) {
        btn.classList.add('checked');
        btn.setAttribute('aria-pressed', 'true');
    });

    document.body.classList.remove('no-podcasts');
    updateFilterResultsCount();
}

function setInitialGridModeByViewport() {
    if (typeof window === 'undefined' || typeof document === 'undefined') {
        return;
    }

    var desktopLike = window.matchMedia && window.matchMedia('(min-width: 700px)').matches;
    document.body.setAttribute('data-box-grid', desktopLike ? 'true' : 'false');
}

function wireFilterAndGrid() {
    setInitialGridModeByViewport();
    var boxGrid = document.body.getAttribute('data-box-grid');

    syncGridAria();

    document.addEventListener('change', function (e) {
        var target = e.target;
        if (!target) {
            return;
        }
        if (target.name === 'category' || target.name === 'language_filter') {
            applyPodcastFilter();
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

    updateFilterResultsCount();
}

if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', wireFilterAndGrid);
} else {
    wireFilterAndGrid();
}

window.onload = function () {
    init();

    var touchClass = isTouchDevice() ? 'touch' : 'no-touch';
    document.body.classList.add(touchClass);
    document.body.classList.add('loaded');
};
