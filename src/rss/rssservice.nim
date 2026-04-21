## Run 'nimble demo'

import std/[os, times, strutils, strformat]
import std/[typetraits]
import mummy, mummy/routers, mummy/datastar
import nimrss
import common

# WebModules
import wmFeedConfig
import wmRSSCards
import wmLogin
import wmSearch


proc handleUpdateClock(req: Request) =
    echo "handleUpdateClock"
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
                let keyword = getSignal(userid, "keyword")
                if formId == "livefeed" and keyword.len == 0:
                    var cardsContent: string                    
                    var cardsCount: int
                    var info = meassure:
                        (cardsContent, cardsCount) = createLatestCards(MAXNEWS, userid)

                    let articles = fmt"{cardsCount} articles"
                    let infotxt = if articles.len > 0: fmt"{articles} in {info}" else: fmt"Fetch in {info}"
                    let infoContainer = fmt"""{{<h3 id="info">{infotxt}</h3>}}"""

                    # Check for new acticles
                    let sha1 = generateSHA1(cardsContent)
                    if sha1 != lastSHA1:
                        echo "New Articles"
                        lastSHA1 = sha1
                        patchElements(sse, infoContainer)
                        patchElements(sse, cardsContent)
            else:
                echo "Leaving WallClock loop. No longer loggedIn"
                break  # no longer loggedIn

            let msToNextMinute = 60000 - (now().second * 1000 + now().nanosecond div 1_000_000)
            #sleep(msToNextMinute)
            sleep(5000)
        except:
            echo "Leaving handleUpdateClock: ", getCurrentExceptionMsg()
            sse.close()
            break


if isMainModule:
    ## Handler für Ctrl+C (SIGINT)
    proc shutdown() {.noconv.} =
        echo "\nShutting down..."
        quit(0)
    setControlCHook(shutdown)

    var router = Router()
    # Register WebModules
    wmFeedConfigModule.register(router)
    wmRSSCardsModule.register(router)
    wmLoginModule.register(router)
    wmSearchModule.register(router)

    router.get("/update-clock", handleUpdateClock)

    # Standard handlers
    router.get("/goto/**", handleGoto)
    router.notFoundHandler = serveStatic

    let (host, port) = ("localhost", 8080)
    let server = newServer(router)
    echo fmt"Simple SSE / Datastar server - Open http://{host}:{port} in your browser"

    server.serve(Port(port), host)
