## Run 'nimble demo'

import std/[os, times, json, strutils, strformat, tables, algorithm, sequtils]
import std/[options, typetraits, enumerate]
import std/[sha1, httpclient, times]
import mummy, mummy/routers, mummy/datastar
import macros
import rssatom

import yottadb
import utils
import types
import searchlib
import locks

# type 
#     Feed = object of RootObj
#         id: int
#         title: string
#         enabled: bool = true

#     UserFeeds = object of RootObj
#         userid: string
#         feeds: seq[Feed]


const
    MAXNEWS = 30 # How many news to show in 'latest'
    HTML_DIR = "html/"

# var 
#     feedsLock: Lock
#     feeds: seq[Feed]

# template withFeeds(body: untyped) =
#     {.cast(gcsafe).}:
#         withLock feedsLock:
#             body

template SSE(req: Request, body: untyped) =
    var sse {.inject.} = req.respondSSE() # sse for body
    defer: sse.close()
    body

proc handleGoto(req: Request) =
    # process menu links g.E. <a href="#form" data-on:click="$menuOpen = false; @get('goto/form.html')">Registration</a>
    let page = req.path.split("/goto/")[1]
    SSE(req):
        #clearFormFields(sse)
        #clearTechFields(sse)
        forward(sse, HTML_DIR & page)

# proc getId(req: Request):string =
#     # get the Id field from the current form
#     let signals = getSignals(req)
#     trimString($signals["id"])

proc getFeeds(): seq[Feed] =
    for title in OrderItr ^RSSTITLE:
        let id = Order ^RSSTITLE(title, "")
        #let enabled = Get ^RSSTITLE(title, id).bool
        var feed: Feed
        feed.rssid = id
        feed.title = title
        feed.enabled = true
        #feed.enabled = enabled
        result.add(feed)


proc createRSSItemCard(rss: RSSItem): string =
    let idxref = rss.idxref
    let title = getOption(rss.title)
    let description = getOption(rss.description)
    let link = getOption(rss.link)

    # categories
    var category: string
    if rss.category.len > 0:
        var cat: string
        for idx, word in enumerate(rss.category):
            cat.add(word & " ")
            if idx >= 2: break
        category = fmt"""<span class="tag">{cat}</span>"""
    
    var topic = getOption(rss.topic)
    if topic.len > 0:
        topic = fmt"""<span class="tag">{toUpper(topic)}</span>"""
    
    var keywords: string
    if rss.keywords.len > 0:
        var keywordlist: string
        for idx, word in enumerate(rss.keywords):
            keywordlist.add(word & " ")
            if idx >= 2: break
        keywords = fmt"""<span class="tag">{keywordlist}</span>"""

    let dt = getOption(rss.pubDate)
    var pubDate: string
    try: 
        pubDate = fmt"{parseInt(dt).fromUnix.local()}"
    except:
         pubDate = "01.01.1970"

    var image:string
    if rss.enclosure.url.len > 0 and rss.enclosure.enclosureType.len > 0 and rss.enclosure.enclosureType.startsWith("image/"):
        image = fmt"""
                <image src="{rss.enclosure.url}" class="rssimage">
            """
    image = ""

    # load feed RSSImage
    let rssImage = loadObject[RSSImage](rss.idxref.split(',')[0])
    let feedUrl = getOption(rssImage.url)
    var divimg: string
    if feedUrl.len > 0:
        let feedTitle = getOption(rssImage.title)
        let feedLink = getOption(rssImage.link)
        var feedWidth = getOption(rssImage.width)
        if feedWidth.len == 0: feedWidth = "90"
        var feedHeight = getOption(rssImage.height)
        if feedHeight.len == 0: feedHeight = "36"
        let feedDescription = getOption(rssImage.description)
        #if feedUrl.len > 0: divimg.add(fmt"""<image src="{feedUrl}" class="icon">""")
        divimg.add(fmt"""<a target="_blank" href={feedLink} class="footer-link">""")
        divimg.add(fmt"""<span class="feed-title">{feedTitle}</span>""")
        divimg.add("</a>")

    let card = fmt"""
        <div class="rsscard">
            <div class="rsscard-tags">
                {topic}
                {category}
                {keywords}
            </div>
            <div class="rsscard-title">  <a target="_blank" href="{link}">{title}</a> </div>
            <p class="rsscard-text"> {description} </p>

            <!-- Icon / Text mit URL -->
            <div class="rsscard-footer">
                <p>{divimg}</p>
                <p class="rsspubdate"> {pubDate} / {rss.idxref} </p>
                {image}
            </div>
        </div>
        """
    return card

proc createLatestCards(max: int, userid: string): string =
    echo "createLatestCards: userid=", userid
    let userFeeds = loadObject[UserFeeds](userid)

    var cards: string
    let items = getLatestRSSItems(max, userFeeds.feeds)
    echo "createLatestCards: Have ", items.len, " items"
    for rssItem in items:
        # produce cards for output
        cards.add(createRSSItemCard(rssItem))

    var container = fmt"""{{
            <div id="container" class="rsscard-container" data-init="@get('/livefeed')">
                {cards}
            </div>      
        }}"""
    return container

proc getWallClock(req: Request): string =
    let signals = getSignals(req)
    let userid = signals["userid"].getStr()
    let nowTime = now()
    result = userid & " : " & nowTime.format("dd.MM.yyyy - HH:mm")


proc handleLiveFeed(req: Request) =
    let signals = getSignals(req)
    echo "formId=", signals["formId"].getStr
    let userid = signals["userid"].getStr()

    echo "handelLiveView: signals=", signals
    let wallclock = getWallClock(req)

    SSE(req):
        patchElements(sse, fmt"<h3 id='wallclock'>{wallclock}</h3>")
        #echo "LiveFeed calling createLatestCards"
        #patchElements(sse, createLatestCards(MAXNEWS, userid))



proc handleUpdateClock(req: Request) =
    # /update-clock and RSSItems (Do not close the connection)
    let signals = getSignals(req)
    echo "handleUpdateClock formId=", signals["formId"].getStr
    let userid = signals["userid"].getStr()
    var sse = req.respondSSE()

    while true:
        try:
            let msg = getWallClock(req)
            patchElements(sse, fmt"<h3 id='wallclock'>{msg}</h3>")
            patchElements(sse, createLatestCards(MAXNEWS, userid))
            let upcount = Increment ^RSSCNT("clock-loop")
            echo "upcount=", upcount

            #let nowTime = now()
            #let msToNextMinute = 60000 - (nowTime.second * 1000 + nowTime.nanosecond div 1_000_000)
            sleep(30000)
            #sleep(msToNextMinute)
        except:
            echo "Leaving handleUpdateClock: ", getCurrentExceptionMsg()
            sse.close()
            break


proc createTRFeed(id: string, title: string, enabled: bool): string =
    # Construct a <TR><TD>Feed with id, title, status
    let dataclass = "{" & fmt"selected: $id==='{id}'" & "}"
    let marked = if enabled: "<i class='bi bi-check-square'></i>" else: "<i class='bi-dash-square-dotted'></i></i>"
    result = fmt"""
        <tr id='Feed{id}' data-on:click__stop="$id='{id}'; @post('/select-feed')" data-class="{dataclass}">
            <td>{id}</td>
            <td>{title}</td>
            <td>
                <button data-on:click__stop="$id='{id}';$title='{title}'; @post('/toggle-feed')">{marked}</button>
            </td>
        </tr>
        """

proc createTRFeed(feed: Feed): string =
    createTRFeed(feed.rssid, feed.title, feed.enabled)


proc handleGetFeeds(req: Request) {.gcsafe.} =
    let signals = getSignals(req)
    echo "handleGetFeeds signals=", signals
    let userid = signals["userid"].getStr()
    var userFeeds = loadObject[UserFeeds](userid)

    if userFeeds.feeds.len == 0: # init user feeds from base config
        userFeeds.userid = userid
        userFeeds.feeds = getFeeds()
        saveObject[UserFeeds](userid, userFeeds)

    # Get Feed's from ^RSSTITLE to present in a table
    var tbody = fmt"""<tbody id="feed-table" data-init="@get('/get-feeds')">"""
    for feed in userFeeds.feeds:
        tbody.add(createTRFeed(feed))
    tbody.add("</tbody>")

    SSE(req):
        patchElements(sse, tbody)


proc handleToggleFeed(req: Request) {.gcsafe.} =
    # Toggle Row
    let signals = getSignals(req)
    let userid = trimString($signals["userid"])
    let feedid = trimString($signals["id"])

    # Update DB
    let userFeeds = loadObject[UserFeeds](userid)
    for idx, feed in enumerate(userFeeds.feeds):
        if feed.rssid == feedid:
            Set: ^Feed(userid, $idx, "enabled") = (not feed.enabled) # update db
            let row = createTRFeed(feed.rssid, feed.title, (not feed.enabled))
            SSE(req):
                patchElements(sse, row) # update gui
            break
   

proc handleLogin(req: Request) =
    let signals = getSignals(req)
    echo "handleLogin signals=", signals
    let userid = signals["userid"].getStr()
    if userid == "ljoeckel" or userid == "guest":
        SSE(req):
            forward(sse, "./html/livefeed.html")


if isMainModule:
    ## Handler für Ctrl+C (SIGINT)
    proc shutdown() {.noconv.} =
        echo "\nShutting down..."
        quit(0)
    setControlCHook(shutdown)

    var router = Router()
    router.post("/login", handleLogin)
    router.get("/livefeed", handleLiveFeed)
    router.get("/get-feeds", handleGetFeeds)
    router.post("/toggle-feed", handleToggleFeed)

    router.get("/update-clock", handleUpdateClock)
    #router.post("/validate-email", isEmailRegistered)

    # Standard handlers
    router.get("/goto/**", handleGoto)
    router.notFoundHandler = serveStatic

    let (host, port) = ("localhost", 8080)
    let server = newServer(router)
    echo fmt"Simple SSE / Datastar server - Open http://{host}:{port} in your browser"

    server.serve(Port(port), host)
