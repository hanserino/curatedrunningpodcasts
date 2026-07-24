(function () {
    var STORAGE_KEY = 'brp-analytics-consent-v1';
    var GA_ID = (window.BRP_ANALYTICS_ID || '').trim();
    var clickWired = false;

    function readConsent() {
        try {
            var raw = localStorage.getItem(STORAGE_KEY);
            if (raw === 'granted') return 'granted';
            if (raw === 'denied') return 'denied';
        } catch (e) {}
        return null;
    }

    function saveConsent(value) {
        try {
            localStorage.setItem(STORAGE_KEY, value);
        } catch (e) {}
    }

    function loadGoogleAnalytics() {
        if (!GA_ID || window.__brpGaLoaded) return;
        window.__brpGaLoaded = true;
        window.dataLayer = window.dataLayer || [];
        function gtag() {
            window.dataLayer.push(arguments);
        }
        window.gtag = gtag;
        gtag('js', new Date());
        gtag('config', GA_ID, { anonymize_ip: true });

        var script = document.createElement('script');
        script.async = true;
        script.src = 'https://www.googletagmanager.com/gtag/js?id=' + encodeURIComponent(GA_ID);
        document.head.appendChild(script);
    }

    function bannerEl() {
        return document.getElementById('brp-analytics-consent');
    }

    function hideBanner() {
        var banner = bannerEl();
        if (banner) banner.hidden = true;
    }

    function showBanner() {
        var banner = bannerEl();
        if (banner) banner.hidden = false;
    }

    function acceptAnalytics() {
        saveConsent('granted');
        hideBanner();
        loadGoogleAnalytics();
    }

    function declineAnalytics() {
        saveConsent('denied');
        hideBanner();
    }

    function reopenBanner() {
        if (!GA_ID) return;
        try {
            localStorage.removeItem(STORAGE_KEY);
        } catch (e) {}
        showBanner();
    }

    function wireClicks() {
        if (clickWired) return;
        clickWired = true;
        document.addEventListener('click', function (event) {
            if (event.target.closest('[data-analytics-consent-accept]')) {
                acceptAnalytics();
                return;
            }
            if (event.target.closest('[data-analytics-consent-decline]')) {
                declineAnalytics();
                return;
            }
            if (event.target.closest('[data-analytics-consent-reopen]')) {
                reopenBanner();
            }
        });
    }

    function syncConsentUi() {
        if (!GA_ID) return;
        wireClicks();
        var consent = readConsent();
        if (consent === 'granted') {
            hideBanner();
            loadGoogleAnalytics();
            return;
        }
        if (consent === 'denied') {
            hideBanner();
            return;
        }
        showBanner();
    }

    window.BRPAnalyticsConsent = {
        accept: acceptAnalytics,
        decline: declineAnalytics,
        reopen: reopenBanner,
        getChoice: readConsent,
    };

    syncConsentUi();
    document.addEventListener('turbo:load', syncConsentUi);
    document.addEventListener('DOMContentLoaded', syncConsentUi);
})();
