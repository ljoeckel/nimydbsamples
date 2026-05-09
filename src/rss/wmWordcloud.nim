import std/[strutils, strformat, times]

import mummy, mummy/routers
import nimrss

import nimpy
import nimpy/py_lib  # Importiert die C-API-Definitionen

    
proc getDayFromTo*(year, month, day: int): (int, int) =
    # Get time range for the current day    
    let date = fmt"{year:02}-{month:02}-{day:02}"
    echo "date=", date
    let dt1 = parse(date & " 00:00:00", "yyyy-MM-dd HH:mm:ss")
    let dt2 = parse(date & " 23:59:59", "yyyy-MM-dd HH:mm:ss")
    return (dt1.toTime().toUnix(),  dt2.toTime().toUnix())


proc getCurrentDay(datetime: int): string =
    let timeObj = fromUnix(datetime)
    let dt = timeObj.local
    result = dt.format("yyyy-MM-dd")

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
    let plt = pyImport("matplotlib.pyplot")

    var processed: int
    var words: string
    let feedtable = getEnabledFeeds("guest")
    let currentDay = getCurrentDay(day00)

    for subs in QueryItr ^RSSItemPUBDATE(day00).keys:
        let dt = parseInt(subs[0])
        let rssSubs = subs[1].split(",")
        let wc = getRSSItemWords(rssSubs, feedtable)
        if wc.len > 0:
            words.add(wc)
            inc processed

    if not words.isEmptyOrWhitespace:
        let cloud = wc.WordCloud(width=800, height=400, min_word_length=3, collocations=false, background_color="white").generate(words)
        #discard cloud.to_file(fmt"wc/cloud{currentDay}.png")
        discard cloud.to_file(fmt"html/wordcloud.png")

    return processed

proc createWordCloudForToday*(): int =
    let (day00, day24) = currentDayFromTo()
    createWordCloudFromTo(day00, day24)

proc createWordCloudForAllDays(): int =
    let wc = pyImport("wordcloud")
    let plt = pyImport("matplotlib.pyplot")
    let feedtable = getEnabledFeeds("guest")

    var lastDay: string
    var words: string
    var processed, processedTotal = 0
    var lang: string

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


proc handleStats(req: Request) =
    echo "get-wordcloud"
    let userid = getSignal(req, USERID)
    let wcType = strip(getSignal(req, "wordcloud"))
    var lang = getSignal(req, "lang")
    echo "userid=", userid, " wcType=", wcType, " lang=", lang
    if lang.len == 0: lang = "DE"

    let processed = createWordCloudForToday()
    echo fmt"Processed {processed} Articles"


# Callback for router registration
proc register*(router: var Router) =
    router.get("/get-wordcloud", handleStats)

# Create module instance
let wmWordcloudModule* = WebModule(
    name: "wmWordclout",
    register: register
)

if isMainModule:
    var processed: int
    let (day00, day23) = getDayFromTo(2026,5,8)
    processed = createWordCloudFromTo(day00, day23)
    echo fmt"Processed {processed} Articles"
    
    #createWordCloudForAllDays()

    processed = createWordCloudForToday()
    echo fmt"Processed {processed} Articles"