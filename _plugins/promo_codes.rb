# frozen_string_literal: true

# Scans episode show notes for promo / discount codes and groups them by brand.

require "cgi"
require "yaml"

module PromoCodes
  CODE_STOPWORDS = %w[
    given the this that checkout episode your our their and for with from at to in on
    off discount promo coupon code codes use enter listener listeners podcast
  ].freeze
  BRAND_STOPWORDS = %w[
    the this that and for with from episode episodes podcast podcasts listeners listener
    check out visit download app website link bio merch community presented brought
    all any you when here between every fast fuel run use using want become get save shop
    order orders first your our their off discount gear solution september triathletes
    insights listeners benefit supported conversation listening harder pillow
  ].freeze
  REJECT_BRAND_KEYS = %w[
    all and any the with you when here between every fast fuel run use using want become
    get save shop order orders first off gear solution september triathletes insights
    listeners benefit supported conversation listening harder pillow become a
    mount to coast here want to try vertpro on ios or android is is supported by
    is a conversation worth listening to chasing big goals not just harder to benefit one
    cooling sleep system code distancetoemptypod code hyperlyteliquidper
    hyperlyteliquidperformance sally mcrae strength choose
    nobody asked us podcast from kara goucher and des linden tifosijune
    trail training analytics vert on ios or android cover photo ryan thrower
    cover photo somer kreisman it yourself 15 at kavahaven technology trusted by elite runners
    winner announced at end of with code btp10 with code choosestrong
  ].freeze
  FRAGMENT_BRAND_RX = /
    \b(?:chasing\s+big\s+goals|cover\s+photo|cooling\s+sleep|distancetoempty|hyperlyte|
       sally\s+mcrae\s+strength|nobody.?asked.?us|trail\s+training|worth\s+listening|
       is\s+is\s+supported|is\s+a\s+conversation|vert\s+on\s+ios|want\s+to\s+try|
       to\s+benefit\s+one|not\s+just\s+harder|with\s+code|checkout|rrp\s+items|
       head\s+to|take\s+quiz|go\s+pick|winner\s+announced|technology\s+trusted|
       it\s+yourself|photo\s*:|fast\s+pickle\s+juice|pickle\s+juice\s+shots|
       sleep\s+system|vert\s+pro\s+just|just\s+\$|face\s+mask)\b
  /ix.freeze
  ALLOWED_SINGLE_WORD_BRANDS = %w[
    janji maurten rabbit strava wahoo saily nordvpn olipop feisty altra shokz amazfit
  ].freeze
  CODE_PATTERNS = [
    /(?:use|enter)\s+(?:the\s+)?code\s*:?\s*["']?(?:<[^>]+>)?\s*([A-Za-z0-9][A-Za-z0-9_-]{2,29})(?:<\/[^>]+>)?["']?(?:\s+(?:at checkout|for|to|and))?/i,
    /(?:use|enter)\s+(?:the\s+)?code\s+([A-Za-z0-9][A-Za-z0-9_-]{2,29})(?=for\b)/i,
    /\b(?:bruk|use)\s+(?:koden|the\s+code)\s*:?\s*["']?(?:<[^>]+>)?\s*([A-Za-z0-9][A-Za-z0-9_-]{2,29})(?:<\/[^>]+>)?["']?/i,
    /\b[A-Za-z][A-Za-z0-9&]*-kode\s*:?\s*["']?(?:<[^>]+>)?\s*([A-Za-z0-9][A-Za-z0-9_-]{2,29})(?:<\/[^>]+>)?["']?/i,
    /\brabattkode\s+["']?(?:<[^>]+>)?\s*([A-Za-z0-9][A-Za-z0-9_-]{2,29})(?:<\/[^>]+>)?["']?/i,
    /\bcode\s*:?\s*["']?(?:<[^>]+>)?\s*([A-Za-z0-9][A-Za-z0-9_-]{2,29})(?:<\/[^>]+>)?["']?(?:\s+(?:for|at|to)\b)/i,
    /with\s+code\s+["']?(?:<[^>]+>)?\s*([A-Za-z0-9][A-Za-z0-9_-]{2,29})(?:<\/[^>]+>)?["']?/i,
    /type\s+in\s+this\s+code\s+([A-Za-z0-9][A-Za-z0-9_-]{2,29})/i,
    %r{/discount/([A-Za-z0-9][A-Za-z0-9_-]{2,29})(?:[/?\s"'<>]|$)}i
  ].freeze
  LABELED_KODE_RX = /\b([A-Za-z][A-Za-z0-9&]*)\s*-kode\s*:?\s*$/i.freeze
  URL_PROMO_CODE_RX = [
    /utm_campaign=([A-Z0-9][A-Z0-9_-]{3,19})/,
    %r{ketone\.com/(?!pages/)([A-Za-z0-9]*[0-9][A-Za-z0-9_-]{2,18})(?:[/?\s"'<>]|$)}i
  ].freeze
  HEADING_PARAGRAPH_HTML_RX = /
    <(?:p|h[1-4])[^>]*>\s*
    (?:
      (?:<(?:strong|em|i|b)[^>]*>\s*)?
      (?:<a[^>]+>\s*)?
      ([^<]{2,60}?)
      (?:<\/a>\s*)?
      (?:<\/(?:strong|em|i|b)>\s*)?
    )
    \s*<\/(?:p|h[1-4])>\s*
    <p[^>]*>([\s\S]*?)<\/p>
  /ix.freeze
  INLINE_SPONSOR_HTML_RX = /
    <p[^>]*>\s*
    (?:
      (?:<(?:strong|em|i|b)[^>]*>\s*)?
      (?:<a[^>]+>\s*)?
      ([^<]{2,60}?)
      (?:<\/a>\s*)?
      (?:<\/(?:strong|em|i|b)>\s*)?
    )
    \s*(?:[-–—]\s*|:\s*)
    ([\s\S]*?)
    <\/p>
  /ix.freeze
  HEADING_REJECT_RX = /
    \b(?:support(?:ing)?|sponsor(?:s|ed|ing)?|topics|stay connected|episode sponsor|chat about|looking for|make sure|join the|merch|newsletter|patreon|youtube|instagram|linkedin|spotify|apple podcasts|cover photo|photo:)\b
  /ix.freeze
  BRAND_IN_OFFER_RX = /
    \d{1,3}%\s*off\s+
    (?:
      your\s+(?:first\s+)?order(?:s)?(?:\s+of\s+)?
    )?
    ([A-Za-z][A-Za-z0-9&'’+. -]{1,40}?)
    (?:\s+(?:gear|nutrition|products?|subscription))?
    (?=\s+(?:with|use)\s+code|\s+at\b|[,.]|$)
  /ix.freeze
  AT_BRAND_BEFORE_OFFER_RX = /
    \bat\s+
    ([A-Za-z0-9][A-Za-z0-9&'’+. -]{1,40}?)
    \s+(?:and\s+)?(?:get|shop|save|\d{1,3}%)
  /ix.freeze
  TRYING_PRODUCT_RX = /
    trying\s+(?:the\s+)?
    ([A-Za-z0-9][A-Za-z0-9&'’+. -]{2,55}?)
    \s+yourself
  /ix.freeze
  CODE_AT_DOMAIN_RX = /
    (?:with\s+(?:the\s+)?code|code)\s+
    [A-Za-z0-9][A-Za-z0-9_-]*\s+
    at\s+
    ([a-z0-9.-]+\.[a-z]{2,})
  /ix.freeze
  BRAND_AFTER_OFF_RX = /
    (?:
      use\s+(?:this\s+)?link\s+for\s+\d{1,3}%\s*off\s+
      |
      get\s+\d{1,3}%\s*off\s+
      |
      \d{1,3}%\s*off\s+a\s+subscription\s+of\s+
    )
    ([A-Za-z][A-Za-z0-9-]{2,30})
  /ix.freeze
  EXCLUDED_SPONSOR_DOMAIN_LABELS = %w[
    freetrail mailing podcasters spotify libsyn acast google mail chanel substack
    patreon instagram facebook strava linkedin youtube spotify
  ].freeze
  ZERO_WIDTH_RX = /[\u200B-\u200D\uFEFF\u2060\u00AD]/.freeze
  SPONSOR_FOR_EPISODE_RX = /
    sponsor\s+for\s+this\s+episode
    \s*[-–—:]\s*
    ([^.!\n<]{2,60})
  /ix.freeze
  EPISODE_WAS_SPONSORED_BY_RX = /
    (?:this\s+)?episode\s+was\s+sponsored\s+by\s+
    ([^.!\n<]{2,60})
  /ix.freeze
  SUBSCRIPTION_OFFER_RX = /
    (?:get\s+)?
    \d{1,3}%\s*off\s+your\s+first\s+month\s+and\s+\d{1,3}%\s*off\s+every\s+month\s+after
    (?:\s+with\s+an\s+active\s+subscription)?
  /ix.freeze
  OFFER_BRAND_FRAGMENT_RX = /
    \A(?:every|each|month|after|with\s+an\s+active|first\s+month|your\s+first)
    |\bevery\s+month\s+after\b
  /ix.freeze
  GET_YOUR_PRODUCT_RX = /
    get\s+your\s+
    ([^.!\n<]{2,60}?)
    (?:\s*,?\s*use\s+code|\.\s*use\s+code)
  /ix.freeze
  PRODUCT_BEFORE_USE_CODE_RX = /
    ([A-Za-z0-9][A-Za-z0-9&'’+. -]{2,55}?)
    \s*(?:\u2060|\s)*
    use\s+code
  /ix.freeze
  CAPS_BRAND_BEFORE_USE_CODE_RX = /
    ([A-Z0-9][A-Z0-9&.-]{2,29})
    (?![a-z])
    \s*(?:\u2060|\s)*
    use\s+code
  /ix.freeze
  TYPE_IN_CODE_RX = /
    ([A-Za-z0-9][A-Za-z0-9&'’+. -]{1,40}?)
    \s*[-–—]\s*
    (?:(?:click|visit|check\s+out).*)?
    type\s+in\s+this\s+code
  /ix.freeze
  LINK_BEFORE_USE_CODE_RX = /
    <a[^>]+href=["'][^"']+["'][^>]*>
    ([^<]{2,60})
    <\/a>
    \s*(?:\u2060|\s)*
    use\s+code
  /ix.freeze
  OFFER_PATTERNS = [
    /\d{1,3}%\s*off(?:\s+your\s+(?:first\s+)?(?:order|purchase))(?:\s+at\s+checkout)?/i,
    /\d{1,3}%\s*off(?:\s+your\s+order)?/i,
    /\d{1,3}\s*%\s*rabatt(?:\s+på\s+[^.!]{0,60})?/i,
    /save\s+\d{1,3}%\s+on\s+[^.!]{0,60}/i,
    /\d{1,3}%\s*off(?:\s+[^.!]{0,50})?/i,
    /(?:to\s+)?save\s+\$\s?\d+(?:\.\d{2})?(?:\s+on\s+[^.!]{0,60})?/i,
    /\$\s?\d+(?:\.\d{2})?\s*off(?:\s+[^.!]{0,60})?/i
  ].freeze
  BROUGHT_BY_RX = /
    (?:
      (?:brought\s+to\s+you\s+by|presented\s+by|sponsored\s+by|partnered\s+with|teamed\s+up\s+with|
       check\s+out|visit|try|shop)
      \s+
      ([^.!?\n]{3,80})
    )
  /ix.freeze
  STRONG_BRAND_RX = /
    <strong[^>]*>
    ([^<]{3,120}?)
    (?:\s*(?:—|–|-)\s*|\s+)
    (?:
      \d{1,3}%\s*off
      |
      use\s+code
      |
      code\s*:
      |
      with\s+code
    )
  /ix.freeze
  CHECK_OUT_RX = /
    check\s+out\s+
    ([A-Za-z0-9][A-Za-z0-9&'’+. -]{1,50}?)
    \s*:
  /ix.freeze
  TEAMED_UP_RX = /
    \A
    ([A-Z][A-Za-z0-9&'’. -]{2,40}?)
    \s+have\s+teamed\s+up
  /ix.freeze
  DOMAIN_RX = %r{https?://(?:www\.)?([a-z0-9.-]+\.[a-z]{2,})}i
  BARE_DOMAIN_RX = /\b([a-z0-9][a-z0-9-]{1,62}\.(?:com|co|io|me|net|org|run|show|store|shop|au))\b/i
  JUNK_BRAND_RX = /
    \A(?:unknown brand|code|enter code|use referral code|visit|choose|joining|connect|mailing|bit|ning|them|sponsors?|instagram|other highlights|chasing big goals|become a|in we dive into|store here enter code|cooling sleep system code|core 2 code|velous order code|distancetoemptypod code|fast pickle juice shots code|currex insoles code|dirtbag bars code|janji gear code|janji gear when you|thealbonway20|use code|my|linktr|005|hydration|lotti on|john fitzgerald joins|centurionultrarunningstore|running|sur|us|tion|patreon|youtube|moboboard|rendezvu|somnuslab|trailteam|velous order code|texting us|amzn|linkedin|your|first|order|nutrition|free trail|freetrail)\b
  /ix.freeze
  CANONICAL_BY_DOMAIN = {
    "precisionhydration" => "Precision Fuel & Hydration",
    "intrepidcampgear" => "Intrepid Camp Gear",
    "openfuel" => "Open Fuel",
    "janji" => "Janji",
    "shokz" => "Shokz",
    "saily" => "Saily",
    "amazfit" => "Amazfit",
    "maurten" => "Maurten",
    "vert" => "Vert.run",
    "nordvpn" => "NordVPN",
    "wahoofitness" => "Wahoo",
    "oarrunning" => "OAR Running",
    "mounttocoast" => "Mount to Coast",
    "probionutrition" => "Probio Nutrition",
    "xendurance" => "Xendurance",
    "kavahaven" => "Kava Haven",
    "lagoonsleep" => "Lagoon Sleep",
    "boncharge" => "Bon Charge",
    "mudwtr" => "MUD\\WTR",
    "drinkolipop" => "Olipop",
    "goodranchers" => "Good Ranchers",
    "corebodytemp" => "CORE 2 Body Temperature Sensor",
    "tifosioptics" => "Tifosi Optics",
    "vacationraces" => "Vacation Races",
    "zbiotics" => "ZBiotics",
    "functionhealth" => "Function Health",
    "heavenlyheatsaunas" => "Heavenly Heat Saunas",
    "irestore" => "iRestore",
    "lofresh" => "LoFresh",
    "never2" => "Neversecond",
    "ketone" => "Ketone-IQ",
    "phosperformance" => "Phos Performance",
    "runinrabbit" => "Run in rabbit",
    "rabbit" => "rabbit",
    "soarrunning" => "SOAR Running",
    "summitroasters" => "Summit Roasters",
    "boulderthon" => "Boulderthon",
    "feisty" => "Feisty",
    "altrarunning" => "Altra",
    "hellofresh" => "HelloFresh",
    "gobrewing" => "Go Brewing",
    "fastpickle" => "Fast Pickle",
    "cirqueseries" => "Cirque Series",
    "injinji" => "Injinji",
    "drdirtbag" => "Dirtbag Bars",
    "lever" => "Lever Movement",
    "hdroptech" => "hDrop",
    "wildstrides" => "Wild Strides Paper Co.",
    "centurionrunning" => "Centurion Running",
    "citiusmag" => "CITIUS MAG",
    "livemomentous" => "Momentous",
    "momentous" => "Momentous",
    "dirtbagbars" => "Dirtbag Bars",
    "nobodyaskedus" => "Nobody Asked Us",
    "vertpro" => "VertPro",
    "vertrun" => "Vert.run",
    "boulderboys" => "The Boulder Boys",
    "runtraillife" => "Runtraillife",
    "hyperlyte" => "Hyperlyte",
    "distancetoempty" => "Distance to Empty",
    "extramilest" => "The Extramilest Show",
    "choosestrong" => "Choose Strong",
    "trailrunnernation" => "Trail Runner Nation",
    "trailsociety" => "Trail Society",
    "roadtothetrials" => "Road to the Trials",
    "runninglong" => "Running long",
    "thealbonway" => "The Albon Way",
    "insiderunning" => "Inside Running Podcast",
    "prproject" => "The PR Project",
    "subhub" => "The Sub Hub",
    "midpacker" => "The Midpacker Podcast",
    "getpace" => "Pace",
    "comfyballs" => "Comfyballs"
  }.freeze
  PRODUCT_NAME_ALIASES = [
    [/\bcore\s*2(?:\s+body\s+temperature(?:\s+sensor)?)?\b|corebodytemp/i, "CORE 2 Body Temperature Sensor"],
    [/janji/i, "Janji"],
    [/precision|precisionhydration/i, "Precision Fuel & Hydration"],
    [/intrepid/i, "Intrepid Camp Gear"],
    [/open\s*fuel|openfuel/i, "Open Fuel"],
    [/shokz/i, "Shokz"],
    [/saily/i, "Saily"],
    [/summit\s*roasters/i, "Summit Roasters"],
    [/neversecond|never2/i, "Neversecond"],
    [/ketone(?:\s*iq|-iq)?/i, "Ketone-IQ"],
    [/lever(?:\s+movement)?/i, "Lever Movement"],
    [/wild\s*strides/i, "Wild Strides Paper Co."],
    [/beekeeper/i, "Beekeeper's Naturals"],
    [/hdrop/i, "hDrop"],
    [/dirtbag\s*bars?/i, "Dirtbag Bars"],
    [/centurion/i, "Centurion Running"],
    [/\bphos(?:\s+performance)?\b/i, "Phos Performance"],
    [/\bcitius(?:\s+mag)?\b/i, "CITIUS MAG"],
    [/momentous|livemomentous/i, "Momentous"],
    [/mount\s*to\s*coast/i, "Mount to Coast"],
    [/probio/i, "Probio Nutrition"],
    [/go\s*brewing/i, "Go Brewing"],
    [/tifosi/i, "Tifosi Optics"],
    [/feisty/i, "Feisty"],
    [/vert\.?run|vertpro|vert on ios/i, "Vert.run"],
    [/nobody\s*asked\s*us/i, "Nobody Asked Us"],
    [/bon\s*charge|boncharge/i, "BONCHARGE"],
    [/distance\s*to\s*empty/i, "Distance to Empty"],
    [/trail\s*runner\s*nation/i, "Trail Runner Nation"],
    [/trail\s*society/i, "Trail Society"],
    [/road\s*to\s*the\s*trials/i, "Road to the Trials"],
    [/running\s*long/i, "Running long"],
    [/albon\s*way/i, "The Albon Way"],
    [/inside\s*running/i, "Inside Running Podcast"],
    [/sub\s*hub/i, "The Sub Hub"],
    [/midpacker/i, "The Midpacker Podcast"],
    [/\bstrava\b/i, "Strava"],
    [/fast\s*pickle|pickle\s*juice/i, "Fast Pickle"],
    [/boulder\s*boys/i, "The Boulder Boys"],
    [/vacation\s*races/i, "Vacation Races"],
    [/naturals|beekeeper/i, "Beekeeper's Naturals"]
  ].freeze

  module_function

  def sanitize_show_notes(text)
    cleaned = CGI.unescapeHTML(text.to_s)
    cleaned = cleaned.gsub(ZERO_WIDTH_RX, "")
    cleaned.gsub(/\s+/, " ").strip
  end

  def normalize_key(text)
    text.to_s.downcase.gsub(/[^a-z0-9]+/, " ").strip.gsub(/\s+/, " ")
  end

  def running_podcast?(doc)
    value = doc.data["not_running_related"]
    !(value == true || value.to_s.strip.downcase == "true")
  end

  def valid_code?(code)
    token = code.to_s.strip
    return false if token.empty?
    return false if token.length < 3 || token.length > 30
    return false if CODE_STOPWORDS.include?(token.downcase)
    return false unless token.match?(/\A[A-Za-z0-9][A-Za-z0-9_-]*\z/)

    token.match?(/[A-Z0-9]/) && !token.match?(/\A[a-z]+\z/)
  end

  def domain_label(host)
    host.to_s.downcase.sub(/\Awww\./, "").split(".").first.to_s.gsub(/[^a-z0-9]/, "")
  end

  def domain_to_brand(domain)
    label = domain_label(domain)
    return CANONICAL_BY_DOMAIN[label] if CANONICAL_BY_DOMAIN[label]

    return nil if label.empty?

    label
      .gsub(/([a-z])([A-Z])/, '\1 \2')
      .gsub(/[-_]+/, " ")
      .split(" ")
      .map { |part| part.capitalize }
      .join(" ")
  end

  def extract_domains(context)
    hosts = context.to_s.scan(DOMAIN_RX).flatten
    hosts += context.to_s.scan(BARE_DOMAIN_RX).flatten
    hosts.map { |host| host.to_s.downcase.sub(/\Awww\./, "") }.uniq
  end

  def sponsor_domains(domains)
    filtered = Array(domains).reject do |host|
      label = domain_label(host)
      EXCLUDED_SPONSOR_DOMAIN_LABELS.any? { |excluded| label == excluded || label.start_with?(excluded) }
    end
    filtered.any? ? filtered : Array(domains)
  end

  def brand_from_trying_product(context)
    match = sanitize_show_notes(context).match(TRYING_PRODUCT_RX)
    return nil unless match

    cleaned = clean_brand_name(match[1])
    cleaned if cleaned && plausible_product_name?(cleaned)
  end

  def brand_from_code_at_domain(context)
    match = sanitize_show_notes(context).match(CODE_AT_DOMAIN_RX)
    return nil unless match

    brand = domain_to_brand(match[1])
    finalized = finalize_product_name(brand, [match[1].to_s.downcase]) if brand
    finalized if finalized && plausible_product_name?(finalized)
  end

  def offer_brand_candidates(context)
    text = context.to_s
    candidates = []

    if (brand = brand_from_trying_product(text))
      candidates << brand
    end
    if (brand = brand_from_code_at_domain(text))
      candidates << brand
    end
    if (match = text.match(BRAND_IN_OFFER_RX))
      candidate = match[1].to_s
      unless candidate.match?(/\b(?:with|use)\s+(?:the\s+)?code\b/i) ||
             candidate.match?(OFFER_BRAND_FRAGMENT_RX)
        finalized = finalize_product_name(candidate, extract_domains(text))
        candidates << finalized if finalized && plausible_product_name?(finalized)
      end
    end
    if (match = text.match(BRAND_AFTER_OFF_RX))
      finalized = finalize_product_name(match[1], extract_domains(text))
      candidates << finalized if finalized && plausible_product_name?(finalized)
    end
    if (match = text.match(AT_BRAND_BEFORE_OFFER_RX))
      finalized = finalize_product_name(match[1], extract_domains(text))
      candidates << finalized if finalized && plausible_product_name?(finalized)
    end

    candidates.compact.uniq
  end

  def brand_from_product_in_offer(context)
    offer_brand_candidates(context).first
  end

  def plausible_product_name?(name)
    text = name.to_s.strip
    return false unless acceptable_brand_name?(text)

    key = normalize_key(text)
    return false if REJECT_BRAND_KEYS.include?(key)
    return false if text.split.size == 1 && !ALLOWED_SINGLE_WORD_BRANDS.include?(text.downcase)
    return false if text.match?(/\A(?:all|any)\s+order/i)

    true
  end

  def publishable_brand?(name, domains)
    text = name.to_s.strip
    return false unless plausible_product_name?(text)
    return false if text.match?(/\b(?:with code|use code|enter code|checkout|http|www\.)\b/i)
    return false if text.match?(%r{[@/\\]|\.com\b|\.co\b}i)
    return false if text.match?(/\p{Extended_Pictographic}/u)
    return false if text.match?(/\A(?:is|a|to|on|at|pro|not|now|take|way|mask|all|any|the|and|with|you|when|here)\b/i)
    return false if text.match?(/\b(?:is by|is is|worth listening|rrp items|head to|take quiz|go pick|buy wahoo|website)\b/i)
    return false if text.match?(/\d{1,3}%\s*(?:of|off)\b/i)
    return false if normalize_key(text).split.size > 6

    high_confidence_product?(text, domains)
  end

  def extract_trailing_product(segment)
    text = segment.to_s.strip
    text = text.sub(/\d{1,3}%\s*off\s*/i, "")
    text = text.sub(/\bsave\s+\$?\d+(?:\.\d{2})?[^.]*\s+on\s+/i, "")
    text = text.sub(/\b(?:on|for)\s+(?:all|any)\s+orders?\z/i, "")
    text = text.strip
    return nil if text.empty?

    words = text.split(/\s+/)
    [3, 2, 1].each do |count|
      candidate = words.last(count)&.join(" ")
      next if candidate.nil? || candidate.empty?

      cleaned = clean_brand_name(candidate)
      return cleaned if cleaned && plausible_product_name?(cleaned)
    end

    nil
  end

  def brand_from_with_code(context, code)
    sanitized = sanitize_show_notes(context)
    trigger = sanitized.match(/with\s+code\s+#{Regexp.escape(code)}\b/i)
    return nil unless trigger

    before = sanitized[0, trigger.begin(0)].to_s.strip
    segment = before.split(/\band\s+|\.\s+/).last.to_s.strip
    return nil if segment.empty?
    return nil if segment.match?(/\A(?:all|any)\s+orders?\z/i)

    offer_brand = brand_from_product_in_offer(segment)
    return offer_brand if offer_brand

    extract_trailing_product(segment)
  end

  def brand_from_and_use_code(context, code)
    match = sanitize_show_notes(context).match(
      /([A-Za-z0-9][A-Za-z0-9&'’+. -]{1,50}?)\s+and\s+use\s+(?:the\s+)?code\s+#{Regexp.escape(code)}\b/i
    )
    return nil unless match

    cleaned = clean_brand_name(match[1])
    cleaned if cleaned && plausible_product_name?(cleaned)
  end

  def brand_from_leading_label(context)
    text = sanitize_show_notes(context)
    if (match = text.match(/(?:^|\s)([A-Z][A-Za-z0-9-]{2,30})\s+Use\s+(?:code|this link)/i))
      finalized = finalize_product_name(match[1], extract_domains(text))
      return finalized if finalized
    end
    if (match = text.match(/\A(?:sponsors?\s+)?([A-Z][A-Za-z0-9-]{2,30})\s+(?:use|get|go)\b/i))
      finalized = finalize_product_name(match[1], extract_domains(text))
      return finalized if finalized
    end

    nil
  end

  def high_confidence_product?(name, domains)
    Array(domains).each do |host|
      label = domain_label(host)
      return true if CANONICAL_BY_DOMAIN[label]
    end

    text = name.to_s.strip
    return false unless plausible_product_name?(text)
    return false if text.split.size > 5
    return false if text.match?(/\b(?:joins|dive|highlights|order code|referral|texting|youtube|patreon|insoles code|bars code|trailrunning|personalised|plans data)\b/i)
    return false if text.match?(/\A(?:running|sur|us|tion|my|ascend)\z/i)

    words = text.split
    return false if words.any? do |word|
      token = word.downcase.delete(".")
      token.length <= 2 && !%w[co llc uk us go].include?(token) && !%w[ZBiotics MUD\WTR].include?(text)
    end

    Array(domains).each do |host|
      label = domain_label(host)
      return true if label.length >= 4 && !%w[linktr patreon youtube linkedin amzn].include?(label)
    end

    return true if text.match?(/\A[A-Z0-9&.-]{3,30}\z/)
    return true if text.match?(/\A[A-Z][a-zA-Z0-9&.-]{2,24}\z/)
    return true if text.split.size >= 2

    ALLOWED_SINGLE_WORD_BRANDS.include?(text.downcase)
  end

  def canonical_product(name, domains, context: nil)
    if context
      domains_for_context = sponsor_domains(extract_domains(context.to_s))
      offer_brand = brand_from_episode_was_sponsored(context) ||
                    brand_from_trying_product(context) ||
                    brand_from_code_at_domain(context) ||
                    brand_from_product_in_offer(context) ||
                    brand_from_leading_label(context)
      if offer_brand
        finalized = finalize_product_name(offer_brand, domains_for_context)
        return finalized if finalized && publishable_brand?(finalized, domains_for_context)
      end
    end

    cleaned = clean_brand_name(name)
    if cleaned
      finalized = finalize_product_name(cleaned, sponsor_domains(domains))
      if finalized && publishable_brand?(finalized, sponsor_domains(domains))
        return finalized
      end
    end

    sponsor_domains(domains).each do |host|
      label = domain_label(host)
      canonical = CANONICAL_BY_DOMAIN[label]
      return canonical if canonical

      brand = domain_to_brand(host)
      finalized = finalize_product_name(brand, domains) if brand
      return finalized if finalized && publishable_brand?(finalized, sponsor_domains(domains))
    end

    nil
  end

  def finalize_product_name(name, domains)
    text = name.to_s.strip
    PRODUCT_NAME_ALIASES.each do |pattern, canonical|
      return canonical if text.match?(pattern)
    end

    key = normalize_key(text)
    PRODUCT_NAME_ALIASES.each do |pattern, canonical|
      return canonical if key.match?(pattern)
    end

    return nil unless acceptable_brand_name?(text)

    text
  end

  def canonical_product_key(name)
    normalize_key(name)
  end

  def acceptable_brand_name?(name)
    text = name.to_s.strip
    return false if text.empty? || text.length < 2 || text.length > 60
    return false if text.match?(/\A\d+\z/)
    return false if text.match?(JUNK_BRAND_RX)
    return false if text.match?(FRAGMENT_BRAND_RX)
    return false if REJECT_BRAND_KEYS.include?(normalize_key(text))
    return false if text.split.size > 7
    return false if text.match?(/\buse code\b/i)
    return false if text.match?(/\benter code\b/i)
    return false if text.match?(/\bgear code\b/i)
    return false if text.match?(/\bwhen you\b/i)
    return false if text.match?(/\A(?:become|want|using|benefit|order|save|shop|get|visit|listen|try)\b/i)
    return false if text.match?(/\b(?:here|code)\z/i)
    return false if text.split.all? { |word| BRAND_STOPWORDS.include?(word.downcase) }

    true
  end

  def clean_brand_name(name)
    text = name.to_s.strip
    text = CGI.unescapeHTML(text)
    text = text.gsub(%r{https?://\S+}i, " ")
    text = text.gsub(/[[:punct:]]+\z/, "")
    text = text.gsub(/\s*(?:for|at)\s+checkout\z/i, "")
    text = text.gsub(/\s+use\s+code.*\z/i, "")
    text = text.gsub(/\A(?:register|sign\s+up|visit|shop|download|check\s+out)\s+(?:at|the)\s+/i, "")
    text = text.gsub(/\s+/, " ").strip

    words = text.split(" ").reject { |word| BRAND_STOPWORDS.include?(word.downcase) }
    cleaned = words.join(" ").strip
    return nil if cleaned.length < 2
    return nil if cleaned.match?(/\buse code\b/i)
    return nil if REJECT_BRAND_KEYS.include?(normalize_key(cleaned))
    return nil if cleaned.split.all? { |word| BRAND_STOPWORDS.include?(word.downcase) }

    cleaned[0, 60]
  end

  def normalize_offer(offer)
    text = offer.to_s.gsub(/\s+/, " ").strip
    if (match = text.match(/\A(?:to\s+)?save\s+(\$\s?\d+(?:\.\d{2})?\s+on\s+.+)/i))
      return "Save #{match[1].strip}"
    end
    if (match = text.match(/\Asave\s+(\d{1,3}%\s+on\s+.+)/i))
      return "Save #{match[1].strip}"
    end

    text
  end

  def extract_offer(context)
    text = context.to_s.gsub(/\s+/, " ").strip

    if (match = text.match(SUBSCRIPTION_OFFER_RX))
      offer = match[0].to_s.gsub(/\s+/, " ").strip
      offer = offer.sub(/\Aget\s+/i, "")
      offer = offer.sub(/\s+with\s+an\s+active\s+subscription\z/i, "")
      return offer
    end

    OFFER_PATTERNS.each do |pattern|
      match = text.match(pattern)
      next unless match

      offer = normalize_offer(match[0].to_s.gsub(/\s+/, " ").strip)
      offer = offer.sub(/\s+(?:at checkout|and use code|use code).*$/i, "").strip
      return offer if offer.length >= 4
    end

    nil
  end

  def sponsor_block_has_code?(text)
    text.to_s.match?(/(?:use|enter)\s+(?:the\s+)?code/i) ||
      text.to_s.match?(/(?:bruk|use)\s+(?:koden|the\s+code)/i) ||
      text.to_s.match?(/\b[A-Za-z][A-Za-z0-9&]*-kode\s*:/i) ||
      text.to_s.match?(/\brabattkode\b/i) ||
      text.to_s.match?(/type\s+in\s+this\s+code/i) ||
      text.to_s.match?(/utm_campaign=/i) ||
      text.to_s.match?(%r{ketone\.com/[A-Za-z0-9]{4,}}i)
  end

  def valid_heading_brand?(heading)
    text = heading.to_s.strip
    return false if text.empty? || text.length > 60
    return false if text.match?(HEADING_REJECT_RX)
    return false if text.match?(/\buse code\b/i)
    return false unless plausible_product_name?(text)

    words = text.split(/\s+/)
    return false if words.size > 6

    true
  end

  def extract_heading_sponsor_blocks(html)
    blocks = []
    seen = {}

    append_block = lambda do |heading, body_html|
      heading_clean = clean_brand_name(CGI.unescapeHTML(heading.to_s)) || heading.to_s.strip
      body_html = body_html.to_s
      return unless valid_heading_brand?(heading_clean)
      return unless sponsor_block_has_code?(body_html)

      plain_body = sanitize_show_notes(CGI.unescapeHTML(body_html.gsub(/<[^>]+>/, " ")))
      key = "#{heading_clean.downcase}|#{plain_body[0, 80]}"
      return if seen[key]

      seen[key] = true
      blocks << {
        brand: heading_clean,
        html: body_html,
        plain: plain_body
      }
    end

    html.to_s.scan(HEADING_PARAGRAPH_HTML_RX) do |heading, body|
      append_block.call(heading, body)
    end

    html.to_s.scan(INLINE_SPONSOR_HTML_RX) do |heading, body|
      append_block.call(heading, body)
    end

    blocks
  end

  def extract_list_sponsor_blocks(html)
    blocks = []
    seen = {}

    html.to_s.scan(/<li[^>]*>([\s\S]*?)<\/li>/im) do |body_html|
      body_html = body_html.to_s
      plain_body = sanitize_show_notes(CGI.unescapeHTML(body_html.gsub(/<[^>]+>/, " ")))
      next unless sponsor_block_has_code?(plain_body)

      codes = extract_codes("#{plain_body} #{body_html}")
      brand = brand_from_product_in_offer(plain_body) ||
              brand_from_leading_label(plain_body)
      brand ||= brand_from_labeled_kode(plain_body, codes.first) if codes.any?
      domains = extract_domains("#{plain_body} #{body_html}")
      brand ||= domain_to_brand(sponsor_domains(domains).first) if sponsor_domains(domains).any?
      brand = clean_brand_name(brand) || brand
      next unless brand && valid_heading_brand?(brand)

      key = "#{brand.downcase}|#{plain_body[0, 80]}"
      next if seen[key]

      seen[key] = true
      blocks << {
        brand: brand,
        html: body_html,
        plain: plain_body
      }
    end

    blocks
  end

  def combined_show_notes(plain, html)
    sanitize_show_notes("#{plain} #{CGI.unescapeHTML(html.to_s.gsub(/<[^>]+>/, ' '))}")
  end

  def sponsor_context_before_code(plain, html, index)
    combined = combined_show_notes(plain, html)
    before = combined[0, index.to_i] || ""
    return "" if before.empty?

    if (match = before.match(/(?:(?:this\s+)?episode\s+was\s+sponsored\s+by|sponsored\s+by|brought\s+to\s+you\s+by|presented\s+by)[\s\S]{0,500}$/i))
      return match[0].strip
    end

    context_before_code(combined, index, 350)
  end

  def context_for_code(plain, html, code)
    index = plain.index(/#{Regexp.escape(code)}/i) ||
            html.index(/#{Regexp.escape(code)}/i) ||
            html.index(/utm_campaign=#{Regexp.escape(code)}/i) ||
            html.index(%r{ketone\.com/#{Regexp.escape(code)}}i) ||
            0
    line_context = sponsor_line_for_code(plain, code)
    combined = combined_show_notes(plain, html)
    sponsor_context = sponsor_context_before_code(plain, html, index)
    context = context_around(combined, index)
    brand_context = if sponsor_context.length >= 20
                      sponsor_context
                    elsif line_context.length >= 12
                      line_context
                    else
                      context_before_code(combined, index)
                    end
    offer_context = if sponsor_context.match?(SUBSCRIPTION_OFFER_RX)
                      sponsor_context
                    elsif line_context.length >= 12
                      line_context
                    else
                      context
                    end
    [brand_context, offer_context, index]
  end

  def promo_context?(text)
    text.to_s.match?(/(?:\d{1,3}%\s*off|\d{1,3}\s*%\s*rabatt|use\s+(?:this\s+)?link|discount|promo|save|subscription|rabattkode)/i) ||
      text.to_s.match?(/ketone\.com/i)
  end

  def normalize_code_token(code)
    token = code.to_s.strip
    return token if token.empty?

    token.match?(/[a-z]/) ? token.upcase : token
  end

  def extract_url_promo_codes(text)
    found = []

    URL_PROMO_CODE_RX.each do |pattern|
      text.to_s.scan(pattern) do |capture|
        code = capture.is_a?(Array) ? capture.first : capture
        code = normalize_code_token(code)
        next unless valid_code?(code)

        idx = Regexp.last_match.begin(0)
        window = text[[idx - 160, 0].max, 160]
        next unless promo_context?(window)

        found << code
      end
    end

    found
  end

  def extract_codes(text)
    found = []

    CODE_PATTERNS.each do |pattern|
      text.to_s.scan(pattern) do |capture|
        code = normalize_code_token(capture.is_a?(Array) ? capture.first : capture)
        next unless valid_code?(code)

        found << code
      end
    end

    found.concat(extract_url_promo_codes(text))
    dedupe_codes(found.uniq)
  end

  def dedupe_codes(codes)
    sorted = Array(codes).sort_by { |code| -code.to_s.length }
    kept = []

    sorted.each do |code|
      token = code.to_s.upcase
      next if kept.any? do |existing|
        existing.upcase.start_with?(token) && existing.length > token.length
      end

      kept << code
    end

    kept
  end

  def context_around(text, index, radius = 200)
    start = [index - radius, 0].max
    length = [radius * 2, text.length - start].min
    text[start, length].to_s
  end

  def context_before_code(text, index, radius = 110)
    start = [index - radius, 0].max
    text[start, index - start].to_s
  end

  def sponsor_line_for_code(text, code)
    sanitized = sanitize_show_notes(text)
    trigger = sanitized.match(/(?:use|enter)\s+(?:the\s+)?code\s+#{Regexp.escape(code)}\b/i) ||
              sanitized.match(/(?:bruk|use)\s+(?:koden|the\s+code)\s*:?\s*#{Regexp.escape(code)}\b/i) ||
              sanitized.match(/\b[A-Za-z][A-Za-z0-9&]*-kode\s*:\s*#{Regexp.escape(code)}\b/i) ||
              sanitized.match(/\brabattkode\s+#{Regexp.escape(code)}\b/i) ||
              sanitized.match(/with\s+code\s+#{Regexp.escape(code)}\b/i) ||
              sanitized.match(/type in this code\s+#{Regexp.escape(code)}\b/i)
    return "" unless trigger

    idx = trigger.begin(0)
    prefix_start = [idx - 90, 0].max
    prefix = sanitized[prefix_start, idx - prefix_start].to_s
    prefix = prefix.split(/(?:\p{So}|(?:\.\s+)|(?:,\s+))/u).last.to_s.strip
    segment = sanitized[idx, [trigger[0].length + 120, sanitized.length - idx].min].to_s.strip
    segment = segment.split(/\.\s+/).first.to_s.strip
    [prefix, segment].reject(&:empty?).join(" ").strip
  end

  def brand_from_strong_html(html, code)
    html.to_s.scan(STRONG_BRAND_RX) do |brand_fragment,|
      fragment = brand_fragment.to_s
      next unless fragment.match?(/#{Regexp.escape(code)}/i) || html.to_s.match?(/#{Regexp.escape(code)}/i)

      brand = fragment.split(/(?:—|–|-|\d{1,3}%\s*off|use\s+code|with\s+code|code\s*:)/i).first
      cleaned = clean_brand_name(brand)
      return cleaned if cleaned
    end

    nil
  end

  def brand_from_brought_by(context)
    match = context.match(BROUGHT_BY_RX)
    return nil unless match

    candidate = match[1].to_s.split(/[.!?\n]/).first
    candidate = candidate.split(/\b(?:use|enter|visit|download|for more)\b/i).first
    clean_brand_name(candidate)
  end

  def brand_from_episode_sponsor(context)
    match = context.match(SPONSOR_FOR_EPISODE_RX)
    return nil unless match

    clean_brand_name(match[1])
  end

  def brand_from_episode_was_sponsored(context)
    match = sanitize_show_notes(context).match(EPISODE_WAS_SPONSORED_BY_RX)
    return nil unless match

    clean_brand_name(match[1])
  end

  def brand_from_get_your_product(context)
    match = context.match(GET_YOUR_PRODUCT_RX)
    return nil unless match

    clean_brand_name(match[1])
  end

  def brand_from_type_in_code(context)
    match = context.match(TYPE_IN_CODE_RX)
    return nil unless match

    clean_brand_name(match[1])
  end

  def html_near_code(html, code)
    source = html.to_s
    idx = source.index(/(?:use|enter)\s+(?:the\s+)?code[^<]{0,40}#{Regexp.escape(code)}/i) ||
          source.index(/#{Regexp.escape(code)}/i)
    return "" unless idx

    source[[idx - 450, 0].max, 650]
  end

  def brand_from_link_before_use_code(html, context, code)
    snippet = html.to_s.length > 600 ? html_near_code(html, code) : html.to_s
    snippet = snippet.empty? ? context.to_s : snippet
    match = snippet.match(LINK_BEFORE_USE_CODE_RX) || context.to_s.match(LINK_BEFORE_USE_CODE_RX)
    return nil unless match

    clean_brand_name(match[1])
  end

  def brand_from_caps_before_use_code(context, _code)
    match = sanitize_show_notes(context).match(CAPS_BRAND_BEFORE_USE_CODE_RX)
    return nil unless match

    clean_brand_name(match[1])
  end

  def brand_from_product_before_use_code(context, code)
    before = sanitize_show_notes(context).split(/#{Regexp.escape(code)}/i).first.to_s
    match = before.match(PRODUCT_BEFORE_USE_CODE_RX) || before.match(CAPS_BRAND_BEFORE_USE_CODE_RX)
    return nil unless match

    candidate = match[1].to_s.strip
    return nil if candidate.match?(/\b(?:pod|support|purchase|click|type in)\b/i)

    clean_brand_name(candidate)
  end

  def brand_from_teamed_up(context)
    sentence = context.to_s.split(/[.!?\n]/).find { |part| part.match?(/have\s+teamed\s+up/i) }
    return nil unless sentence

    match = sentence.match(TEAMED_UP_RX)
    return nil unless match

    clean_brand_name(match[1])
  end

  def brand_from_labeled_kode(context, code)
    before = sanitize_show_notes(context).split(/#{Regexp.escape(code)}/i).first.to_s
    match = before.match(LABELED_KODE_RX)
    return nil unless match

    cleaned = clean_brand_name(match[1])
    cleaned if cleaned && plausible_product_name?(cleaned)
  end

  def brand_from_plain_context(context, code)
    before = sanitize_show_notes(context).split(/#{Regexp.escape(code)}/i).first.to_s
    before = before.split(/[.!?\n]/).last.to_s

    if (match = before.match(/([A-Z0-9][A-Za-z0-9&'’+. -]{2,50})\s*(?:—|–|-|:)\s*\z/))
      cleaned = clean_brand_name(match[1])
      return cleaned if cleaned && plausible_product_name?(cleaned)
    end

    if (match = before.match(/([A-Z][A-Za-z0-9&'’+. -]{2,40})\s*\z/))
      cleaned = clean_brand_name(match[1])
      return cleaned if cleaned && plausible_product_name?(cleaned) && cleaned.split.size <= 5
    end

    brand_from_caps_before_use_code(context, code) ||
      brand_from_product_before_use_code(context, code) ||
      brand_from_teamed_up(context) ||
      brand_from_brought_by(context)
  end

  def brand_from_check_out(context)
    match = context.match(CHECK_OUT_RX)
    return nil unless match

    clean_brand_name(match[1])
  end

  def infer_brand(html, plain, code, context)
    sanitized_context = sanitize_show_notes(context)

    brand_from_episode_was_sponsored(sanitized_context) ||
      brand_from_trying_product(sanitized_context) ||
      brand_from_code_at_domain(sanitized_context) ||
      brand_from_labeled_kode(sanitized_context, code) ||
      brand_from_with_code(sanitized_context, code) ||
      brand_from_and_use_code(sanitized_context, code) ||
      brand_from_product_in_offer(sanitized_context) ||
      brand_from_leading_label(sanitized_context) ||
      brand_from_link_before_use_code(html, sanitized_context, code) ||
      brand_from_strong_html(html, code) ||
      brand_from_product_before_use_code(sanitized_context, code) ||
      brand_from_type_in_code(sanitized_context) ||
      brand_from_episode_sponsor(sanitized_context) ||
      brand_from_get_your_product(sanitized_context) ||
      brand_from_check_out(sanitized_context) ||
      brand_from_caps_before_use_code(sanitized_context, code) ||
      brand_from_teamed_up(sanitized_context) ||
      brand_from_plain_context(sanitized_context, code) ||
      brand_from_brought_by(sanitized_context) ||
      sponsor_domains(extract_domains(sanitized_context)).map { |host| CANONICAL_BY_DOMAIN[domain_label(host)] }.compact.first ||
      sponsor_domains(extract_domains(sanitized_context)).filter_map do |host|
        label = domain_label(host)
        next if %w[linktr patreon youtube linkedin amzn spotify apple].include?(label)

        brand = CANONICAL_BY_DOMAIN[label] || domain_to_brand(host)
        cleaned = clean_brand_name(brand)
        cleaned if cleaned && plausible_product_name?(cleaned)
      end.first
  end

  def episode_time(episode)
    Time.parse(episode["published_at"].to_s)
  rescue ArgumentError, TypeError
    nil
  end

  def build_mention(episode, podcast_doc, product, code, offer)
    {
      product: product,
      product_key: canonical_product_key(product),
      code: code,
      offer: offer,
      podcast_title: podcast_doc.data["title"].to_s.strip,
      podcast_page_url: podcast_doc.url.to_s,
      podcast_slug: podcast_doc.data["slug"].to_s.strip,
      episode_title: episode["episode_title"].to_s.strip,
      episode_page_url: episode["episode_page_url"].to_s.strip,
      published_at: episode["published_at"].to_s.strip,
      published_time: episode_time(episode)
    }
  end

  def extract_from_episode(episode, podcast_doc)
    html = episode["description_html"].to_s
    plain =
      if episode["description_plain"].to_s.strip != ""
        sanitize_show_notes(episode["description_plain"].to_s)
      else
        sanitize_show_notes(LatestPodcastEpisodes.description_plain_from_html(html))
      end

    return [] if plain.strip.empty?

    mentions = []
    heading_blocks = extract_heading_sponsor_blocks(html) + extract_list_sponsor_blocks(html)
    codes_in_blocks = heading_blocks.flat_map do |block|
      extract_codes("#{block[:plain]} #{block[:html]}")
    end.map { |code| code.to_s.upcase }.uniq

    heading_blocks.each do |block|
      codes = extract_codes("#{block[:plain]} #{block[:html]}")
      domains = extract_domains("#{block[:plain]} #{block[:html]}")

      codes.each do |code|
        product = canonical_product(block[:brand], domains, context: block[:plain])
        next unless product

        mentions << build_mention(
          episode,
          podcast_doc,
          product,
          code,
          extract_offer(block[:plain])
        )
      end
    end

    codes = extract_codes("#{plain} #{html}")

    codes.each do |code|
      next if codes_in_blocks.include?(code.to_s.upcase)

      brand_context, offer_context, index = context_for_code(plain, html, code)
      primary_domains = extract_domains(brand_context)
      domains = primary_domains.any? ? primary_domains : extract_domains(context_around(plain, index))
      raw_brand = infer_brand(html_near_code(html, code), plain, code, brand_context).to_s
      product = canonical_product(raw_brand, domains, context: offer_context)
      next unless product

      mentions << build_mention(
        episode,
        podcast_doc,
        product,
        code,
        extract_offer(offer_context)
      )
    end

    mentions
  end

  def merge_podcast(existing, mention)
    slug = mention[:podcast_slug]
    return existing if slug.empty?

    podcasts = Array(existing)
    idx = podcasts.index { |row| row["podcast_slug"] == slug }

    row = {
      "podcast_title" => mention[:podcast_title],
      "podcast_page_url" => mention[:podcast_page_url],
      "podcast_slug" => slug,
      "episode_count" => 1,
      "latest_episode_title" => mention[:episode_title],
      "latest_episode_page_url" => mention[:episode_page_url],
      "latest_published_at" => mention[:published_at]
    }

    if idx
      current = podcasts[idx]
      current["episode_count"] = current["episode_count"].to_i + 1
      current_time = begin
        Time.parse(current["latest_published_at"].to_s)
      rescue ArgumentError, TypeError
        nil
      end
      if mention[:published_time] && (!current_time || mention[:published_time] > current_time)
        current["latest_episode_title"] = mention[:episode_title]
        current["latest_episode_page_url"] = mention[:episode_page_url]
        current["latest_published_at"] = mention[:published_at]
      end
    else
      podcasts << row
    end

    podcasts
  end

  def aggregate_mentions(mentions)
    products = {}

    mentions.each do |mention|
      key = mention[:product_key]
      next if key.empty?

      products[key] ||= {
        "brand" => mention[:product],
        "brand_key" => key,
        "codes" => {},
        "podcasts" => []
      }

      code_key = mention[:code].upcase
      products[key]["codes"][code_key] ||= {
        "code" => mention[:code],
        "offer" => mention[:offer],
        "podcasts" => []
      }

      if mention[:offer] && products[key]["codes"][code_key]["offer"].to_s.strip.empty?
        products[key]["codes"][code_key]["offer"] = mention[:offer]
      end

      products[key]["codes"][code_key]["podcasts"] =
        merge_podcast(products[key]["codes"][code_key]["podcasts"], mention)
      products[key]["podcasts"] = merge_podcast(products[key]["podcasts"], mention)
    end

    products.values.map do |product|
      codes = product["codes"].values.sort_by { |row| row["code"].to_s.upcase }
      codes.each do |code_row|
        code_row["podcasts"] = code_row["podcasts"].sort_by { |row| row["podcast_title"].to_s.downcase }
        code_row["podcast_count"] = code_row["podcasts"].size
      end

      product.delete("codes")
      product["codes"] = codes
      product["podcasts"] = product["podcasts"].sort_by { |row| row["podcast_title"].to_s.downcase }
      product["podcast_count"] = product["podcasts"].size
      product
    end.sort_by { |product| product["brand"].to_s.downcase }
  end

  def build_entries(products)
    entries = []

    Array(products).each do |product|
      Array(product["codes"]).each do |code_row|
        entries << {
          "brand" => product["brand"],
          "brand_key" => product["brand_key"],
          "code" => code_row["code"],
          "offer" => code_row["offer"],
          "podcasts" => code_row["podcasts"],
          "podcast_count" => code_row["podcast_count"]
        }
      end
    end

    entries.sort_by do |entry|
      [entry["brand"].to_s.downcase, entry["code"].to_s.upcase]
    end
  end

  def build_from_site(site)
    feed_data = site.data["latest_podcast_episodes"]
    return empty_payload unless feed_data.is_a?(Hash)

    episodes_by_feed = feed_data["episodes_by_feed"]
    return empty_payload unless episodes_by_feed.is_a?(Hash)

    posts = site.posts.respond_to?(:docs) ? site.posts.docs : []
    feed_to_podcast = {}

    posts.each do |doc|
      next unless doc.data["category"] == "podcast"
      next unless running_podcast?(doc)

      feed_url = doc.data["rss_feed"].to_s.strip
      next if feed_url.empty?

      feed_to_podcast[LatestPodcastEpisodes.normalize_feed_key(feed_url)] = doc
    end

    mentions = []

    episodes_by_feed.each do |feed_key, episodes|
      podcast_doc = feed_to_podcast[feed_key]
      next unless podcast_doc

      Array(episodes).each do |episode|
        next unless episode.is_a?(Hash)

        mentions.concat(extract_from_episode(episode, podcast_doc))
      end
    end

    brands = aggregate_mentions(mentions)
    entries = build_entries(brands)
    {
      "generated_at" => Time.now.utc.iso8601,
      "brands" => brands,
      "entries" => entries,
      "stats" => {
        "brand_count" => brands.size,
        "code_count" => entries.size,
        "mention_count" => mentions.size
      }
    }
  end

  def empty_payload
    {
      "generated_at" => Time.now.utc.iso8601,
      "brands" => [],
      "entries" => [],
      "stats" => { "brand_count" => 0, "code_count" => 0, "mention_count" => 0 }
    }
  end

  def write_committed_data(site, payload)
    path = site.in_source_dir("_data", "promo_codes.yml")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, LatestPodcastEpisodes.dump_yaml(payload))
  rescue StandardError => e
    Jekyll.logger.warn "PromoCodes:", "Could not write #{path}: #{e.message}"
  end
end

class PromoCodesGenerator < Jekyll::Generator
  safe true
  priority :low

  def generate(site)
    payload = PromoCodes.build_from_site(site)
    site.data["promo_codes"] = payload
    PromoCodes.write_committed_data(site, payload)

    stats = payload["stats"] || {}
    Jekyll.logger.info(
      "PromoCodes:",
      "Indexed #{stats['code_count']} code(s) across #{stats['brand_count']} brand(s) from running shows."
    )
  rescue StandardError => e
    Jekyll.logger.warn "PromoCodes:", "#{e.class}: #{e.message}"
  end
end
