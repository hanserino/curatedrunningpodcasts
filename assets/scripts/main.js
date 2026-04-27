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

function updateFilterResultsCount() {
    var el = document.getElementById('filter-results');
    if (!el) {
        return;
    }
    var $allItems = $('.podcast-loop__item').not('.no-podcast-found');
    if (!filterTotalItems) {
        filterTotalItems = $allItems.length;
    }
    var visible = $allItems.filter(':visible').length;
    var hasCategory = $('input[name="category"]:checked').length > 0;
    var hasLang = !!$('input[name="language_filter"]:checked').val();
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
    var $allItems = $('.podcast-loop__item').not('.no-podcast-found');
    var selector = '';

    $('input[name="category"]:checked').each(function () {
        selector += "[data-category~='" + this.id + "']";
    });

    var lang = $('input[name="language_filter"]:checked').val();
    if (lang) {
        selector += "[data-category~='" + lang + "']";
    }

    if (!selector) {
        $allItems.show();
        $('.filter__reset').addClass('checked').attr('aria-pressed', 'true');
    } else {
        $allItems.hide();
        $allItems.filter(selector).show();
        $('.filter__reset').removeClass('checked').attr('aria-pressed', 'false');
    }

    if ($('.podcast-loop__item:visible').not('.no-podcast-found').length >= 1) {
        $('body').removeClass('no-podcasts');
    } else {
        $('body').addClass('no-podcasts');
    }

    updateFilterResultsCount();
}

$(document).ready(function () {
    var boxGrid = $('body').attr('data-box-grid');

    syncGridAria();

    $('.filter,.podcast-loop').on('change', 'input[name="category"]', applyPodcastFilter);
    $('.filter').on('change', 'input[name="language_filter"]', applyPodcastFilter);

    function resetAllFilters() {
        $('input[name="category"]').prop('checked', false);
        $('#lang-all').prop('checked', true);
        $('.podcast-loop__item').not('.no-podcast-found').show();
        $('.filter__reset').addClass('checked').attr('aria-pressed', 'true');
        $('body').removeClass('no-podcasts');
        updateFilterResultsCount();
    }

    $('.filter__reset').on('click', resetAllFilters);

    $('.filter__clear-all').on('click', resetAllFilters);

    $('#grid-switch').on('click', function () {
        boxGrid = boxGrid === 'true' ? 'false' : 'true';
        $('body').attr('data-box-grid', boxGrid);
        syncGridAria();
    });

    updateFilterResultsCount();
});

window.onload = function () {
    init();

    var touchClass = isTouchDevice() ? 'touch' : 'no-touch';
    document.body.classList.add(touchClass);
    document.body.classList.add('loaded');
};