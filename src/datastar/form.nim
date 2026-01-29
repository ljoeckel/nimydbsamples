## Run with: nim c -r examples/form.nim
## Then open http://localhost:8080 in your browser

import std/[asyncdispatch, asynchttpserver, json, strutils, strformat, times]
import std/[posix]
import datastar
import datastar/asynchttpserver as DATASTAR

const HTML = "html"

# Shutdown
proc handleSignal() {.noconv.} =
  echo "\nShutting down..."
  quit(0)
setControlCHook(handleSignal)

#-------------
# Handler's
#-------------

# Load /
proc handleIndex(req: Request) {.async.} =
    let indexHtml = readFile(HTML & "/form.html")
    await req.respond(Http200, indexHtml, newHttpHeaders([("Content-Type", "text/html")]))

# Load /style.css
proc handleStyle(req: Request) {.async.} =
    let css = readFile(HTML & "/style.css") 
    await req.respond(Http200, css, newHttpHeaders([("Content-Type", "text/css")]))

# Load /style.css
proc handleIco(req: Request) {.async.} =
  let css = readFile(HTML & "/favicon.ico") 
  await req.respond(Http200, css, newHttpHeaders([("Content-Type", "image/x-icon")]))

# Deliver /contact-sales
proc handleContactSales(req: Request) {.async.} =
  let indexHtml = readFile(HTML & "/sales.html")
  await req.respond(Http200, indexHtml, newHttpHeaders([("Content-Type", "text/html")]))

# Send the servertime to the client each second
proc handleServerEvents(req: Request) {.async.} =
    # connection is opened with <head data-init="@get('/server-events')">
    let sse = await req.newSSEGenerator(); defer: req.closeSSE()
    while true:
        let msg = fmt"<div id='events-message' class='formsuccess'>" & $now() & "</div>"
        await sse.patchElements(msg)
        await sleepAsync(1000)

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
  let signals = parseJson(req.body)
  let name = signals["name"].getStr()
  let email = signals["email"].getStr()
  let message = signals["message"].getStr()

  var msg: string
  if name.len > 0 and email.len > 0:
    msg = fmt"<div id='response-message' class='formsuccess'>Thank you '{name}', Data received!</div>"
  else:
    msg = "<div id='response-message' class='formerror'>Sorry! Invalid or missing data!</div>"

  let sse = await req.newSSEGenerator(); defer: req.closeSSE()
  await sse.patchElements(msg)
  # Show all signals in the Message Textfield
  await sse.patchSignals(%*{"message": $signals})


proc handler(req: Request) {.async.} =
  case req.url.path
  of "/": await handleIndex(req)
  of "/server-events": await handleServerEvents(req)
  of "/style.css": await handleStyle(req) # deliver CSS
  of "/favicon.ico": await handleIco(req) # deliver CSS
  of "/validate-email": await handleValidateEmail(req) # validate email field
  of "/submit-form": await handleSubmit(req) # receive formdata
  of "/contact-sales": await handleContactSales(req) # redirect to sales department
  else:
    await req.respond(Http404, "Not Found")

proc main() =
  let server = newAsyncHttpServer()
  echo "Server running at http://localhost:8080 (Ctrl+C to stop)"
  waitFor server.serve(Port(8080), handler)

main()
