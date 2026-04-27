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

$(document).ready(function () {
    var boxGrid = $('body').attr('data-box-grid');

    syncGridAria();

    $('.filter,.podcast-loop').on('change', 'input[type=checkbox]', function () {
        var $filterItems = $('.podcast-loop__item'),
            $checked = $('input[type=checkbox]:checked');

        if ($checked.length) {
            var selector = '';

            $checked.each(function (index, element) {
                selector += "[data-category~='" + element.id + "']";
            });

            $(this).closest('fieldset').find('.filter__reset').removeClass('checked').attr('aria-pressed', 'false');

            $filterItems.hide();
            $filterItems.filter(selector).show();
        } else {
            $filterItems.show();
            $('.filter__reset').addClass('checked').attr('aria-pressed', 'true');
        }

        if ($('.podcast-loop__item:visible').not('.no-podcast-found').length >= 1) {
            $('body').removeClass('no-podcasts');
        } else {
            $('body').addClass('no-podcasts');
        }
    });

    $('.filter__reset').on('click', function () {
        $('input[type=checkbox]').prop('checked', false);
        $('.podcast-loop__item').show();
        $('.filter__reset').addClass('checked').attr('aria-pressed', 'true');
        $('body').removeClass('no-podcasts');
    });

    $('#grid-switch').on('click', function () {
        boxGrid = boxGrid === 'true' ? 'false' : 'true';
        $('body').attr('data-box-grid', boxGrid);
        syncGridAria();
    });
});

window.onload = function () {
    init();

    var touchClass = isTouchDevice() ? 'touch' : 'no-touch';
    document.body.classList.add(touchClass);
    document.body.classList.add('loaded');
};
