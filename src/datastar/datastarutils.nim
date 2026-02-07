import std/[asyncdispatch, asynchttpserver, times, json, strutils, paths]
import datastar
import datastar/asynchttpserver # as DATASTAR
import mimetypes

proc executeScript*(req: Request, script: string, close: bool = true) {.async.} =
    let sse = await req.newSSEGenerator()
    await sse.executeScript(script)
    if close: req.closeSSE()

proc patchElements*(req: Request, elements: string, close: bool = true) {.async.} =
    let sse = await req.newSSEGenerator()
    await sse.patchElements(elements)
    if close: req.closeSSE()        

proc patchSignals*(req: Request, signals: JsonNode, close: bool = true) {.async.} =
    let sse = await req.newSSEGenerator()
    await sse.patchSignals(signals)
    if close: req.closeSSE()        


# Serve static resources (html, css, etc.
proc serveStatic*(req: Request, file: string, ext: string) {.async.} =
    let path = Path("html/" & file & ext)
    try:
        let data = readFile($path)
        await req.respond(Http200, data, newHttpHeaders([("Content-Type", getMimeType(ext))]))
    except:
        await req.respond(Http404, "<h1>File '" & $path & "' not found</h1>", newHttpHeaders([("Content-Type", "text/html")]))

# Reload /
proc reload*(req: Request) {.async.} =
    executeScript(req, "window.location.reload()")
  
# Forward to another page
proc forward*(req: Request, url: string) {.async.} =
    let data = readFile(url)
    await patchElements(req, data)

# Send the servertime to the client each second
proc updateClock*(req: Request) {.async.} =
    # connection stays open. Initialized with <head data-init="@get('/update-clock')">
    while true:
        await patchElements(req, "<h3 id='clock'>" & $now() & "</h3>", close=false)
        await patchSignals(req, %*{"time": $now()}, close=false)
        await sleepAsync(1000)
