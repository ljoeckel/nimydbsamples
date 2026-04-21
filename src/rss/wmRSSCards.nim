import std/[times, strutils, strformat]
import std/[options, typetraits, enumerate]
import mummy, mummy/routers, mummy/datastar
import nimrss

proc pubDate(item: RSSItem): string =
    try: 
        let dt = getOption(item.pubDate)
        let fu = parseInt(dt).fromUnix()
        result = fu.format("dd.MM.yyyy HH:mm")
    except:
         result = "01.01.1970 00:00"


proc feedData(item: RSSItem): (string, string) =
    let id = item.idxref.split(',')[0]
    let rssImage = loadObject[RSSImage](id)

    var feedTitle, feedLink: string
    if rssImage.url.isSome():
        feedTitle = if rssImage.title.isSome: getOption(rssImage.title) else: getOption(item.title)
        feedLink = getOption(rssImage.link)
    else:
        feedTitle = Get ^RSS(id, "title")
        feedLink = Get ^RSS(id, "link")
    
    return (feedTitle, feedLink)


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

    let feedId = getOption(item.feedId)
    let (feedTitle, feedLink) = feedData(item)
    let divimg = fmt"""
        <a target='_blank' href={feedLink} class='footer-link'>
        <span class='feed-title'>{feedTitle}</span></a>
        """
    
    result = fmt"""
        <div class='rsscard'>
            <div class='rsscard-tags'>
                {topic}
                {category}
                {keywords}
            </div>
            <div class='rsscard-title'> <a target='_blank' href='{link}'> {title}</a> </div>
            <p class='rsscard-text'> <a target='_blank' href='{link}'> {description}</a> </p>
            <div class='rsscard-footer'>
                <p>{divimg}</p>
                <p class='rsspubdate'> {pubDate(item)} / {item.idxref} / {feedId}</p>
            </div>
        </div>
        """

proc createRSSItemList*(item: RSSItem): string =
    let title = getOption(item.title)
    let link = getOption(item.link)
    let (feedTitle, feedLink) = feedData(item)
    let divimg = fmt"<a target='_blank' href={feedLink}><span>{feedTitle}</span></a>"

    result = fmt"""
        <div class='rsscard-title'>
            <a target='_blank' href='{link}'> {title}</a>
            <p class='rsspubdate'> {pubDate(item)} / {item.idxref} / {divimg} </p>
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


# Callback for router registration
proc register*(router: var Router) =
    router.get("/livefeed", handleLiveFeed)


# Create module instance
let wmRSSCardsModule* = WebModule(
    name: "wmRSSCards",
    register: register
)