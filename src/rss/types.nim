import yottadb
import mummy, mummy/routers, mummy/datastar

var
    MIN_KEYWORD_LEN* = 2
    MAX_SEARCH_RESULTS* = 1000
    MAX_CARDS* = 100

type 
    Feed* = object of RootObj
        rssid*: string
        group*: string
        title*: string
        description*: string
        lastAccess*: string
        lastError*: string
        enabled*: bool = true

    ConfigFeed* = object of Feed
    
    UserFeeds* = object of RootObj
        userid*: string
        group*: string
        feeds*: seq[Feed]

    TimeSearchEntry* = object of RootObj
        time*: int
        wordCount*: int
        subscript*: seq[string]

    SortBy* = enum 
        ByTimeDescending,
        ByTimeAscending,
        ByRelevanceDescending,
        ByRelevanceAscending



type
  RouteHandler* = proc (req: Request)
  #RouteHandler* = proc (req: Request) {.gcsafe, raises: [].}
  WebModule* = ref object
    name*: string
    register*: proc (router: var Router)
    #register*: proc (router: var Router) {.gcsafe, raises: [].}

type
    Registration* = object of RootObj
        id*: string
        name*: string
        password*: string
        email* {.INDEX: "id".} : string
        message*: string
        country* {.INDEX: "id".} : string
        plan* {.INDEX: "id".} : string = "starter"
        status* {.INDEX: "id".} : string
        time*: string
        terms* {.INDEX: "id".} : bool