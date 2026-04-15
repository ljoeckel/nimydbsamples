## Run 'nimble demo'

import std/[os, times, json, strutils, strformat, tables, algorithm, sequtils, sugar]
import std/[options, typetraits, enumerate]
import std/[sha1, httpclient]
import mummy, mummy/routers, mummy/datastar
import macros
import nimrss


proc handleSearch(req: Request) =
    echo "handleSearch"
    let userid = getSignal(req, USERID)
    let keyword = getSignal(req, "keyword")
    var lang = getSignal(req, "lang")
    if lang.len == 0: lang = "DE"

    if keyword.len == 0:
        handleLiveFeed(req)
        return

    let stemword = stem(keyword, lang)

    var cards: string
    var keywords: string  # TODO: handle more keywords after keyword
    
    var info = meassure:
        var searchResults = getFTI(keyword, lang, userid) # @["1158,4", "118,10"...]
        searchResults.sortFTIResult(SortBy.ByTimeDescending)
        # Reduce result to max_search_results
        let mx = min(searchResults.len, MAX_SEARCH_RESULTS)
        for idx in 0..mx-1:
            let rssItem = loadObject[RSSItem](searchResults[idx].subscript)
            cards.add(createRSSItemCard(rssItem))
   
    let articles = fmt"{mx} articles"
    let infotxt = if articles.len > 0: fmt"{articles} in {info}" else: fmt"Indexsearch in {info}"
    let infoContainer = fmt"""{{<h3 id="info">{infotxt}</h3>}}"""

    let rssContainer = fmt"""{{<div id="rsscard" class="rsscard-container">{cards}</div>}}"""
    let keywordContainer = fmt"""{{<div id="keywords">{$keywords}</div>}}"""

    SSE(req): 
        patchElements(sse, infoContainer)
        patchElements(sse, rssContainer)
        patchElements(sse, keywordContainer)


# Callback for router registration
proc register*(router: var Router) =
    echo "register /livefeed"
    router.get("/livefeed", handleLiveFeed)


# Create module instance
let wmSearchModule* = WebModule(
    name: "wmSearch",
    register: register
)