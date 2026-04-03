import yottadb

type
    RowStatus* = enum 
        NEW = "New"
        EDIT = "Edit"
        MARKED = "Marked"

type 
    Feed* = object of RootObj
        rssid*: string
        title*: string
        enabled*: bool = true

    UserFeeds* = object of RootObj
        userid*: string
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