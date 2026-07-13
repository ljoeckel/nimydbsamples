## Run 'nimble demo'

import std/[os, times, strutils, strformat, typetraits, json]
import mummy, mummy/routers, mummy/datastar
import nimrss

# WebModules
import wmFeedConfig
import wmLogin
import wmSearch
import wmStats
import wmWordcloud
import wmDbMonitor

proc updateWallClock(sse: SSEConnection) =
    let dt = now()
    let wc = dt.format("dd.MM.yyyy - HH:mm")
    patchElements(sse, fmt"<h3 id='wallclock'>{wc}</h3>") # Update Wall-Clock

    # HTML ISO 8601  format: YYYY-MM-DDThh:mm
    let date = dt.format("yyyy-MM-dd")
    let time = dt.format("HH:mm")
    patchSignals(sse, %* { "dateTime": fmt"{date}T{time}" })


proc handleUpdateClock(req: Request) =
    let ctx = getContext(req)
    var sse = req.respondSSE()
    var endPubDate = getFirstPubDate()
    echo toDateTime(datetimeToUnix()),": User: ", ctx.userid, " enter handleUpdateClock"

    try:
        updateWallClock(sse)
        var p = getSearchParams(sse)
        p.searchType = SearchType.Basic
        handleSearch(sse, p)
    except:
        echo "ERROR: ", getCurrentExceptionMsg()

    var loggedIn = if ctx.userid.len > 0 and ctx.getBool("loggedIn"): true else: false
    while loggedIn:
        try:
            updateDBStats("srv")
            let msToNextMinute = 60000 - (now().second * 1000 + now().nanosecond div 1_000_000)
            sleep(msToNextMinute)

            loggedIn = ctx.getBool("loggedIn")
            let formId = ctx.getStr("formId")
            let lastRun = ctx.getInt("lastRun")
            let lastCollectorRun = ctx.getInt("rsscollector", "lastRun") # any new news?
            
            echo toDateTime(datetimeToUnix()),": User: ", ctx.userid, " formId:", formId, " lastRun:", toDateTime(lastRun), " lastCollectorRun:", toDateTime(lastCollectorRun)
            if lastRun > 0 and lastCollectorRun > lastRun and formId == "livefeed":
                var p = getSearchParams(sse)
                p.searchType = SearchType.Incremental
                p.lastPubDate = int.high 
                p.lowerBoundPubdate = endPubDate
                handleSearch(sse, p)
                endPubDate = getFirstPubDate()
            
            updateWallClock(sse)

        except:
            echo "Leaving handleUpdateClock: ", getCurrentExceptionMsg()
            break
        
    sse.close()


proc handleShowRSSItem(req: Request) =
    # Display the raw RSS/RSSItem data in a popup window
    let ctx = getContext(req)
    let id = ctx.getStr("id")
    let subscript = id.split(',')
    let rssFields = getRSSFields(subscript)
    
    var tbody = "<tbody id='rssinfo'>"
    for (field, value) in rssFields:
        if value.isEmptyOrWhitespace(): continue
        tbody.add(fmt"""
            <tr>
                <td align='right'>{field}</td>
                <td align='right'>{value}</td>
            </tr>
            """)
    tbody.add("</tbody>")

    SSE(req):
        patchElements(sse, tbody) # set new data


proc handleUpdateScroll(req: Request) =
    # Dummy handler to allow 'lastScroll' signal update
    # A empty patchSignals must be send, otherwise the client waits for an answer
    # When the next request is then made, the client aborts the previous connection
    # with NS_BINDING_ABORTED
    SSE(req):
        patchSignals(sse, %*{})


if isMainModule:
    ## Handler für Ctrl+C (SIGINT)
    proc shutdown() {.noconv.} =
        echo "\nShutting down..."
        quit(0)
    setControlCHook(shutdown)

    var router = Router()
    # Register WebModules
    wmFeedConfigModule.register(router)
    wmLoginModule.register(router)
    wmSearchModule.register(router)
    wmStatsModule.register(router)
    wmWordcloud.register(router)
    wmDbMonitor.register(router)

    router.post("/update-clock", handleUpdateClock)
    router.post("/show-rssitem", handleShowRSSItem)
    router.post("/update-scroll", handleUpdateScroll)
    

    # Standard handlers
    router.post("/goto/**", handleGoto)
    router.notFoundHandler = serveStatic

    let (host, port) = ("localhost", 8080)
    let server = newServer(router)
    echo fmt"Simple SSE / Datastar server - Open http://{host}:{port} in your browser"

    server.serve(Port(port), host)
