import std/strutils
import yottadb
import ydbutils
import tabbylj

import types

# Create one big 'Country' dataset which is created from
# 4 different csv datasets.
# Country is saved in YottaDB

type 
    Country2 = object
        country: string
        alpha2: string
        alpha3: string
        numeric: string

type 
    Country3 = object
        name: string
        alpha2: string
        alpha3: string
        country_code: string
        iso_3166_2: string
        region: string
        sub_region: string
        intermediate_region: string
        region_code: string
        sub_region_code: string
        intermediate_region_code: string

type
    World = object
        id: string
        alpha2: string
        alpha3: string
        ar: string
        bg: string
        br: string
        cs: string
        da: string
        de: string
        el: string
        en: string
        eo: string
        es: string
        et: string
        eu: string
        fa: string
        fi: string
        fr: string
        hr: string
        hu: string
        hy: string
        it: string
        ja: string
        ko: string
        lt: string
        nl: string
        no: string
        pl: string
        pt: string
        ro: string
        ru: string
        sk: string
        sl: string
        sr: string
        svv: string
        th: string
        trv: string
        ukv: string
        zhv: string
        zh_tw: string


func getInt(s: string): int =
    if s.isEmptyOrWhitespace(): 0 else: parseInt(s)

proc loadCsvData() =
    let csvData = readFile("data/countries.csv")
    let countries = csvData.fromCsv(seq[Country], separator = ",")
    for country in countries:
        saveObject(country.id, country)

    let data2 = readFile("data/ISO 3166-1 Country Codes.csv")
    for iso3 in data2.fromCsv(seq[Country2], separator = ","):
        var country = loadObject[Country](@[iso3.alpha2])
        if country.id == "":
            echo "No data for ", iso3
        else:
            country.iso3 = iso3.alpha3
            country.numeric = getInt(iso3.numeric)
            saveObject(country.id, country)

    let data3 = readFile("data/regions.csv")
    for region in data3.fromCsv(seq[Country3], separator = ","):
        var country = loadObject[Country](@[region.alpha2])
        if country.id == "":
            echo "No data for ", region
        else:
            country.subRegion = region.sub_region
            country.intermediateRegion = region.intermediate_region
            country.regionCode = getInt(region.region_code)
            country.subregionCode = getInt(region.sub_region_code)
            country.intermediateregionCode = getInt(region.intermediate_region_code)
            saveObject(country.id, country)

    let data4 = readFile("data/world.csv")
    for world in data4.fromCsv(seq[World], separator = ","):
        var country = loadObject[Country](@[toUpper(world.alpha2)])
        if country.id == "":
            echo "No data for ", toUpper(world.alpha2)
        else:
            country.lang_ar = world.ar
            country.lang_bg = world.bg
            country.lang_br = world.br
            country.lang_cs = world.cs
            country.lang_da = world.da
            country.lang_de = world.de
            country.lang_el = world.el
            country.lang_en = world.en
            country.lang_eo = world.eo
            country.lang_es = world.es
            country.lang_et = world.et
            country.lang_eu = world.eu
            country.lang_fa = world.fa
            country.lang_fi = world.fi
            country.lang_fr = world.fr
            country.lang_hr = world.hr
            country.lang_hu = world.hu
            country.lang_hy = world.hy
            country.lang_it = world.it
            country.lang_ja = world.ja
            country.lang_ko = world.ko
            country.lang_lt = world.lt
            country.lang_nl = world.nl
            country.lang_no = world.no
            country.lang_pl = world.pl
            country.lang_pt = world.pt
            country.lang_ro = world.ro
            country.lang_ru = world.ru
            country.lang_sk = world.sk
            country.lang_sl = world.sl
            country.lang_sr = world.sr
            country.lang_svv = world.svv
            country.lang_th = world.th
            country.lang_trv = world.trv
            country.lang_ukv = world.ukv
            country.lang_zhv = world.zhv
            country.lang_zh_tw = world.zh_tw
            saveObject(country.id, country)


proc listCountries() =
    for countryCode in OrderItr ^Country:
        echo loadObject[Country](@[countryCode])


if isMainModule:
    Kill: ^Country
    loadCsvData()
    #listCountries()