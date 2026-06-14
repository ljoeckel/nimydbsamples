import std/[times, strutils, strformat, json, enumerate]
import std/[typetraits]
import mummy, mummy/routers, mummy/datastar
import nimrss


proc getSearchParams*(sse: SSEConnection): SearchParams =
    var p = SearchParams()
   
    p.userid = getUserId(sse)
    p.keyword = strip(getSignal(p.userid, "keyword"))

    p.lang = getSignal(p.userid, "lang")
    if p.lang.len == 0: p.lang = "DE"

    p.sort = getSignal(p.userid, "sort")
    p.direction = getSignal(p.userid, "direction")
    if p.sort == "today":
        p.sortBy = if p.direction == "up": ByTodayAscending else: ByTodayDescending
    elif p.sort == "time":
        p.sortBy = if p.direction == "up": ByTimeAscending else: ByTimeDescending
    elif p.sort == "relevance":
        p.sortBy = if p.direction == "up": ByRelevanceAscending else: ByRelevanceDescending

    p.lastIdxRef = getSignal(p.userid, "lastIdxRef")

    p.maxArticles = parseInt(getSignal(p.userid, "articles"))
    p.format = getSignal(p.userid, "format")

    (p.todayFrom, p.todayTo) = currentDayFromTo()

    return p


proc getHTMLForRSSItem(format: string, rssItem: RSSItem): string =
        if format == "card":
            createRSSItemCard(rssItem)
        else:
            createRSSItemList(rssItem)


proc handleSearch*(sse: SSEConnection, p: SearchParams) =
    var timeFrom = min(p.todayTo, p.lastPubDate)
    echo "timeFrom=", timeFrom, " ", toDateTime(timeFrom)
    var lastRSSItem: RSSItem
    var articles = 0

    proc searchByKeyword() =
        #let lastPubDate = parseInt(getSignal(p.userid, "lastPubDate"))
        #var searchResults = getFTI(p, lastPubDate) # @["1158,4", "118,10"...]
        var searchResults = getFTI(p) # @["1158,4", "118,10"...]
        searchResults.sortFTIResult(p.sortBy)
        # Reduce result to max_search_results
        let mx: int = min(searchResults.len, p.maxArticles)
        for idx in 0..mx-1:
            let rssItem = loadObject[RSSItem](searchResults[idx].subscript)
            let card = trim(getHTMLForRSSItem(p.format, rssItem))
            patchElements(sse, card, selector="#rsscards", mode=Append)
            lastRSSItem = rssItem
        articles = mx

    proc search() =
        var cards: seq[string]
        for (cnt, rssItem) in enumerate(getLatestRSSItems(timeFrom, p.lastIdxRef, p.userid, p.sortBy)):
            if cnt >= p.maxArticles: break
            let pubDate = parseInt(getOption(rssItem.pubDate))
            #echo cnt, " ", toDateTime(pubDate), " ", rssItem.idxref, " ", getOption(rssItem.title)
            lastRSSItem = rssItem
            if p.sortBy in {ByTodayAscending, ByTodayDescending} and pubDate < p.todayFrom: break
            cards.add(trim(getHTMLForRSSItem(p.format, rssItem)))
            articles = cnt + 1

        if p.searchType == Incremental:
            for idx in countdown(cards.len-1, 0):
                patchElements(sse, cards[idx], selector="#rsscards", mode=Prepend)
        else:
            for idx in 0..cards.len-1:
                patchElements(sse, cards[idx], selector="#rsscards", mode=Append)

    case p.searchType:
    of Basic:
        let containerClass = if p.format == "card": "rsscard-container" else: "rsslist-container"
        let rssContainer = fmt"""<div id="rsscards" class="{containerClass}"></div>"""
        patchElements(sse, rssContainer) # remove old entries on fresh search
    of Append:
        # Remove the intersect element
        patchElements(sse, "", selector="#intersect", mode=Remove)
    of Incremental:
        discard

    let queryTime = meassure:
        if p.keyword.isEmptyOrWhitespace:
            search()
        else:
            searchByKeyword()

    # Intersect element to continue search on scroll at the end
    if articles >= p.maxArticles:
        let intersect = """<div id="intersect" data-on-intersect="@post('/search-more')">/div>"""
        patchElements(sse, intersect, selector="#rsscards", mode=Append)

    # Update info
    patchElements(sse, fmt"""<h3 id="info">{articles} Articles in {queryTime}</h3>""")
    if lastRssItem.idxref.len > 0:
        let lastPubDate = parseInt(getOption(lastRssItem.pubDate))
        let lastIdxref = lastRssItem.idxref
        patchSignals(sse, %*{"lastPubDate": lastPubdate, "lastIdxRef": lastIdxRef})



proc handleSearch*(req: Request) =
    SSE(req):
        var p = getSearchParams(sse)
        p.lastPubdate = datetimeToUnix()
        handleSearch(sse, p)


proc handleSearchMore(req: Request) =
    let userid = getUserId(req)
    let lastPubDate = parseInt(getSignal(userid, "lastPubDate"))
    SSE(req):
        var p = getSearchParams(sse)
        p.searchType = SearchType.Append
        p.lastPubDate = lastPubDate
        handleSearch(sse, p)


# Callback for router registration
proc register*(router: var Router) =
    router.post("/search", handleSearch)
    router.post("/search-more", handleSearchMore)

# Create module instance
let wmSearchModule* = WebModule(
    name: "wmSearch",
    register: register
)