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


proc handleUpdateClock(req: Request) =
    let userid = getSignal(req, USERID)
    var lastSHA1: string

    # /update-clock and RSSItems (Do not close the connection)
    var sse = req.respondSSE()
    while true:
        try:
            let loggedIn = if userid.len > 0 and getSignal(userid, "loggedIn") == "true": true else: false
            let msg = if loggedIn: getWallClock(userid) else: ""

            # Update Wall-Clock
            patchElements(sse, fmt"<h3 id='wallclock'>{msg}</h3>")

            if loggedIn:
                # Show articles for logged in users
                let formId = getSignal(userid, "formId")
                let keyword = strip(getSignal(userid, "keyword"))
                let sort = getSignal(userid, "sort")
                let direction = getSignal(userid, "direction")
                let sortBy = getSortBy(sort, direction)

                if formId == "livefeed" and keyword.len == 0:
                    let format = getSignal(userid, "format")
                    let articlesCount = parseInt(getSignal(userid, "articles"))

                    var rssItems: seq[RssItem]
                    var cardsContent: string
                    let info = meassure:
                        rssItems = getLatestRSSItems(articlesCount, userid, sortBy)

                    let infoRender = meassure:
                        for rssItem in rssItems:
                            if format == "card":
                                cardsContent.add(createRSSItemCard(rssItem))
                            else:
                                cardsContent.add(createRSSItemList(rssItem))

                    # Check for new acticles
                    let sha1 = generateSHA1(cardsContent)
                    if sha1 != lastSHA1:
                        lastSHA1 = sha1
                        let articles = fmt"{rssItems.len} articles"
                        let infotxt = if rssItems.len > 0: fmt"{articles} in {info} + {infoRender}" else: fmt"Fetch in {info}"
                        let infoContainer = fmt"""{{<h3 id="info">{infotxt}</h3>}}"""
                        patchElements(sse, infoContainer)

                        var containerClass = if format == "card": "rsscard-container" else: "rsslist-container"
                        let rssContainer = fmt"<div id='rsscard' class='{containerClass}'>{cardsContent}</div>"
                        patchElements(sse, rssContainer)
            else:
                echo "Leaving WallClock loop. No longer loggedIn"
                break  # no longer loggedIn

            let msToNextMinute = 60000 - (now().second * 1000 + now().nanosecond div 1_000_000)
            sleep(msToNextMinute)
        except:
            echo "Leaving handleUpdateClock: ", getCurrentExceptionMsg()
            sse.close()
            break


proc handleShowRSSItem(req: Request) =
    # Display the raw RSS/RSSItem data in a popup window
    let signals = getSignals(req)
    let id = signals["id"].getStr()
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

    router.get("/update-clock", handleUpdateClock)
    router.get("/show-rssitem", handleShowRSSItem)

    # Standard handlers
    router.get("/goto/**", handleGoto)
    router.notFoundHandler = serveStatic

    let (host, port) = ("localhost", 8080)
    let server = newServer(router)
    echo fmt"Simple SSE / Datastar server - Open http://{host}:{port} in your browser"

    server.serve(Port(port), host)
