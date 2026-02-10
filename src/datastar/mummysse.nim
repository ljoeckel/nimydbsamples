## Minimal "Datastar" PatchSignals example for Mummy
import ../../../mummyx/src/mummy, ../../../mummyx/src/mummy/routers
import std/[json, options, os, strutils, strformat]

const SLEEP_BEFORE_CLOSE = 10 # guessed value. if not sleeping then connection is closed before send is dispatched from worker queue

type
  ElementPatchMode* = enum
    Outer = "outer"
    Inner = "inner"
    Replace = "replace"
    Prepend = "prepend"
    Append = "append"
    Before = "before"
    After = "after"
    Remove = "remove"

# Datastar 'patchSignals'
proc patchSignals*(sse: SSEConnection, signals: JsonNode, onlyIfMissing = false,  eventId = "", retryDuration = 0, close = true) =
  var data: string
  if onlyIfMissing: data.add("onlyIfMissing true\n")
  data.add("signals " & $signals & "\n")

  var evt: SSEEvent
  evt.event = some("datastar-patch-signals")
  if eventId.len > 0: evt.id = some(eventId)
  if retryDuration > 0: evt.retry = some(retryDuration)
  evt.data = data
  sse.send(evt)


proc patchElements*(sse: SSEConnection, elements: string, selector = "", mode = Outer, useViewTransition = false, eventId = "", retryDuration = 0) =
  var lines: seq[string]

  if mode == Remove and elements.len == 0:
    # Special ordering for remove mode without elements
    if useViewTransition:
      # With useViewTransition: selector, mode, useViewTransition
      lines.add("selector " & selector)
      lines.add("mode " & $mode)
      lines.add("useViewTransition true")
    else:
      # Without useViewTransition: mode, selector
      lines.add("mode " & $mode)
      lines.add("selector " & selector)
  else:
    # Standard ordering: selector, mode, useViewTransition, elements
    if selector.len > 0:
      lines.add("selector " & selector)
    if mode != Outer:
      lines.add("mode " & $mode)
    if useViewTransition:
      lines.add("useViewTransition true")
    # Split multiline elements into separate data lines
    for elementLine in elements.split('\n'):
      lines.add("elements " & elementLine)

  var data: string
  for line in lines:
    data.add(line & "\n")

  var evt: SSEEvent
  evt.event = some("datastar-patch-elements")
  if eventId.len > 0: evt.id = some(eventId)
  if retryDuration > 0: evt.retry = some(retryDuration)
  evt.data = data
  sse.send(evt)


var count = 0
proc handleIncrement(request: Request) {.gcsafe.} =
    inc count
    let signals = %*{
        "value": count,
        "info": "Clicked " & $count & " times"
    }
    let sse = request.respondSSE()
    patchSignals(sse, signals)
    sleep(SLEEP_BEFORE_CLOSE)
    sse.close()

proc handleUpdateClock(request: Request) {.gcsafe.} =
  let sse = request.respondSSE()
  while true:
    let tm = $now()
    try:
      patchElements(sse, fmt"<h3 id='clock'>{tm}</h3>")
    except:
      echo "ERROR while patching Elements. Breaking /update-clock loop"
      break
    sleep(1000)
  sse.close()
  echo "Leaving handleUpdateClock"

proc handleRoot(request: Request) {.gcsafe.} =
  let html = """
<!DOCTYPE html>
<html>
<head data-init="@get('/update-clock')">
    <meta charset="UTF-8">
    <script type="module"
        src="https://cdn.jsdelivr.net/gh/starfederation/datastar@1.0.0-RC.7/bundles/datastar.js"></script>
</head>
<body data-signals="{value: 0, info: ''}">
    <h3 id="clock">00:00:00</h3>
    <button type="button" data-text="$value" data-on:click="@get('/increment')"></button>
    <input name="info" placeholder="Click button.." data-bind="info">
</body>
</html>
"""
  request.respond(200, @[("Content-Type", "text/html")], html)

   
proc main() =
  var router = Router()
  router.get("/", handleRoot)
  router.get("/increment", handleIncrement)
  router.get("/update-clock", handleUpdateClock)
  

  let server = newServer(router)
  echo "Simple SSE / Datastar server"
  echo "- Open http://192.168.1.159:8080 in your browser"
  server.serve(Port(8080), "192.168.1.159")

when isMainModule:
  main()