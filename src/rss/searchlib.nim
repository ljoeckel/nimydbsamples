import std/[enumerate, strformat, algorithm, hashes, sets, tables]
import std/[options, strutils, typetraits, times]
import yottadb
import stemmer
import types
import sugar
import common


const TIME_FORMATS* = [
    "yyyy-MM-dd'T'HH:mm:sszzz",
    "ddd, d MMM yyyy HH:mm:ss ZZZ",
    "ddd, d MMM yyyy HH:mm:ss 'GMT'",
    "ddd, d MMM yyyy HH:mm:ss 'UTC'",
    "ddd, d MMM yyyy HH:mm:ss 'EDT'",
    "d MMM yyyy HH:mm:ss ZZZ",
    "ddd, dd MMM yyyy HH:mm 'GMT'" # Thu, 09 Apr 2026 12:57 GMT
  ]


proc pubDate(item: RSSItem): string =
    try: 
        let dt = getOption(item.pubDate)
        let fu = parseInt(dt).fromUnix()
        result = fu.format("dd.MM.yyyy HH:mm")
    except:
         result = "01.01.1970 00:00"


proc getUnixTimestamp*(dts: string): string =
  if dts.len > 0:
    for f in TIME_FORMATS:
        try:
            let dt = parse(dts, f)
            return $dt.toTime().toUnix()
        except:
            continue
  
    raise newException(YdbError, "No matching timeformat found to create timestamp for '" & $dts)


proc getRSSFeedConfiguration*(path: string): Table[string, seq[string]] =
    # Get the RSS feeds from feeds.rss
    # [Section] content content [Section2] content content
    var currentSection = ""
    result[currentSection] = @[]

    for line in lines(path):
        let trimmed = line.strip()
        if trimmed == "" or trimmed.startsWith("#"): continue
  
        if trimmed.startsWith("[") and trimmed.endsWith("]"):
            currentSection = trimmed[1 .. ^2]
            result[currentSection] = @[]
        else:
            result[currentSection].add(trimmed)


proc normalizeChannelTitle*(title: string): string =
    # result = result.multiReplace(
    #     ("RSS CHANNEL", ""), 
    #     ("AKTUELLE", ""), ("WWW", ""), ("ONLINE", ""),
    #     ("TICKER", ""), ("SCHLAGZEILEN", ""), ("NEUIGKEITEN", ""), ("NEWS", ""),
    #     ("DIE", ""), ("DER", ""), ("IM", ""), ("VON",""), ("UND",""), ("AUS",""),
    #     ("  "," "), ("-", ""), (",", ""),
    #     ("SECTION", ""),
    # )
    result = title
    let idx = result.toUpper().find(" VOM ")
    if idx > 0:
        result = result[0..idx-1] # Edgecase "Deutschlandfunk Nachrichten vom 01.01.2026"

    while find(result,"  ") > 0:
        result = result.replace("  "," ")
    while result.len > 60:
        let pos = result.rfind(" ")
        if pos > 0:
            result = result[0..pos-1]
    return result.strip


proc normalizeUrl*(url: string): string =
    result = url.multiReplace(
        ("https://", ""), ("rss", ""), ("www", ""),
        ("/", ""), (".", ""), ("-", ""), ("!", ""),
        (";", ""), ("_", "")
    )

proc getWordCountFromFTI(word: string, subscript: seq[string]): int =
    let s0 = subscript[0]
    let s1 = subscript[1]
    result = Get ^RSSItemFTI(word, s0, s1).int
    #TODO: Allow 1. Get ^RSSItemFTI(word, subscript)
    #TODO: Allow 2. Get ^RSSItemFTI(word, subscript[0], subscript[1])


# ========= Overwrites for HashTable[TimeSearchEntry] ========

# Nur 'subscript' für den Vergleich nutzen
proc `==`*(a, b: TimeSearchEntry): bool =
  a.subscript == b.subscript

# Nur 'subscript' für den Hash nutzen
proc hash*(x: TimeSearchEntry): Hash =
  var h: Hash = 0
  h = h !& hash(x.subscript)
  result = !$h


template append(result: var HashSet[TimeSearchEntry], keyword: string, wc: int, item: TimeSearchEntry) =
    var itm = item
    inc(itm.wordCount, getWordCountFromFTI(keyword, item.subscript) + wc)
    incl(result, itm)


proc intersect(keyword: string, s1: var HashSet[TimeSearchEntry], s2: var HashSet[TimeSearchEntry]): HashSet[TimeSearchEntry] =
    #var itm: TimeSearchEntry
    if s1.len == 0:
        for item in s2:
            let wc = s2[item].wordCount
            result.append(keyword, wc, item)
    elif s2.len == 0:
        for item in s1: 
            let wc = s1[item].wordCount
            result.append(keyword, wc, item)
    elif s1.len < s2.len:
        for item in s1:
            if item in s2: 
                let wc = s2[item].wordCount
                result.append(keyword, wc, item)
    else:
        for item in s2:
            if item in s1: 
                let wc = s1[item].wordCount
                result.append(keyword, wc, item)


proc sortFTIResult*(data: var seq[TimeSearchEntry], sortBy: SortBy) =
    case sortBy
    of ByTodayAscending, ByTimeAscending:
        data.sort((x, y) => cmp(x.time, y.time))
    of ByTodayDescending, ByTimeDescending:
        data.sort((x, y) => cmp(y.time, x.time))
    of ByRelevanceAscending:
        data.sort do (x, y: TimeSearchEntry) -> int:
            var res: int
            res = cmp(x.wordCount, y.wordCount) # sort by wordCount
            if res == 0:
                res = cmp(x.time, y.time) # by 'time' if 'wordCont' is 0 (equal)
            return res
    of ByRelevanceDescending:
        data.sort do (x, y: TimeSearchEntry) -> int:
            var res: int
            res = cmp(y.wordCount, x.wordCount) # sort by wordCount
            if res == 0:
                res = cmp(y.time, x.time) # by 'time' if 'wordCont' is 0 (equal)
            return res


proc getFTI*(keyword: string, lang: string, userid: string, sortBy: SortBy): seq[TimeSearchEntry] =
    # Search Full Text Index
    if keyword.isEmptyOrWhitespace or keyword.len < MIN_KEYWORD_LEN: 
        return # check minimum length of keywords

    # Get enabled feeds
    let feedtable = getEnabledFeeds(userid)

    # resultTable holds for each search word a sequence of TimeSearchEntry
    var resultTable = initTable[string, seq[TimeSearchEntry]]()
    # Find entries for each search word
    for kw in split(toLower(trim(keyword))," "):
        var items: seq[TimeSearchEntry]
        let stemword = stem(kw, lang)
        for keys in QueryItr ^RSSItemFTI(stemword).keys:
            if not keys[0].startsWith(stemword): break
            # check if item is in active feed
            let feedId = Order ^RSSItemIDXREF(keys[1] & "," & keys[2] ,"")
            if feedId in feedtable:
                items.add(TimeSearchEntry(subscript: @[keys[1], keys[2] ]))
        # save found items under stemword
        resultTable[stemword] = items

    # Find TimeSearchEntry's which are in all resultTables
    var common: HashSet[TimeSearchEntry]
    for key in resultTable.keys:
        var s2 = resultTable[key].toHashSet
        common = intersect(key, common, s2)

    # Update TimeSearchEntry with pubDate
    # get current day from/to
    let (todayFrom, todayTo) = currentDayFromTo()

    for entry in common:
        var sr = entry
        let subscript = entry.subscript
        sr.time = Get ^RSSItem(subscript, "pubDate").int # get time from DB
        case sortBy
        of ByTodayAscending, ByTodayDescending:
            if sr.time >= todayFrom and sr.time <= todayTo:
                result.add(sr)
        else:
            result.add(sr)


proc getLatestRSSItems*(max: int, userid: string, sortBy: SortBy): seq[RSSItem] =
    var feedtable = getEnabledFeeds(userid)
   
    # get current day from/to
    let (todayFrom, todayTo) = currentDayFromTo()
    # Iterate from new to old
    for key  in QueryItr ^RSSItemPUBDATE.reverse.keys:  # youngest first
        let pubDate = fastParseInt(key[0])
        let idxKey = key[1]
        let feedId = Order ^RSSItemIDXREF(idxkey,"")
        if feedId in feedtable:
            let itemKey = idxKey.split(",")
            let rssItem = loadObject[RSSItem](itemKey)
            case sortBy:
            of ByTodayAscending, ByTodayDescending:
                if pubDate >= todayFrom and pubDate <= todayTo:
                    result.add(rssItem)
                if pubDate < todayFrom:
                    break
            else:
                result.add(rssItem)

        if result.len >= max:
            break


proc getLatestRSSItemKeys*(max: int): seq[seq[string]] =
    var cnt = max
    for key  in QueryItr ^RSSItemPUBDATE.reverse:
        let keys = key.split(',')
        result.add(keys)
        dec cnt
        if cnt == 0: break


proc feedData(item: RSSItem): (string, string) =
    let id = item.idxref.split(',')[0]
    let rssImage = loadObject[RSSImage](id)

    var feedTitle, feedLink: string
    if rssImage.url.isSome():
        feedTitle = if rssImage.title.isSome: getOption(rssImage.title) else: getOption(item.title)
        feedLink = getOption(rssImage.link)
    else:
        feedTitle = Get ^RSS(id, "title")
        feedLink = Get ^RSS(id, "link")
    
    return (feedTitle, feedLink)


proc createRSSItemCard*(item: RSSItem): string =
    let title = getOption(item.title)
    let description = getOption(item.description)
    let link = getOption(item.link)

    # categories
    var category: string
    if item.category.len > 0:
        var cat: string
        for idx, word in enumerate(item.category):
            cat.add(word & " ")
            if idx >= 2: break
        category = fmt"""<span class="tag">{cat}</span>"""
    
    var topic = getOption(item.topic)
    if topic.len > 0: topic = fmt"""<span class="tag">{toUpper(topic)}</span>"""
    
    var keywords: string
    if item.keywords.len > 0:
        var keywordlist: string
        for idx, word in enumerate(item.keywords):
            keywordlist.add(word & " ")
            if idx >= 2: break # show only first 3 keywords
        keywords = fmt"""<span class="tag">{keywordlist}</span>"""

    let (feedTitle, feedLink) = feedData(item)
    let divimg = fmt"""
        <a target='_blank' href={feedLink} class='footer-link'>
        <span class='feed-title'>{feedTitle}</span></a>
        """
    
    let idxref = fmt"""
        <button data-on:click__stop="$id='{item.idxref}'; @get('/show-rssitem')"
        popovertarget="rss-detail">
            &nbsp;&nbsp;
            <i class="bi bi-info-square"></i>
        </button>"""

    result = fmt"""
        <div class='rsscard'>
            <div class='rsscard-tags'>
                {topic}
                {category}
                {keywords}
            </div>
            <div class='rsscard-title'> <a target='_blank' href='{link}'> {title}</a> </div>
            <p class='rsscard-text'> <a target='_blank' href='{link}'> {description}</a> </p>
            <div class='rsscard-footer'>
                <p>{divimg}</p>
                <p class='rsspubdate'> {pubDate(item)}  {idxref}</p>
            </div>
        </div>
        """


proc createRSSItemList*(item: RSSItem): string =
    let title = getOption(item.title)
    let link = getOption(item.link)
    let (feedTitle, feedLink) = feedData(item)
    let divimg = fmt"<a target='_blank' href={feedLink}><span>{feedTitle}</span></a>"

    result = fmt"""
        <div class='rsscard-title'>
            <a target='_blank' href='{link}'> {title}</a>
            <p class='rsspubdate'> {pubDate(item)} / {item.idxref} / {divimg} </p>
        </div>
        """


proc getRSSFields*(subscript: seq[string]): seq[(string, string)] =
    if subscript.len == 0:
        echo fmt">> Subscript {subscript} not valid <<"
        return

    let rss = loadObject[RSS](subscript[0])
    result.add ("RSS - FeedType", $rss.feedType)
    result.add(("id", getOption(rss.id)))
    result.add(("Title", getOption(rss.title)))
    result.add(("Category", rss.category.join(" ")))
    result.add(("Link", getOption(rss.link)))
    result.add(("Description", getOption(rss.description)))
    result.add(("Language", getOption(rss.language)))
    result.add(("Copyright", getOption(rss.copyright)))
    result.add(("Managing Editor", getOption(rss.managingEditor)))
    result.add(("Web Master", getOption(rss.webMaster)))
    result.add(("Publication-date", getOption(rss.pubDate)))
    result.add(("Last build-date", getOption(rss.lastBuildDate)))
    result.add(("Generator", getOption(rss.generator)))
    result.add(("Docs", getOption(rss.docs)))
    result.add(("Rating", getOption(rss.rating)))
    result.add(("TTL", getOption(rss.ttl)))
    result.add(("Skip Days", rss.skipDays.join(" ")))
    result.add(("Skip Hours", rss.skipHours.join(" ")))
    result.add(("RSSImage - url", getOption(rss.image.url)))
    result.add((" title", getOption(rss.image.title)))
    result.add((" link", getOption(rss.image.link)))
    result.add(("width", getOption(rss.image.width)))
    result.add(("height", getOption(rss.image.height)))
    result.add(("description", getOption(rss.image.description)))
    result.add(("RSSCloud - domain", getOption(rss.cloud.domain)))
    result.add((" port", getOption(rss.cloud.port)))
    result.add((" path", getOption(rss.cloud.path)))
    result.add((" registerProcedure", getOption(rss.cloud.registerProcedure)))
    result.add((" protocol", getOption(rss.cloud.protocol)))

    # Get RSSItem fields
    let rssItem = loadObject[RSSItem](subscript)
    if rssItem.idxref.len > 0:
        result.add(("RSSItem - Title", getOption(rssItem.title)))
        result.add(("Description", getOption(rssItem.description)))
        result.add(("idxref", rssItem.idxref))
        result.add(("Author - name", getOption(rssItem.author.name)))
        result.add(("email", getOption(rssItem.author.email)))
        result.add(("uri", getOption(rssItem.author.uri)))
        result.add(("link", getOption(rssItem.link)))
        result.add(("content", getOption(rssItem.content)))
        result.add(("category", rssItem.category.join(" ")))
        result.add(("comments", getOption(rssItem.comments)))
        result.add(("Enclosure - Url", rssItem.enclosure.url))
        result.add((" Length", rssItem.enclosure.length))
        result.add((" Type", rssItem.enclosure.enclosureType))
        result.add(("guid", getOption(rssItem.guid)))
        result.add(("pubDate", getOption(rssItem.pubDate)))
        result.add(("sourceUrl", getOption(rssItem.sourceUrl)))
        result.add(("sourceText", getOption(rssItem.sourceText)))
        result.add(("updated", getOption(rssItem.updated)))
        result.add(("topic", getOption(rssItem.topic)))
        result.add(("keywords", rssItem.keywords.join(" ")))
