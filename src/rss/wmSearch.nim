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


proc getHTMLForRSSItem(format: string, rssItem: RSSItem): string =
        if format == "card":
            createRSSItemCard(rssItem)
        else:
            createRSSItemList(rssItem)


proc handleSearch*(sse: SSEConnection, toTS: int = 0) =
    let incremental = if toTS != 0: true else: false
    let userid = getUserId(sse)
    let keyword = strip(getSignal(userid, "keyword"))
    var lang = getSignal(userid, "lang")
    if lang.len == 0: lang = "DE"
    let sort = getSignal(userid, "sort")
    let direction = getSignal(userid, "direction")
    let sortBy = getSortBy(sort, direction)
    let maxArticles = parseInt(getSignal(userid, "articles"))
    let format = getSignal(userid, "format")
    
    var articleCount = 0
    var containerClass = if format == "card": "rsscard-container" else: "rsslist-container"
    let rssContainer = fmt"""<div id="rsscards" class="{containerClass}"></div>"""
    if not incremental:
        patchElements(sse, rssContainer)

    let (todayFrom, todayTo) = currentDayFromTo()
    var timeFrom = if sortBy == ByTodayAscending or sortBy == ByTodayDescending: todayFrom else: toTS
    var timeTo = todayTo

    let queryTime = meassure:
        if keyword.len == 0:
            for rssItem in getLatestRSSItems(timeFrom, timeTo, userid, sortBy):
                let card = getHTMLForRSSItem(format, rssItem)
                inc articleCount
                if articleCount >= maxArticles: break
                let pubDate = parseInt(getOption(rssItem.pubDate))
                if incremental and pubDate <= toTS: break
                if incremental:
                    patchElements(sse, card, selector="#rsscards", mode=Prepend)
                else:
                    patchElements(sse, card, selector="#rsscards", mode=Append)
        else:
            var searchResults = getFTI(keyword, lang, userid, sortBy) # @["1158,4", "118,10"...]
            searchResults.sortFTIResult(sortBy)
            # Reduce result to max_search_results
            let mx: int = min(searchResults.len, maxArticles)
            for idx in 0..mx-1:
                let rssItem = loadObject[RSSItem](searchResults[idx].subscript)
                let card = getHTMLForRSSItem(format, rssItem)
                try:
                    patchElements(sse, card, selector="#rsscards", mode=Append)
                except:
                    echo "ERROR wmsearch 100:patchelements: ", getCurrentExceptionMsg()
                inc articleCount
                if articleCount >= maxArticles: break

    patchElements(sse, fmt"""<h3 id="info">{articleCount} Articles in {queryTime}</h3>""")


proc handleUpdateSearch*(sse: SSEConnection, toTS: int) =
    let userid = getUserId(sse)
    let keyword = strip(getSignal(userid, "keyword"))
    var lang = getSignal(userid, "lang")
    if lang.len == 0: lang = "DE"
    let sort = getSignal(userid, "sort")
    let direction = getSignal(userid, "direction")
    let sortBy = getSortBy(sort, direction)
    let format = getSignal(userid, "format")
    let maxArticles = parseInt(getSignal(userid, "articles"))    

    var articleCount = 0

    let (todayFrom, todayTo) = currentDayFromTo()
    var timeFrom = if sortBy == ByTodayAscending or sortBy == ByTodayDescending: todayFrom else: toTS
    var timeTo = todayTo

    let queryTime = meassure:
        if keyword.len == 0:
            var cards: seq[string]
            for rssItem in getLatestRSSItems(timeFrom, timeTo, userid, sortBy):
                let card = getHTMLForRSSItem(format, rssItem)
                inc articleCount
                let pubDate = parseInt(getOption(rssItem.pubDate))
                if pubDate <= toTS: break
                cards.add(card)
                
            # Insert from old to young
            for idx in countdown(cards.len-1, 0):
                patchElements(sse, cards[idx], selector="#rsscards", mode=Prepend)
        else:
            var searchResults = getFTI(keyword, lang, userid, sortBy) # @["1158,4", "118,10"...]
            searchResults.sortFTIResult(sortBy)
            # Reduce result to max_search_results
            let mx: int = min(searchResults.len, maxArticles)
            for idx in 0..mx-1:
                let rssItem = loadObject[RSSItem](searchResults[idx].subscript)
                let card = getHTMLForRSSItem(format, rssItem)
                try:
                    patchElements(sse, card, selector="#rsscards", mode=Append)
                except:
                    echo "ERROR wmsearch 100:patchelements: ", getCurrentExceptionMsg()
                inc articleCount
                if articleCount >= maxArticles: break

    patchElements(sse, fmt"""<h3 id="info">{articleCount} Articles in {queryTime}</h3>""")


proc handleSearch*(req: Request) =
    var sse = req.respondSSE()
    handleSearch(sse)
    sse.close()


# Callback for router registration
proc register*(router: var Router) =
    router.post("/search", handleSearch)

# Create module instance
let wmSearchModule* = WebModule(
    name: "wmSearch",
    register: register
)