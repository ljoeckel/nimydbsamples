
import std/[strutils, strformat, tables, algorithm]
import std/[typetraits, enumerate]
import mummy, mummy/routers, mummy/datastar
import macros
import nimrss

proc getFeeds(): seq[Feed] =
    for feedId in OrderItr ^ConfigFeed:
        result.add(loadObject[ConfigFeed](feedId))


proc createTRFeed(feed: Feed): string =
    let id = feed.rssid
    let title = feed.title
    let enabled = feed.enabled
    # Construct a <TR><TD>Feed entry
    var dataclass = fmt"{{selected: $id==='{id}'}}"
    var markedclass = if enabled: "class='marked'" else: ""
    let checkbox = if enabled: "<i class='bi bi-check-square'></i>" else: "<i class='bi bi-square'></i></i>"
    
    result = fmt"""
        <tr {markedclass} id='Feed{id}' data-class="{dataclass}">
            <td></td>
            <td>
                <button data-on:click__stop="$id='{id}'; @post('/toggle-feed')">{checkbox}</button>
                &nbsp;
                <a href={feed.link} target='_blank'>{feed.title}</a>
            </td>
        </tr>
        """


proc handleGetFeeds(req: Request) {.gcsafe.} =
    let userid = getSignal(req, USERID)
    var userFeeds = loadObject[UserFeeds](userid)
    if userFeeds.feeds.len == 0: # init user feeds from base config
        userFeeds.userid = userid
        userFeeds.feeds = getFeeds()
        saveObject[UserFeeds](userid, userFeeds)
        echo fmt"Created UserFeeds for '{userid}', Number of feeds: {userFeeds.feeds.len}"

    # Sort by group / title
    let feeds = userFeeds.feeds.sortedByIt(toUpper(it.group) & toUpper(it.title))

    # Create the tbody
    var tbody = fmt"""<tbody id="feed-table">"""

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

    # create 'Group' row
    var oldGroup: string
    for feed in feeds:
        # Add Group header
        if oldGroup != feed.group:
            let class = "feedgroup-" & classTable[feed.group]
    
            var cbIcon: string
            let feedClass = classTable[feed.group]
            if feedClass == "full":
                cbIcon = "bi-check-square"
            elif feedClass == "partial":
                cbIcon = "bi-slash-square"
            else:
                cbIcon = "bi-square"

            var groupline = fmt"""
                <tr>
                    <td class='{class}' colspan='2'>
                    <button data-on:click__stop="$id='{feed.group}';@post('/toggle-feedgroup')"><i class="bi {cbIcon}"></i></button>
                    &nbsp;
                    {feed.group}
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
    let userid = getSignal(req, USERID)
    let id = getSignal(req, "id")
    let userFeeds = loadObject[UserFeeds](userid)

    # Update DB
    var init, flip: bool
    for idx, feed in enumerate(userFeeds.feeds):
        if id == "ALL":  # select / deselect all
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
    let userid = getSignal(req, USERID)
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


proc checkFeedConfiguration*(userid: string) =
    let dta = Data ^Feed(userid)
    if dta == 0:  # no feeds for the user
        echo "Create initial Feeds for user ", userid
        var userFeeds: UserFeeds
        userFeeds.userid = userid

        for feedid in OrderItr ^ConfigFeed:
            let feed = loadObject[ConfigFeed](feedid)
            userFeeds.feeds.add(feed)
        saveObject[UserFeeds](userid, userFeeds)


# Callback for router registration
proc register*(router: var Router) =
    router.get("/get-feeds", handleGetFeeds)
    router.post("/select-feed", handleToggleFeed)
    router.post("/toggle-feed", handleToggleFeed)
    router.post("/toggle-feedgroup", handleToggleFeedGroup)


# Create module instance
let wmFeedConfigModule* = WebModule(
    name: "wmFeedConfig",
    register: register
)