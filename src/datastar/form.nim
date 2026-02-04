## Run in the src/datastar directory: nim c -r form.nim
## Then open http://localhost:8080 in your browser

import std/[asyncdispatch, asynchttpserver, times, json, strutils]
import std/[posix]
import datastar
import datastar/asynchttpserver as DATASTAR
import yottadb

const HTML = "html"

# Shutdown
proc handleSignal() {.noconv.} =
    echo "\nShutting down..."
    quit(0)
setControlCHook(handleSignal)

#-------------
# Handler's
#-------------
proc handleStatic(req: Request, url: string, content: string) {.async.} =
    let data = readFile(HTML & "/" & url)
    await req.respond(Http200, data, newHttpHeaders([("Content-Type", content)]))

# Reload /
proc reload(req: Request) {.async.} =
    let sse = await req.newSSEGenerator(); defer: req.closeSSE()
    await sse.executeScript("window.location.reload()")

# Validate E-Mail
proc handleValidateEmail(req: Request) {.async.} =
    let signals = parseJson(req.body)
    let email = signals["email"].getStr()
    let isInvalid = email.len > 0 and not email.contains("@")
    let sse = await req.newSSEGenerator(); defer: req.closeSSE()
    await sse.patchSignals(%*{
        "emailInvalid": isInvalid,
        "canSubmit": not isInvalid
    })

# Handle Form submit
proc handleSubmit(req: Request) {.async.} =
    var msg:string
    let signals = parseJson(req.body)
    let email = signals["email"].getStr()
    let name = signals["name"].getStr()
    if name.len > 0 and email.len > 0:
        # Save all signals in the database for each form submit
        let id = increment ^datastar("submits")
        for key in signals.keys:
            let str = strip($signals[key], chars={'"'})
            setvar: ^datastar(id, key) = str

        msg = "<div id='response-message' class='formsuccess'>Thank you '" & name & "', Data received!</div>"
    else:
        msg = "<div id='response-message' class='formerror'>Sorry! Invalid or missing data!</div>"
        
    # Update the Browser
    let sse = await req.newSSEGenerator(); defer: req.closeSSE()
    await sse.patchElements(msg)
    # Show all signals in the Message Textfield
    await sse.patchSignals(%*{"message": $signals})

# Send the servertime to the client each second
proc handleServerEvents(req: Request) {.async.} =
    # connection is opened with <head data-init="@get('/server-events')">
    let sse = await req.newSSEGenerator(); defer: req.closeSSE()
    while true:
        let currentDateTime = $now()
        await sse.patchElements("<div id='clock'>" & currentDateTime & "</div>")
        await sse.patchSignals(%*{"time": currentDateTime})
        await sleepAsync(1000)


proc router(req: Request) {.async.} =
    case req.url.path
    of "/": await handleStatic(req, "form.html", "text/html") #await handleIndex(req)
    of "/favicon.ico": await handleStatic(req, "favicon.ico", "image/x-icon") #await handleIco(req) # deliver CSS
    of "/style.css": await handleStatic(req, "style.css", "text/css") #await handleStyle(req) # deliver CSS
    of "/contact-sales": await handleStatic(req, "sales.html", "text/html") #await handleContactSales(req) # redirect to sales department
    of "/server-events": await handleServerEvents(req)
    of "/validate-email": await handleValidateEmail(req) # validate email field
    of "/submit-form": await handleSubmit(req) # receive formdata
    else:
        echo "NOT FOUND: req.url=", req.url
        await req.respond(Http404, "Not Found")

if isMainModule:
    let server = newAsyncHttpServer()
    echo "Server running at http://localhost:8080 (Ctrl+C to stop)"
    waitFor server.serve(Port(8080), router)