import std/[strutils, strformat, times]
import mummy, mummy/routers, mummy/datastar
import nimrss
import nimpy

    
proc getRSSItemWords(subs: seq[string], feedtable: seq[string]): string =
    # Get the article
    let rssItem = loadObject[RSSItem](subs)
    if not feedtable.contains(getOption(rssItem.feedId)): return

    # get the language from the RSS
    let id = subs[0]
    var language = Get ^RSS(id, "language")
    if language.len > 0: # ignore articles without language
        if language.contains("-"): language = language.split("-")[0]
        let txt = getOption(rssItem.title)
        let filteredWords = splitWords(txt, language)
        return filteredWords.join(" ")


proc createWordCloudFromTo(day00, day24: int): int =
    let wc = pyImport("wordcloud")
    var processed: int
    var words: string
    let feedtable = getEnabledFeeds("guest")

    for subs in QueryItr ^RSSItemPUBDATE(day00).keys:
        let rssSubs = subs[1].split(",")
        let wc = getRSSItemWords(rssSubs, feedtable)
        if wc.len > 0:
            words.add(wc)
            inc processed

    if not words.isEmptyOrWhitespace:
        let cloud = wc.WordCloud(width=800, height=400, min_word_length=3, collocations=false, background_color="white").generate(words)
        discard cloud.to_file(fmt"html/wordcloud.jpg")

    return processed


proc createWordCloudForToday*(): int =
    let (day00, day24) = currentDayFromTo()
    createWordCloudFromTo(day00, day24)


proc createWordCloudForAllDays(): int =
    let wc = pyImport("wordcloud")
    let feedtable = getEnabledFeeds("guest")

    var lastDay: string
    var words: string
    var processed, processedTotal = 0

    for subs in QueryItr ^RSSItemPUBDATE.keys:
        let pubDate = parseInt(subs[0])
        let timeObj = fromUnix(pubDate)
        let dt = timeObj.local
        let currentDay = dt.format("yyyy-MM-dd")
        if lastDay != currentDay:
            echo "Processed ", processed, " articles for ", currentDay
            if not words.isEmptyOrWhitespace and processed >= 10:
                let cloud = wc.WordCloud(width=800, height=400, min_word_length=3, collocations=false, background_color="white").generate(words)
                discard cloud.to_file(fmt"wc/cloud{currentDay}.png")

            inc(processedTotal, processed)
            processed = 0
            words = ""
            lastDay = currentDay

        # Get the article
        let rssId = subs[1].split(",")
        let wc = getRSSItemWords(rssId, feedtable)
        if wc.len > 0:
            words.add(wc)
            inc processed

    return processedTotal


proc handleGetWordcloud(req: Request) =
    let userid = getUserId(req)
    var lang = getSignal(userid, "lang")
    if lang.len == 0: lang = "DE"
    let processed = createWordCloudForToday()
    echo fmt"Processed {processed} Articles"


# Callback for router registration
proc register*(router: var Router) =
    #router.get("/get-wordcloud", handleGetWordcloud) # disabled due to python GIL problem
    discard

# Create module instance
let wmWordcloudModule* = WebModule(
    name: "wmWordclout",
    register: register
)

if isMainModule:
    var processed: int
    # let (day00, day23) = getDayFromTo(2026,5,8)
    # processed = createWordCloudFromTo(day00, day23)
    # echo fmt"Processed {processed} Articles"
    
    #createWordCloudForAllDays()

    processed = createWordCloudForToday()
    echo fmt"Processed {processed} Articles"