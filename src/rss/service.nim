## Run 'nimble demo'

import std/[os, times, json, strutils, strformat, tables, algorithm, sequtils]
import std/[options, typetraits, enumerate]
import std/[sha1, httpclient, times]
import mummy, mummy/routers, mummy/datastar
import macros
import rssatom
import yottadb
import types
import searchlib

const
    MAXNEWS = 30 # How many news to show in 'latest'
    HTML_DIR = "html/"


template meassure(body: untyped): auto =
    let t0 = getTime()
    body
    let td = (getTime() - t0).inMicroseconds
    if td > 1000:
        $(td div 1000) & "ms."
    else:
        $td & " µs."


template SSE(req: Request, body: untyped) =
    var sse {.inject.} = req.respondSSE() # sse for body
    defer: sse.close()
    body


proc listSession() =
    echo "Session:"
    for k,v in QueryItr Session.kv:
        echo k, "=", v


proc getSignal(req: Request, key: string): string = 
    let signals = getSignals(req)
    # Update Session variable
    if "userid" in signals:
        let userid = $signals["userid"]
        for k,v in signals.pairs:
            Set: Session(userid, k) = v

    if key in signals:
        result = $signals[key]
        if result.startsWith("\"") and result.endsWith("\""): # Remove "xxxx" -> xxxx
            result = result[1..^2]


proc handleGoto(req: Request) =
    # process menu links g.E. <a href="#form" data-on:click="$menuOpen = false; @get('goto/form.html')">Registration</a>
    let page = req.path.split("/goto/")[1]
    SSE(req):
        #clearFormFields(sse)
        #clearTechFields(sse)
        forward(sse, HTML_DIR & page)


proc getFeeds(): seq[Feed] =
    for title in OrderItr ^RSSTITLE:
        let id = Order ^RSSTITLE(title, "")
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
    let feedId = getOption(rss.feedId)
    
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
            <div class="rsscard-footer">
                <p>{divimg}</p>
                <p class="rsspubdate"> {pubDate} / {rss.idxref} / {feedId}</p>
                {image}
            </div>
        </div>
        """
    return card

proc createLatestCards(max: int, userid: string): string =
    let userFeeds = loadObject[UserFeeds](userid)

    var cards: string
    let items = getLatestRSSItems(max, userFeeds.feeds)
    for rssItem in items:
        # produce cards for output
        cards.add(createRSSItemCard(rssItem))

    var container = fmt"""{{
            <div id="livefeed" class="rsscard-container" data-init="@get('/livefeed')">
                {cards}
            </div>      
        }}"""
    return container

proc getWallClock(req: Request): string =
    let userid = getSignal(req, "userid")
    let nowTime = now().format("dd.MM.yyyy - HH:mm")
    result = fmt"{userid} / {nowTime}"


proc handleLiveFeed(req: Request) =
    let userid = getSignal(req, "userid")
    let wallclock = getWallClock(req)
    let keywordContainer = fmt"""{{<div id="keywords"></div>}}"""

    SSE(req):
        patchElements(sse, fmt"<h3 id='wallclock'>{wallclock}</h3>")
        patchElements(sse, keywordContainer) # clear keyword search result
        patchElements(sse, createLatestCards(MAXNEWS, userid))


proc handleUpdateClock(req: Request) =
    # /update-clock and RSSItems (Do not close the connection)
    var sse = req.respondSSE()
    let userid = getSignal(req, "userid")
    while true:
        try:
            # Update Wall-Clock
            let msg = getWallClock(req)
            patchElements(sse, fmt"<h3 id='wallclock'>{msg}</h3>")

            # Show articles for logged in users
            if userid.len > 0:
                # Update Articles
                let formId = getSignal(req, "formId")
                echo "updateclock page:", formId, " signals=", getSignals(req)
                if formId == "livefeed":
                    patchElements(sse, createLatestCards(MAXNEWS, userid))

            #let msToNextMinute = 60000 - (now().second * 1000 + now().nanosecond div 1_000_000)
            #sleep(msToNextMinute)
            sleep(10000)
        except:
            echo "Leaving handleUpdateClock: ", getCurrentExceptionMsg()
            sse.close()
            break


proc createTRFeed(id: string, title: string, enabled: bool): string =
    # Construct a <TR><TD>Feed with id, title, status
    var dataclass = fmt"{{selected: $id==='{id}'}}"
    var markedclass = if enabled: "class='marked'" else: ""
    let checkbox = if enabled: "<i class='bi bi-check-square'></i>" else: "<i class='bi-dash-square-dotted'></i></i>"
    result = fmt"""
        <tr {markedclass} id='Feed{id}' data-on:click__stop="$id='{id}'; @post('/select-feed')" data-class="{dataclass}">
            <td>{id}</td>
            <td>{title}</td>
            <td>
                <button data-on:click__stop="$id='{id}';$title='{title}'; @post('/toggle-feed')">{checkbox}</button>
            </td>
        </tr>
        """

proc createTRFeed(feed: Feed): string =
    createTRFeed(feed.rssid, feed.title, feed.enabled)


proc handleGetFeeds(req: Request) {.gcsafe.} =
    let userid = getSignal(req, "userid")
    var userFeeds = loadObject[UserFeeds](userid)
    if userFeeds.feeds.len == 0: # init user feeds from base config
        userFeeds.userid = userid
        userFeeds.feeds = getFeeds()
        saveObject[UserFeeds](userid, userFeeds)

    # Create the tbody
    var tbody = fmt"""<tbody id="feed-table" data-init="@get('/get-feeds')">"""
    let head = Feed(rssid:" ", title:" Select all", enabled:false)
    tbody.add(createTRFeed(head))

    for feed in userFeeds.feeds:
        tbody.add(createTRFeed(feed))
    tbody.add("</tbody>")

    SSE(req):
        patchElements(sse, tbody)


proc handleToggleFeed(req: Request) {.gcsafe.} =
    # Toggle Row
    let userid = getSignal(req, "userid")
    let id = getSignal(req, "id")
    let userFeeds = loadObject[UserFeeds](userid)

    # Update DB
    var init: bool
    var flip: bool
    for idx, feed in enumerate(userFeeds.feeds):
        if id == " ":  # select / deselect all
            if not init:
                flip = (not feed.enabled)
                init = true
            Set: ^Feed(userid, $idx, "enabled") = flip # update db

        elif feed.rssid == id:
            Set: ^Feed(userid, $idx, "enabled") = (not feed.enabled) # update db
            let row = createTRFeed(feed.rssid, feed.title, (not feed.enabled))
            SSE(req): patchElements(sse, row) # update gui
            return
    
    handleGetFeeds(req)
   

proc handleLogin(req: Request) =
    let userid = getSignal(req, "userid")
    if userid == "ljoeckel" or userid == "guest":
        SSE(req):
            forward(sse, "./html/livefeed.html")


proc handleLogout(req: Request) =
    SSE(req):
        forward(sse, "./html/index.html")


proc handleSearch(req: Request) =
    let keyword = getSignal(req, "keyword")
    if keyword.len == 0:
        handleLiveFeed(req)
        return

    var cards: string
    var keywords: string
    var articles: string
    
    var info = meassure:
        let itemkeys = getRSSItemKeys(keyword) # @["1158,4", "118,10"...]
    
        if itemkeys.len > 0:
            for key in itemkeys:
                let parts = key.split(",")
                let rssItem = loadObject[RSSItem](@[parts[0], parts[1]])
                cards.add(createRSSItemCard(rssItem))
            
            articles = fmt"{itemkeys.len} articles"
        else:
            for word in getKeywords(keyword):
                keywords.add(word & " ")

    let infotxt = if articles.len > 0: fmt"{articles} in {info}" else: fmt"Indexsearch in {info}"
    let infoContainer = fmt"""{{
        <h3 id="info">{infotxt}</h3>
    }}"""

    let rssContainer = fmt"""{{
        <div id="livefeed" class="rsscard-container" data-init="@get('/livefeed')">{cards}</div>      
    }}"""

    let keywordContainer = fmt"""{{
        <div id="keywords">{$keywords}</div>      
    }}"""

    SSE(req): 
        patchElements(sse, infoContainer)
        patchElements(sse, rssContainer)
        patchElements(sse, keywordContainer)



if isMainModule:
    Kill: ^Session

    ## Handler für Ctrl+C (SIGINT)
    proc shutdown() {.noconv.} =
        echo "\nShutting down..."
        quit(0)
    setControlCHook(shutdown)

    var router = Router()
    router.post("/login", handleLogin)
    router.get("/logout", handleLogout)
    router.get("/livefeed", handleLiveFeed)
    router.get("/get-feeds", handleGetFeeds)

    router.post("/search", handleSearch)
    router.post("/select-feed", handleToggleFeed)
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
