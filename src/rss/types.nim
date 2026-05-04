import options
import yottadb
import mummy, mummy/routers

const
    MIN_KEYWORD_LEN* = 2
    MAX_SEARCH_RESULTS* = 1000
    MAX_CARDS* = 100
    DEFAULT_LANGUAGE* = "EN"

type
    RouteHandler* = proc (req: Request)
    WebModule* = ref object
        name*: string
        register*: proc (router: var Router)

    Feed* = object of RootObj
        rssid*: string
        group*: string
        link*: string
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
        ByTodayDescending,
        ByTodayAscending,
        ByTimeDescending,
        ByTimeAscending,
        ByRelevanceDescending,
        ByRelevanceAscending

    DBStats* = object
        ordercnt*: int
        querycnt*: int
        keylen*: int
        valuelen*: int
        minkey*: int = 999
        minvalue*: int = 999
        maxkey*: int
        maxvalue*: int
        global*: string


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


# Create the RSSATOM types.
type
  FeedType* = enum
    RSSv2,Atom

  RSS* = object
    id*: Option[string] #atom
    title*: Option[string]
    link*: Option[string]
    description*: Option[string]
    language*: Option[string]
    copyright*: Option[string]
    managingEditor*: Option[string]
    webMaster*: Option[string]
    pubDate*: Option[string]
    lastBuildDate*: Option[string]
    category*: seq[string]
    generator*: Option[string]
    docs*: Option[string]
    cloud*: RSSCloud
    ttl*: Option[string]
    image*: RSSImage
    rating*: Option[string]
    textInput*: RSSTextInput
    skipHours*: seq[string]
    skipDays*: seq[string]
    items*: seq[RSSItem]
    author*: Author
    feedType*: FeedType

  RSSEnclosure* = object
    url*: string
    length*: string
    enclosureType*: string

  RSSCloud* = object
    domain*: Option[string]
    port*: Option[string]
    path*: Option[string]
    registerProcedure*: Option[string]
    protocol*: Option[string]

  RSSImage* = object
    url*: Option[string]
    title*: Option[string]
    link*: Option[string]
    width*: Option[string]
    height*: Option[string]
    description*: Option[string]

  RSSTextInput* = object
    title*: Option[string]
    description*: Option[string]
    name*: Option[string]
    link*: Option[string]

  RSSItem* = object
    idxref* {.INDEX: "feedId".} : string
    title*: Option[string]
    link*: Option[string]
    description*: Option[string]
    content*: Option[string]
    author*: Author
    category*: seq[string]
    comments*: Option[string]
    enclosure*: RSSEnclosure
    guid* {.INDEX: "idxref".} : Option[string]
    pubDate* {.INDEX: "idxref".} : Option[string]
    sourceUrl*: Option[string]
    sourceText*: Option[string]
    updated*: Option[string] #Atom
    feedId*: Option[string]
    topic*: Option[string]
    keywords*: seq[string]

  Author* = object
    name*: Option[string]
    email*: Option[string]
    uri*: Option[string]
    #legacyRss*: Option[string] #RSSV2