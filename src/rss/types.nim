import yottadb

type 
    Feed* = object of RootObj
        rssid*: string
        group*: string
        title*: string
        enabled*: bool = true

    UserFeeds* = object of RootObj
        userid*: string
        group*: string
        feeds*: seq[Feed]

type
    Registration* = object of RootObj
        id*: string
        name*: string
        password*: string
        email* {.INDEX: "id".} : string
        message*: string
        country* {.INDEX: "id".} : string
        plan* {.INDEX: "id".} : string = "starter"
        terms* {.INDEX: "id".} : bool
        status* {.INDEX: "id".} : string
        time*: string