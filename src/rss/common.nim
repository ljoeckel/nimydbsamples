import std/[os, times, json, strutils, strformat, tables]
import std/[options, typetraits]
import std/[httpclient]
import checksums/sha1
import mummy, mummy/routers, mummy/datastar
import macros
import yottadb


const
    MAXNEWS* = 100 # How many news to show in 'latest'
    HTML_DIR* = "html/"
    USERID* = "userid"


template meassure*(body: untyped): auto =
    let t0 = getTime()
    body
    let td = (getTime() - t0).inMicroseconds
    if td > 1000: $(td div 1000) & "ms."
    else: $td & " µs."


template SSE*(req: Request, body: untyped) =
    var sse {.inject.} = req.respondSSE() # sse for body
    defer: sse.close()
    body

func stripSignal*(signal: string): string =
    result = strip(signal)
    if result.startsWith("\"") and result.endsWith("\""): # Remove "xxxx" -> xxxx
        result = result[1..^2]

proc patch*(sse: SSEConnection, signals: JsonNode) =
    let dsSignals = getSignals(sse)
    let userid = if USERID in dsSignals: dsSignals[USERID].getStr() else: ""

    patchSignals(sse, signals)
    for key in signals.keys:
        Set: ^Session(userid, key) = stripSignal($signals[key])


proc getSignal*(userid: string, key: string): string =
    result = Get ^Session(userid, key)

proc getSignals*(userid: string): seq[(string, string)] =
    for k,v in OrderItr ^Session(userid,"").kv:
        result.add((k,v))

proc getSignal*(req: Request, key: string): string = 
    let signals = getSignals(req)
    let userid = if USERID in signals: stripSignal($signals[USERID]) else: ""
    for k, v in signals.pairs:
        Set: ^Session(userid, k) = stripSignal($v)
    getSignal(userid, key)



proc handleGoto*(req: Request) =
    # process menu links g.E. <a href="#form" data-on:click="$menuOpen = false; @get('goto/form.html')">Registration</a>
    let page = req.path.split("/goto/")[1]
    echo "handelGoto page=", page
    SSE(req):
        forward(sse, HTML_DIR & page)

proc getWallClock*(userid: string): string =
    let nowTime = now().format("dd.MM.yyyy - HH:mm")
    result = fmt"{userid} / {nowTime}"
