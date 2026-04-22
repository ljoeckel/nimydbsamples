import std/[times, strutils, strformat]
import std/[typetraits]
import mummy, mummy/routers, mummy/datastar
import nimrss
import wmRSSCards

proc handleSearch(req: Request) =
    let userid = getSignal(req, USERID)
    let keyword = strip(getSignal(req, "keyword"))
    var lang = getSignal(req, "lang")
    if lang.len == 0: lang = "DE"

    let sort = getSignal(req, "sort")
    let direction = getSignal(req, "direction")
    let articleCount = parseInt(getSignal(req, "articles"))
    let format = getSignal(req, "format")

    var sortBy: SortBy
    if sort == "today":
        sortBy = if direction == "up": ByTodayAscending else: ByTodayDescending
    elif sort == "time":
        sortBy = if direction == "up": ByTimeAscending else: ByTimeDescending
    elif sort == "relevance":
        sortBy = if direction == "up": ByRelevanceAscending else: ByRelevanceDescending

    var cards, keywords: string
    var containerClass = if format == "card": "rsscard-container" else: "rsslist-container"
    var rssItems: seq[RSSItem]

    let infoQuery = meassure:
        if keyword.len == 0:
            rssItems = getLatestRSSItems(articleCount, userid)
        else:
            var searchResults = getFTI(keyword, lang, userid) # @["1158,4", "118,10"...]
            searchResults.sortFTIResult(sortBy)
            # Reduce result to max_search_results
            let mx = min(searchResults.len, articleCount)
            for idx in 0..mx-1:
                rssItems.add(loadObject[RSSItem](searchResults[idx].subscript))

    let infoRender = meassure:
        for rssItem in rssItems:
            if format == "card":
                cards.add(createRSSItemCard(rssItem))
            else:
                cards.add(createRSSItemList(rssItem))

    let articles = fmt"{rssItems.len} articles"
    let infotxt = if rssItems.len > 0: fmt"{articles} in {infoQuery} + {infoRender}" else: fmt"Indexsearch in {infoQuery}"
    let infoContainer = fmt"""<h3 id="info">{infotxt}</h3>"""
    let rssContainer = fmt"""<div id="rsscard" class="{containerClass}">{cards}</div>"""
    let keywordContainer = fmt"""<div id="keywords">{$keywords}</div>"""

    SSE(req): 
        patchElements(sse, infoContainer)
        patchElements(sse, rssContainer)
        patchElements(sse, keywordContainer)


# Callback for router registration
proc register*(router: var Router) =
    router.post("/search", handleSearch)


# Create module instance
let wmSearchModule* = WebModule(
    name: "wmSearch",
    register: register
)