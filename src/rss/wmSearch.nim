import std/[times, strutils, strformat, json]
import std/[typetraits]
import mummy, mummy/routers, mummy/datastar
import nimrss


proc getSearchParams*(sse: SSEConnection): SearchParams =
    var p = SearchParams()
    let ctx = getContext(sse)
    p.userid = ctx.userid
    p.keyword = strip(ctx.getStr("keyword"))

    p.lang = ctx.getStr("lang")
    if p.lang.len == 0: p.lang = "DE"

    p.sort = ctx.getStr("sort")
    p.direction = ctx.getStr("direction")
    if p.sort == "today":
        p.sortBy = if p.direction == "up": ByTodayAscending else: ByTodayDescending
    elif p.sort == "time":
        p.sortBy = if p.direction == "up": ByTimeAscending else: ByTimeDescending
    elif p.sort == "relevance":
        p.sortBy = if p.direction == "up": ByRelevanceAscending else: ByRelevanceDescending

    p.lastIdxRef = ctx.getStr("lastIdxRef")
    p.maxArticles = ctx.getInt("articles")
    p.format = ctx.getStr("format")
    (p.todayFrom, p.todayTo) = currentDayFromTo()

    return p


proc getHTMLForRSSItem(format: string, rssItem: RSSItem): string =
        if format == "card":
            createRSSItemCard(rssItem)
        else:
            createRSSItemList(rssItem)


proc handleSearch*(sse: SSEConnection, p: SearchParams) =
    var timeFrom = p.lastPubDate
    var lastRSSItem: RSSItem
    var articles = 0

    proc searchByKeyword() =
        var searchResults = getFTI(p) # @["1158,4", "118,10"...]
        searchResults.sortFTIResult(p.sortBy)
        # Reduce result to max_search_results
        let mx: int = min(searchResults.len, p.maxArticles)
        for idx in 0..mx-1:
            let subs = searchResults[idx].subscript
            let rssItem = loadObject[RSSItem](subs[1..^1]) # 0=pubDate, 1=rss, 2=article
            let card = trim(getHTMLForRSSItem(p.format, rssItem))
            patchElements(sse, card, selector="#rsscards", mode=Append)
            lastRSSItem = rssItem
        articles = mx

    proc search() =
        var cards: seq[string]
        for rssItem in getLatestRSSItems(timeFrom, p.lastIdxRef, p.userid, p.sortBy):
            let pubDate = parseInt(getOption(rssItem.pubDate))
            if p.sortBy in {ByTodayAscending, ByTodayDescending} and pubDate < p.todayFrom: break # only Todays articles
            let card = trim(getHTMLForRSSItem(p.format, rssItem))

            if p.searchType == Incremental:
                if pubDate < p.lowerBoundPubdate: break # ignore older articles than from update
                cards.add(card)    
            else:
                patchElements(sse, card, selector="#rsscards", mode=Append)
            
            lastRSSItem = rssItem
            inc articles
            if articles >= p.maxArticles: break

        if p.searchType == Incremental:
            for idx in countdown(cards.len-1, 0):
                patchElements(sse, cards[idx], selector="#rsscards", mode=Prepend)


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
        let intersect = """<div id="intersect" data-on-intersect__threshold.25="@post('/search-more')"></div>"""
        patchElements(sse, intersect, selector="#rsscards", mode=Append)

    # Update info
    let nextRun = Get ^Session("rsscollector", "nextRun").int
    patchElements(sse, fmt"""<h3 id="info" title="Next collector run at '{toDateTime(nextRun)}'">{articles} Articles in {queryTime}</h3>""")
    if lastRssItem.idxref.len > 0:
        patchSignals(sse, %*{
            "userid": p.userid,
            "lastPubDate": parseInt(getOption(lastRssItem.pubDate)),
            "firstPubDate": getFirstPubDate(),
            "lastIdxRef": lastRssItem.idxref,
            "lastRun": datetimetoUnix()
        })



proc handleSearch*(req: Request) =
    SSE(req):
        var p = getSearchParams(sse)
        p.lastPubdate = datetimeToUnix()
        handleSearch(sse, p)


proc handleSearchMore(req: Request) =
    let ctx = getContext(req)
    SSE(req):
        var p = getSearchParams(sse)
        p.searchType = SearchType.Append
        p.lastPubDate = ctx.getInt("lastPubDate")
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