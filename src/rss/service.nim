## Run 'nimble demo'

import std/[os, times, json, strutils, strformat, tables, algorithm, sequtils, sugar]
import std/[options, typetraits, enumerate]
import std/[sha1, httpclient]
import mummy, mummy/routers, mummy/datastar
import macros
import nimrss

const
    MAXNEWS = 100 # How many news to show in 'latest'
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


func stripSignal(signal: string): string =
    result = strip(signal)
    if result.startsWith("\"") and result.endsWith("\""): # Remove "xxxx" -> xxxx
        result = result[1..^2]


proc getSignal(req: Request, key: string): string = 
    let signals = getSignals(req)
    if key in signals:
        result = strip($signals[key])
        if result.startsWith("\"") and result.endsWith("\""): # Remove "xxxx" -> xxxx
            result = result[1..^2]


proc handleGoto(req: Request) =
    # process menu links g.E. <a href="#form" data-on:click="$menuOpen = false; @get('goto/form.html')">Registration</a>
    let page = req.path.split("/goto/")[1]
    SSE(req):
        forward(sse, HTML_DIR & page)


proc getFeeds(): seq[Feed] =
    for feedId in OrderItr ^ConfigFeed:
        let feed = loadObject[ConfigFeed](feedId)
        result.add(loadObject[ConfigFeed](feedId))


proc createRSSItemCard(item: RSSItem): string =
    let title = getOption(item.title)
    let description = getOption(item.description)
    let link = getOption(item.link)

    # categories
    var category: string
    if item.category.len > 0:
        var cat: string
        for idx, word in enumerate(item.category):
            cat.add(word & " ")
            if idx >= 2: break
        category = fmt"""<span class="tag">{cat}</span>"""
    
    var topic = getOption(item.topic)
    if topic.len > 0: topic = fmt"""<span class="tag">{toUpper(topic)}</span>"""
    
    var keywords: string
    if item.keywords.len > 0:
        var keywordlist: string
        for idx, word in enumerate(item.keywords):
            keywordlist.add(word & " ")
            if idx >= 2: break # show only first 3 keywords
        keywords = fmt"""<span class="tag">{keywordlist}</span>"""

    var pubDate: string
    try: 
        let dt = getOption(item.pubDate)
        let fu = parseInt(dt).fromUnix()
        pubDate = fu.format("dd.MM.yyyy HH:mm")
    except:
         pubDate = "01.01.1970 00:00"

    # load feed RSSImage
    let rssImage = loadObject[RSSImage](item.idxref.split(',')[0])
    let feedUrl = getOption(rssImage.url)
    let feedId = getOption(item.feedId)
    
    var divimg, feedTitle, feedLink: string
    if feedUrl.len > 0:
        feedTitle = getOption(rssImage.title)
        if feedTitle.len == 0: feedTitle = getOption(item.title)
        feedLink = getOption(rssImage.link)
    else:
        let rssId = item.idxref.split(',')[0]
        feedTitle = Get ^RSS(rssId, "title")
        feedLink = Get ^RSS(rssId, "link")

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
            <div class="rsscard-title"> <a target="_blank" href="{link}"> {title}</a> </div>
            <p class="rsscard-text"> <a target="_blank" href="{link}"> {description}</a> </p>
            <div class="rsscard-footer">
                <p>{divimg}</p>
                <p class="rsspubdate"> {pubDate} / {item.idxref} / {feedId}</p>
            </div>
        </div>
        """

    return card


proc createLatestCards(max: int, userid: string): string =
    let userFeeds = loadObject[UserFeeds](userid)
   
    var cards: string
    for rssItem in getLatestRSSItems(max, userFeeds.feeds):
        # produce cards for output
        cards.add(createRSSItemCard(rssItem))

    let container = fmt"""{{
        <div id="rsscard" class="rsscard-container">{cards}</div>      
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


proc createTRFeed(feed: Feed): string =
    let id = feed.rssid
    let group = feed.group
    let title = feed.title
    let enabled = feed.enabled
    # Construct a <TR><TD>Feed with id, title, status
    var dataclass = fmt"{{selected: $id==='{id}'}}"
    var markedclass = if enabled: "class='marked'" else: ""
    let checkbox = if enabled: "<i class='bi bi-check-square'></i>" else: "<i class='bi bi-square'></i></i>"
    #let checkbox = if enabled: "<i class='bi bi-check-square'></i>" else: "<i class='bi-dash-square-dotted'></i></i>"
    result = fmt"""
        <tr {markedclass} id='Feed{id}' data-on:click__stop="$id='{id}'; @post('/select-feed')" data-class="{dataclass}">
            <td>{title}</td>
            <td>
                <button data-on:click__stop="$id='{id}';$title='{title}'; @post('/toggle-feed')">{checkbox}</button>
            </td>
        </tr>
        """


proc handleGetFeeds(req: Request) {.gcsafe.} =
    let userid = getSignal(req, "userid")
    var userFeeds = loadObject[UserFeeds](userid)
    if userFeeds.feeds.len == 0: # init user feeds from base config
        userFeeds.userid = userid
        userFeeds.feeds = getFeeds()
        saveObject[UserFeeds](userid, userFeeds)
        echo fmt"Created UserFeeds for '{userid}', Number of feeds: {userFeeds.feeds.len}"

    # Sort by group / title
    let feeds = userFeeds.feeds.sortedByIt(toUpper(it.group) & toUpper(it.title))

    # Create the tbody
    var tbody = fmt"""<tbody id="feed-table" data-init="@get('/get-feeds')">"""
    let head = Feed(rssid:" ", title:" Select all", enabled:false)
    tbody.add(createTRFeed(head))

    # Calculate css class for group title
    var groupsCount = initCountTable[string]()
    var groupsEnabled = initCountTable[string]()
    for feed in feeds:
        groupsCount.inc(feed.group)
        if feed.enabled: groupsEnabled.inc(feed.group)
    var classTable = initTable[string, string]()
    var classname: string
    for group, count in groupsCount.pairs:
        if groupsEnabled[group] == count: classname = "full"
        elif groupsEnabled[group] > 0:    classname = "partial"
        else:                             classname = "empty"
        classTable[group] = classname

    # create table-rows
    var oldGroup: string
    for feed in feeds:
        let class = "feedgroup-" & classTable[feed.group]
        # Add Group header
        if oldGroup != feed.group:
            var groupline = fmt"""
                <tr class='{class}'>
                    <td>{feed.group}</td>
                    <td>
                        <button data-on:click__stop="$id='{feed.group}';@post('/toggle-feedgroup')"><i class="bi bi-card-checklist"></i></button>
                    </td>
                </tr>
            """
            tbody.add(groupline)
            oldGroup = feed.group
        # Add Feed's
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
    var init, flip: bool
    for idx, feed in enumerate(userFeeds.feeds):
        if id == " ":  # select / deselect all
            if not init:
                flip = (not feed.enabled)
                init = true
            Set: ^Feed(userid, $idx, "enabled") = flip # update db
        elif feed.rssid == id:
            Set: ^Feed(userid, $idx, "enabled") = (not feed.enabled) # update db
    
    # Update gui    
    handleGetFeeds(req)
   

proc handleToggleFeedGroup(req: Request) =
    # Toggle a feedgroup
    let group = getSignal(req, "id")
    let userid = getSignal(req, "userid")
    var init, flip: bool
    var userFeeds = loadObject[UserFeeds](userid)

    for feed in userFeeds.feeds.mitems:
        if feed.group == group:
            if not init:
                flip = (not feed.enabled)
                init = true
            feed.enabled = flip
    saveObject[UserFeeds](userid, userFeeds) # update db
    handleGetFeeds(req) # update gui


proc handleLogin(req: Request) =
    let userid = getSignal(req, "userid")
    if userid == "ljoeckel" or userid == "guest":
        # Check for ^Feed
        let dta = Data ^Feed(userid)
        if dta == 0:  # no feeds for the user
            echo "Create initial Feeds for user ", userid
            var userFeeds: UserFeeds
            userFeeds.userid = userid

            for feedid in OrderItr ^ConfigFeed:
                let feed = loadObject[ConfigFeed](feedid)
                userFeeds.feeds.add(feed)
            saveObject[UserFeeds](userid, userFeeds)

        SSE(req):
            forward(sse, "./html/livefeed.html")


proc handleLogout(req: Request) =
    SSE(req):
        forward(sse, "./html/index.html")


proc handleSearch(req: Request) =
    let keyword = getSignal(req, "keyword")
    var lang = getSignal(req, "lang")
    if lang.len == 0: lang = "DE"

    if keyword.len == 0:
        handleLiveFeed(req)
        return

    let stemword = stem(keyword, lang)

    var cards: string
    var keywords: string
    var articles: string
    
    var info = meassure:
        let searchResults = getFTI(keyword, lang) # @["1158,4", "118,10"...]
        for searchResult in searchResults:
            let rssItem = loadObject[RSSItem](searchResult.subscript)
            cards.add(createRSSItemCard(rssItem))
        
        articles = fmt"{searchResults.len} articles"

    let infotxt = if articles.len > 0: fmt"{articles} in {info}" else: fmt"Indexsearch in {info}"
    let infoContainer = fmt"""{{
        <h3 id="info">{infotxt}</h3>
    }}"""

    let rssContainer = fmt"""{{
        <div id="rsscard" class="rsscard-container">{cards}</div>      
    }}"""
    let keywordContainer = fmt"""{{
        <div id="keywords">{$keywords}</div>      
    }}"""

    SSE(req): 
        patchElements(sse, infoContainer)
        patchElements(sse, rssContainer)
        patchElements(sse, keywordContainer)


proc handleUpdateClock(req: Request) =
    let userid = getSignal(req, "userid")
    var lastSHA1: string

    # /update-clock and RSSItems (Do not close the connection)
    var sse = req.respondSSE()
    while true:
        try:
            # Update Wall-Clock
            let msg = getWallClock(req)
            patchElements(sse, fmt"<h3 id='wallclock'>{msg}</h3>")

            # Show articles for logged in users
            if userid.len > 0:
                # Update Articles
                let formId = getSignal(req, "formId")
                if formId == "livefeed":
                    let cards = createLatestCards(MAXNEWS, userid)
                    let sha1 = generateSHA1(cards)
                    if sha1 != lastSHA1:
                        echo "New Articles"
                        lastSHA1 = sha1
                        patchElements(sse, cards)

            let msToNextMinute = 60000 - (now().second * 1000 + now().nanosecond div 1_000_000)
            sleep(msToNextMinute)
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
    router.post("/login", handleLogin)
    router.get("/logout", handleLogout)
    router.get("/livefeed", handleLiveFeed)
    router.get("/get-feeds", handleGetFeeds)

    router.post("/search", handleSearch)
    router.post("/select-feed", handleToggleFeed)
    router.post("/toggle-feed", handleToggleFeed)
    router.post("/toggle-feedgroup", handleToggleFeedGroup)

    router.get("/update-clock", handleUpdateClock)

    # Standard handlers
    router.get("/goto/**", handleGoto)
    router.notFoundHandler = serveStatic

    let (host, port) = ("localhost", 8080)
    let server = newServer(router)
    echo fmt"Simple SSE / Datastar server - Open http://{host}:{port} in your browser"

    server.serve(Port(port), host)
