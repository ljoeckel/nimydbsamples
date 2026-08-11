import std/[enumerate, strformat, algorithm, hashes, sets, tables]
import std/[options, strutils, typetraits, times]
import yottadb
import stemmer
import types
import sugar
import common


const TIME_FORMATS* = [
    "yyyy-MM-dd'T'HH:mm:sszzz",
    "yyyy-MM-dd'T'HH:mm:ss.fff'Z'", #'2026-06-01T03:50:57.000Z
    "ddd, d MMM yyyy HH:mm:ss ZZZ",
    "ddd, d MMM yyyy HH:mm:ss 'GMT'",
    "ddd, d MMM yyyy HH:mm:ss 'UTC'",
    "ddd, d MMM yyyy HH:mm:ss 'EDT'",
    "d MMM yyyy HH:mm:ss ZZZ",
    "ddd, dd MMM yyyy HH:mm 'GMT'" # Thu, 09 Apr 2026 12:57 GMT
  ]


proc pubDate(item: RSSItem, format: string = "dd.MM.yyyy HH:mm"): string =
    try: 
        let dt = getOption(item.pubDate)
        let fu = parseInt(dt).fromUnix()
        result = fu.format(format)
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
  
    raise newException(YdbError, "No matching timeformat found to create timestamp for '" & $dts & "'")


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


# ========= Overwrites for HashTable[TimeSearchEntry] ========

# Nur 'subscript' für den Vergleich nutzen
proc `==`*(a, b: TimeSearchEntry): bool =
  a.subscript == b.subscript

# Nur 'subscript' für den Hash nutzen
proc hash*(x: TimeSearchEntry): Hash =
  var h: Hash = 0
  h = h !& hash(x.subscript)
  result = !$h

proc intersect(keyword: string, s1: var HashSet[TimeSearchEntry], s2: var HashSet[TimeSearchEntry]): HashSet[TimeSearchEntry] =
    if s1.len == 0:
        result.incl(s2)
    elif s2.len == 0:
        result.incl(s1)
    elif s1.len < s2.len:
        for item in s1:
            if item in s2: 
                result.incl(item)
    else:
        for item in s2:
            if item in s1: 
                result.incl(item)


proc sortFTIResult*(data: var seq[TimeSearchEntry], sortBy: SortBy) =
    case sortBy
    of ByTodayAscending, ByTimeAscending:
        data.sort((x, y) => cmp(x.time, y.time))
    of ByTodayDescending, ByTimeDescending:
        data.sort((x, y) => cmp(y.time, x.time))
    of ByRelevanceAscending:
        data.sort do (x, y: TimeSearchEntry) -> int:
            let res = cmp(x.wordCount, y.wordCount) # sort by wordCount
            if res == 0: # wordCount is equal
                return cmp(x.time, y.time) # further sort by 'time'
            else:
                return res
    of ByRelevanceDescending:
        data.sort do (x, y: TimeSearchEntry) -> int:
            let res = cmp(y.wordCount, x.wordCount) # sort by wordCount
            if res == 0:
                return cmp(y.time, x.time) # by 'time' if 'wordCont' is 0 (equal)
            else:
                return res


proc getFTI*(p: SearchParams): seq[TimeSearchEntry] =
    # Search Full Text Index
    if p.keyword.len < MIN_KEYWORD_LEN: return # check minimum length of keywords
    let lastPubDate = p.lastPubdate
    # Get enabled feeds
    let feedtable = getEnabledFeeds(p.userid)

    # resultTable holds for each search word a sequence of TimeSearchEntry
    var resultTable = initTable[string, seq[TimeSearchEntry]]()
    # Find entries for each search word
    for kw in split(toLower(trim(p.keyword))," "):
        var items: seq[TimeSearchEntry]
        let stemword = stem(kw, p.lang)
        for keys in QueryItr ^RSSItemFTI(stemword).keys:
            if not keys[0].startsWith(stemword): break
            let pubDate = parseInt(keys[1])
            if pubDate <= lastPubDate:
                # check if item is in active feed
                let feedId = Order ^RSSItemIDXREF(keys[2] & "," & keys[3] ,"")
                if feedId in feedtable:
                    let wc = Get ^RSSItemFTI(keys).int
                    items.add(TimeSearchEntry(time: pubDate, wordCount: wc, subscript: @[keys[1], keys[2], keys[3]]))
        # save found items under stemword
        resultTable[stemword] = items

    # Find TimeSearchEntry's which are in all resultTables
    var common: HashSet[TimeSearchEntry]
    for key in resultTable.keys:
        var s2 = resultTable[key].toHashSet
        common = intersect(key, common, s2)

    # Update TimeSearchEntry with pubDate
    let (todayFrom, todayTo) = dayFromTo()

    for entry in common:
        case p.sortBy
        of ByTodayAscending, ByTodayDescending:
            if entry.time >= todayFrom and entry.time <= todayTo:
                result.add(entry)
        else:
            result.add(entry)


iterator getLatestRSSItems*(timeFrom: int, idxref: string, userid: string, sortBy: SortBy): RSSItem =
    var feedtable = getEnabledFeeds(userid)
    if feedtable.len == 0:
        var empty: RSSItem
        yield empty

    let gbl = if idxref.isEmptyOrWhitespace: fmt"^RSSItemPUBDATE({timeFrom})" else: fmt"""^RSSItemPUBDATE({timeFrom}, "{idxref}")"""
    # Iterate from new to old
    for key  in QueryItr @gbl.reverse.keys:  # youngest first
        let idxKey = key[1]
        let feedId = Order ^RSSItemIDXREF(idxkey,"")
        if feedId in feedtable:
            let itemKey = idxKey.split(",")
            yield loadObject[RSSItem](itemKey)


proc getLatestRSSItemKeys*(max: int): seq[seq[string]] =
    var cnt = max
    for keys  in QueryItr ^RSSItemPUBDATE.keys.reverse:
        result.add(keys[1].split(','))
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

    var tags = ""

    if item.category.len > 0:
        var pos = 0
        for idx, word in enumerate(item.category):
            tags.add(&"<span class='tag is-primary is-light'>{word}</span>")
            if idx > 1:
                let remaining = item.category[idx+1..^1].join(" ")
                tags.add(&"<span title='{remaining}' class='tag is-primary is-light'>...</span>")
                break

    
    var topic = toUpper(getOption(item.topic))
    if topic.len > 0:
        var pos = 0
        for idx, word in enumerate(topic.split(",")):
            tags.add(&"<span class='tag is-warning is-light'>{word}</span>")
            inc(pos, word.len + 1)
            if idx > 1 and pos < topic.len:
                tags.add(&"<span title='{topic[pos..^1]}' class='tag is-warning is-light'>...</span>")
                break

    if item.keywords.len > 0:
        for words in item.keywords:
            var pos = 0
            for idx, word in enumerate(words.split(",")):
                tags.add(&"<span class='tag is-info is-light'>{word}</span>")
                inc(pos, word.len + 1)
                if idx > 1 and pos < words.len:
                    tags.add(&"<span title='{words[pos..^1]}' class='tag is-info is-light'>...</span>")
                    break

    var (feedTitle, feedLink) = feedData(item)
    feedTitle = feedTitle.replace("RSS Feed von ", "")  # TODO: im preprocessing
    if feedTitle.len > 24: feedTitle = feedTitle[0..24] & ".."

    let idxref = fmt"""
        <button data-on:click__stop="$id='{item.idxref}'; @post('/show-rssitem')"
        popovertarget="rss-detail">
            &nbsp;&nbsp;
            <i class="has-text-link bi bi-info-square"></i>
        </button>"""

# style="display: inline-block; line-height: 1.125;"
    let htmltags = if tags.len > 0: fmt"<div class='tags has-addons mt-0 mb-0'>{tags}</div>" else: ""
    result = fmt"""
        <div class='box cell is-flex is-flex-direction-column'>
            {htmltags}

            <a target='_blank' href='{link}'><h6 class='subtitle is-5'>{title}</h6></a>
            
            <span class="is-size-6a mt-3">{description}</span>

            <div class="columns is-gapless mt-auto" style="width: 100%;">
                <div class="column is-four-fifths">
                    <a class='subtitle is-7 has-text-info mt-auto' target='_blank' href={feedLink}>
                        {feedTitle}  {pubDate(item, "dd.MM HH:mm")}
                    </a>
                </div>
                <div class="column has-text-right">
                    {idxref}
                </div>
            </div>
        </div>
        """


proc createRSSItemList*(item: RSSItem): string =
    let title = getOption(item.title)
    let link = getOption(item.link)
    let (feedTitle, feedLink) = feedData(item)
    result = fmt"""
        <a target='_blank' href='{link}'><h6 class='subtitle is-6'>{title}</h6></a>
        <span class='subtitle is-7 has-text-info'> {pubDate(item)} / {item.idxref} / {feedTitle}</span>
        """

proc getRSSFields*(subscript: seq[string]): seq[(string, string)] =
    if subscript.len == 0:
        echo fmt">> Subscript {subscript} not valid <<"
        return
    
    let rss = loadObject[RSS](subscript[0])
    result.add(("RSS - FeedType", $rss.feedType))
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