import std/strutils
import yottadb
import ydbutils
import tabbylj

import types



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
        saveObject(@[country.id], country)

    let data2 = readFile("data/ISO 3166-1 Country Codes.csv")
    for iso3 in data2.fromCsv(seq[Country2], separator = ","):
        var country = loadObject[Country](@[iso3.alpha2])
        if country.id == "":
            echo "No data for ", iso3
        else:
            country.iso3 = iso3.alpha3
            country.numeric = getInt(iso3.numeric)
            saveObject(@[country.id], country)

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
            saveObject(@[country.id], country)

    let data4 = readFile("data/world.csv")
    for world in data4.fromCsv(seq[World], separator = ","):
        var country = loadObject[Country](@[toUpper(world.alpha2)])
        if country.id == "":
            echo "No data for ", toUpper(world.alpha2)
        else:
            country.ar = world.ar
            country.bg = world.bg
            country.br = world.br
            country.cs = world.cs
            country.da = world.da
            country.de = world.de
            country.el = world.el
            country.en = world.en
            country.eo = world.eo
            country.es = world.es
            country.et = world.et
            country.eu = world.eu
            country.fa = world.fa
            country.fi = world.fi
            country.fr = world.fr
            country.hr = world.hr
            country.hu = world.hu
            country.hy = world.hy
            country.it = world.it
            country.ja = world.ja
            country.ko = world.ko
            country.lt = world.lt
            country.nl = world.nl
            country.no = world.no
            country.pl = world.pl
            country.pt = world.pt
            country.ro = world.ro
            country.ru = world.ru
            country.sk = world.sk
            country.sl = world.sl
            country.sr = world.sr
            country.svv = world.svv
            country.th = world.th
            country.trv = world.trv
            country.ukv = world.ukv
            country.zhv = world.zhv
            country.zh_tw = world.zh_tw
            saveObject(@[country.id], country)


proc listCountries() =
    for countryCode in OrderItr ^Country:
        echo loadObject[Country](@[countryCode])


if isMainModule:
    for global in getGlobals():
        if global.startsWith("^Country"):
            echo "delete global ", global
            deleteGlobal(global)
    loadCsvData()
    listCountries()