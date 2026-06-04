import std/[times, strutils, strformat]
import std/[typetraits]
import mummy, mummy/routers, mummy/datastar
import nimrss

proc getSortBy*(sort: string, direction: string): SortBy =
    if sort == "today":
        result = if direction == "up": ByTodayAscending else: ByTodayDescending
    elif sort == "time":
        result = if direction == "up": ByTimeAscending else: ByTimeDescending
    elif sort == "relevance":
        result = if direction == "up": ByRelevanceAscending else: ByRelevanceDescending


iterator getLatestRSSItem*(userid: string, sortBy: SortBy): RSSItem =
    var feedtable = getEnabledFeeds(userid)
  
    # get current day from/to
    let (todayFrom, todayTo) = currentDayFromTo()
    # Iterate from new to old
    for key  in QueryItr ^RSSItemPUBDATE.reverse.keys:  # youngest first
        let pubDate = fastParseInt(key[0])
        if pubDate > todayTo: continue # ignore items in the future

        let idxKey = key[1]
        let feedId = Order ^RSSItemIDXREF(idxkey,"")
        if feedId in feedtable:
            let itemKey = idxKey.split(",")
            let rssItem = loadObject[RSSItem](itemKey)
            case sortBy:
            of ByTodayAscending, ByTodayDescending:
                if pubDate >= todayFrom:
                    yield rssItem
                if pubDate < todayFrom:
                    break
            else:
                yield rssItem


proc getHTMLForRSSItem(format: string, rssItem: RSSItem): string =
        if format == "card":
            createRSSItemCard(rssItem)
        else:
            createRSSItemList(rssItem)


proc handleSearch(req: Request) =
    let userid = getSignal(req, USERID)
    let keyword = strip(getSignal(req, "keyword"))
    var lang = getSignal(req, "lang")
    if lang.len == 0: lang = "DE"

    let sort = getSignal(req, "sort")
    let direction = getSignal(req, "direction")
    let maxArticles = parseInt(getSignal(req, "articles"))
    var articleCount = 0 
    let format = getSignal(req, "format")
    var cards: string
    var containerClass = if format == "card": "rsscard-container" else: "rsslist-container"
    var rssItems: seq[RSSItem]
    let sortBy = getSortBy(sort, direction)

    var sse = req.respondSSE()
    let rssContainer = fmt"""<div id="rsscards" class="{containerClass}"></div>"""
    patchElements(sse, rssContainer)

    let queryTime = meassure:
        if keyword.len == 0:
            for rssItem in getLatestRSSItem(userid, sortBy):
                let card = getHTMLForRSSItem(format, rssItem)
                patchElements(sse, card, selector="#rsscards", mode=Append)
                inc articleCount
                if articleCount >= maxArticles: break
        else:
            var searchResults = getFTI(keyword, lang, userid, sortBy) # @["1158,4", "118,10"...]
            searchResults.sortFTIResult(sortBy)
            # Reduce result to max_search_results
            let mx: int = min(searchResults.len, maxArticles)
            for idx in 0..mx-1:
                let rssItem = loadObject[RSSItem](searchResults[idx].subscript)
                let card = getHTMLForRSSItem(format, rssItem)
                patchElements(sse, card, selector="#rsscards", mode=Append)
                inc articleCount
                if articleCount >= maxArticles: break

    patchElements(sse, fmt"""<h3 id="info">{articleCount} Articles in {queryTime}</h3>""")
    sse.close()


# Callback for router registration
proc register*(router: var Router) =
    router.post("/search", handleSearch)

# Create module instance
let wmSearchModule* = WebModule(
    name: "wmSearch",
    register: register
)