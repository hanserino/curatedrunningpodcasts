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


function init(){}

$(document).ready(function(){

    $('.filter,.podcast-loop').delegate('input[type=checkbox]', 'change', function() {
  
        var $filterItems = $('.podcast-loop__item'),
            $checked = $('input:checked');

        if ($checked.length) {		
            var selector = '';
            
            $($checked).each(function(index, element){                      
                selector += "[data-category~='" + element.id + "']";
            });

            $(this).closest('div').find('.filter__reset').removeClass('checked');

            $filterItems.hide();
            $filterItems.filter(selector).show();
        }

        else {
            $filterItems.show();
        }

        if( $('.podcast-loop__item:visible').length >= 1) {
            $('body').removeClass('no-podcasts');
        } else {
            $('body').addClass('no-podcasts');
        }
        
    });


    $('.filter__reset').click(function(){
        $('input[type=checkbox]').prop('checked',false);
        $('.podcast-loop__item').show();

        $(this).addClass('checked');
    });


});



window.onload = function () {
    init();
    
    var touchClass = isTouchDevice() ? "touch" : "no-touch";
    document.body.classList.add(touchClass);
    
    document.body.classList.add("loaded");

}
