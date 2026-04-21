## Run 'nimble demo'

import std/[os, times, json, strutils, strformat, tables, algorithm, sequtils, sugar]
import std/[options, typetraits, enumerate]
import std/[sha1, httpclient]
import mummy, mummy/routers, mummy/datastar
import macros
import nimrss



proc createRSSItemCard*(item: RSSItem): string =
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
    
    result = fmt"""
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

proc createRSSItemList*(item: RSSItem): string =
    let title = getOption(item.title)
    let link = getOption(item.link)

    var pubDate: string
    try: 
        let dt = getOption(item.pubDate)
        let fu = parseInt(dt).fromUnix()
        pubDate = fu.format("dd.MM.yyyy HH:mm")
    except:
         pubDate = "01.01.1970 00:00"

    result = fmt"""
        <div class="rsslist">
            <div class="rsscard-title"> <a target="_blank" href="{link}"> {title}</a> </div>
            <div class="rsscard-footer">
                <p class="rsspubdate"> {pubDate} / {item.idxref} </p>
            </div>
        </div>
        """


proc createLatestCards*(max: int, userid: string): (string, int) =
    let userFeeds = loadObject[UserFeeds](userid)
   
    var cards: string
    var items: int
    for rssItem in getLatestRSSItems(max, userFeeds.feeds):
        # produce cards for output
        cards.add(createRSSItemCard(rssItem))
        inc items

    let container = fmt"""{{
        <div id="rsscard" class="rsscard-container">{cards}</div>      
    }}"""

    return (container, items)


proc handleLiveFeed*(req: Request) =
    echo "handleLiveFeed"
    let userid = getSignal(req, USERID)
    let wallclock = getWallClock(userid)
    let keywordContainer = fmt"""{{<div id="keywords"></div>}}"""

    SSE(req):
        patchElements(sse, fmt"<h3 id='wallclock'>{wallclock}</h3>")
        patchElements(sse, keywordContainer) # clear keyword search result
        var cardsContent: string
        var cardsCount: int
        var info = meassure:
            (cardsContent, cardsCount) = createLatestCards(MAXNEWS, userid)
        let articles = fmt"{cardsCount} articles"
        let infotxt = if articles.len > 0: fmt"{articles} in {info}" else: fmt"Fetch in {info}"
        let infoContainer = fmt"""{{<h3 id="info">{infotxt}</h3>}}"""

        patchElements(sse, cardsContent)
        patchElements(sse, infoContainer)


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


# Callback for router registration
proc register*(router: var Router) =
    echo "register /livefeed"
    router.get("/livefeed", handleLiveFeed)


# Create module instance
let wmRSSCardsModule* = WebModule(
    name: "wmRSSCards",
    register: register
)