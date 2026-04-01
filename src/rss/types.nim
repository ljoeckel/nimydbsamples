import yottadb

type
    RowStatus* = enum 
        NEW = "New"
        EDIT = "Edit"
        MARKED = "Marked"

# type
#     Feed* = object of RootObj
#         title*: string
#         rssid*: string

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

    Country* = object
        id*: string
        country*: string
        demonym*: string
        iso2*: string
        iso3* {.INDEX: "id".}: string
        numeric*: int
        tld*: string
        currency*: string
        population*: int
        density*: float
        area*: float
        gdp*: int
        median_age*: float
        language*: string
        website*: string
        calling_code*: string
        driving_side*: string
        un_member*: bool
        religion*: string
        continent*: string
        subRegion*: string
        intermediateRegion*: string
        regionCode*: int
        subregionCode*: int
        intermediateregionCode*: int
        lang_ar*: string
        lang_bg*: string
        lang_br*: string
        lang_cs*: string
        lang_da*: string
        lang_de*: string
        lang_el*: string
        lang_en*: string
        lang_eo*: string
        lang_es*: string
        lang_et*: string
        lang_eu*: string
        lang_fa*: string
        lang_fi*: string
        lang_fr*: string
        lang_hr*: string
        lang_hu*: string
        lang_hy*: string
        lang_it*: string
        lang_ja*: string
        lang_ko*: string
        lang_lt*: string
        lang_nl*: string
        lang_no*: string
        lang_pl*: string
        lang_pt*: string
        lang_ro*: string
        lang_ru*: string
        lang_sk*: string
        lang_sl*: string
        lang_sr*: string
        lang_svv*: string
        lang_th*: string
        lang_trv*: string
        lang_ukv*: string
        lang_zhv*: string
        lang_zh_tw*: string
        time*: string