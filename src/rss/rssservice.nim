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

proc updateWallClock(sse: SSEConnection) =
    let wc = now().format("dd.MM.yyyy - HH:mm")
    patchElements(sse, fmt"<h3 id='wallclock'>{wc}</h3>") # Update Wall-Clock


proc handleUpdateClock(req: Request) =
    let userid = getUserId(req)
    let loggedIn = if userid.len > 0 and getSignal(userid, "loggedIn") == "true": true else: false
    var sse = req.respondSSE()

    while loggedIn:
        try:
            updateWallClock(sse)

            let msToNextMinute = 60000 - (now().second * 1000 + now().nanosecond div 1_000_000)
            #sleep(msToNextMinute)
            sleep(5000)

            let formId = getSignal(userid, "formId")
            let lastPubDate = getSignal(userid, "lastPubDate")
            let lastIdxRef = getSignal(userid, "lastIdxRef")

            let lastRun = Get ^Session(userid, "lastRun").int        
            let lastCollectorRun = Get ^Session("rsscollector", "lastRun").int # any new news?
            #echo "lastCollectorRun=", lastCollectorRun, " lastRun=", lastRun, " lastPubDate=", lastPubDate, " lastIdxRef=", lastIdxRef
            if lastRun > 0 and lastCollectorRun > lastRun and formId == "livefeed":
                Set: ^Session(userid, "lastRun") = lastCollectorRun
                let timeFrom = Get ^Session("rsscollector", "oldestPubDate").int
                var p = getSearchParams(sse)
                p.searchType = SearchType.Incremental
                p.lastPubDate = timeFrom + 1
                handleSearch(sse, p)
        except:
            echo "Leaving handleUpdateClock: ", getCurrentExceptionMsg()
            break
    sse.close()


proc handleShowRSSItem(req: Request) =
    # Display the raw RSS/RSSItem data in a popup window
    let userid = getUserId(req)
    let id = getSignal(userid, "id")
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

    router.post("/update-clock", handleUpdateClock)
    router.get("/show-rssitem", handleShowRSSItem)
    router.post("/update-scroll", handleUpdateScroll)
    

    # Standard handlers
    router.get("/goto/**", handleGoto)
    router.notFoundHandler = serveStatic

    let (host, port) = ("localhost", 8080)
    let server = newServer(router)
    echo fmt"Simple SSE / Datastar server - Open http://{host}:{port} in your browser"

    server.serve(Port(port), host)
