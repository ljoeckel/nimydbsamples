import yottadb

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
        wordCounts*: seq[int]
        subscript*: seq[string]

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