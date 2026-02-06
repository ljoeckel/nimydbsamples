## Run in the src/datastar directory: nim c -r form.nim
## Then open http://localhost:8080 in your browser
## Save formdata with Transaction
## 
import std/[asyncdispatch, asynchttpserver, times, json, strutils, strformat, paths]
import std/[posix]
import datastar
import datastar/asynchttpserver as DATASTAR
import mimetypes
import yottadb

type 
    Registration = object of RootObj
        id: int = -1
        formId: string = "Form"
        name: string
        password: string
        email: string
        message: string
        country: string
        plan: string = "starter"
        terms: bool
        status: string
        time: string

# Shutdown
proc handleSignal() {.noconv.} =
    echo "\nShutting down..."
    quit(0)
setControlCHook(handleSignal)

# Serve static resources (html, css, etc.
proc handleStatic(req: Request, file: string, ext: string) {.async.} =
    let path = Path("html/" & file & ext)
    try:
        let data = readFile($path)
        await req.respond(Http200, data, newHttpHeaders([("Content-Type", getMimeType(ext))]))
    except:
        await req.respond(Http404, "<h1>File '" & $path & "' not found</h1>", newHttpHeaders([("Content-Type", "text/html")]))

# Reload /
proc reload(req: Request) {.async.} =
    let sse = await req.newSSEGenerator(); defer: req.closeSSE()
    await sse.executeScript("window.location.reload()")
  
# Forward to another page
proc forward(req: Request, url: string) {.async.} =
    let sse = await req.newSSEGenerator(); defer: req.closeSSE()
    let data = readFile(url)
    await sse.patchElements(data)

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

# Create a table row
proc tableRow(msg: Registration): Future[string] {.async.} =
    let dataclass = "{selected: $selectedId===" & $msg.id & "}"
    result = fmt"""
        <tr data-on:click__stop="$selectedId={msg.id}; @post('/api/select-row/:{msg.id}')" data-class="{dataclass}">
            <td>{msg.formId}</td>
            <td>{msg.id}</td>
            <td>{msg.name}</td>
            <td>{msg.email}</td>
            <td>{msg.message}</td>
            <td>{msg.status}</td>
            <td>
                <button data-on:click__stop="@post('/api/delete-row/:{msg.id}')"><i class="bi bi-trash"></i></button>
                <button data-on:click__stop="@post('/api/mark-row/:{msg.id}')"><i class="bi bi-alarm"></i></button>
                <button data-on:click__stop="@post('/api/edit-row/:{msg.id}')"><i class="bi bi-pencil"></i></button>
            </td>
        </tr>
        """

# Load Tabledata
proc handleApiGetSubmits(req: Request) {.async.} =
    let sse = await req.newSSEGenerator(); defer: req.closeSSE()
    var rows = "<tbody id='user-table-body'>"
    for id in orderItr ^Registration:
        var registration: Registration
        bingoser.load(@[id], registration)
        rows.add(await tableRow(registration))
    rows.add("</tbody>")
    await sse.patchElements(rows)

# Select Row and show data in the form
proc handleApiSelectRow(req: Request, id: string) {.async.} =
    var reg = Registration()
    bingoser.load(@[id], reg) # load from DB
    let sse = await req.newSSEGenerator(); defer: req.closeSSE()
    await sse.patchSignals(%reg) # json

# Delete Row
proc handleApiDeleteRow(req: Request, id: string) {.async.} =
    dsl.kill: ^Registration(id)
    await handleApiGetSubmits(req)

# Edit Row
proc handleApiEditRow(req: Request, id: string) {.async.} =
    setvar: ^Registration(id,"status") = "Edited " & $now()
    await forward(req, "html/form.html")

# Mark Row (Update Timestamp)
proc handleApiMarkRow(req: Request, id: string) {.async.} =
    setvar: ^Registration(id,"status") = "Marked " & $now()
    await handleApiGetSubmits(req)

# Reset the form, clear response-message on form
proc handleClearForm(req: Request) {.async.} =
    let sse = await req.newSSEGenerator(); defer: req.closeSSE()
    var reg = Registration()
    await sse.patchSignals(%reg) # json clear Registration fields
    await sse.patchSignals(%*{ # clear technical fields
        "emailInvalid": false,
        "canSubmit": true
    })
    await sse.patchElements("<div id='response-message'></div>") # clear response-message

# Save Registration
proc handleSubmit(req: Request) {.async.} =
    let signals = $(parseJson(req.body))
    let rc = Transaction(signals):
        let signals = $cast[cstring](param)
        var reg = parseJson(signals).to(Registration)
        # assign id to new Registration
        if reg.id == -1:
            reg.id = increment ^CNT("registration")
        # Save to DB
        bingoser.store(@[$(reg.id)], reg)

    if rc == YDB_OK:
        let sse = await req.newSSEGenerator(); defer: req.closeSSE()
        await sse.patchElements("<div id='response-message' class='formsuccess'>Thank you,data received!</div>")
        await handleApiGetSubmits(req)

# Send the servertime to the client each second
proc handleServerEvents(req: Request) {.async.} =
    # connection is opened with <head data-init="@get('/server-events')">
    let sse = await req.newSSEGenerator(); defer: req.closeSSE()
    while true:
        await sse.patchElements("<h3 id='clock'>" & $now() & "</h3>")
        await sse.patchSignals(%*{"time": $now()})
        await sleepAsync(1000)

# Route requests (static, /api, /others)
proc router(req: Request) {.async.} =
    var path: string
    # handle /api/xxxx/<id>
    if req.url.path.startsWith("/api/"):
        let ss = req.url.path.split("/:")
        path = ss[0]
        let id = if ss.len >= 2: ss[1] else: ""
        case path
        of "/api/submits": await handleApiGetSubmits(req)
        of "/api/select-row": await handleApiSelectRow(req, id)
        of "/api/delete-row": await handleApiDeleteRow(req, id)
        of "/api/edit-row": await handleApiEditRow(req, id)
        of "/api/mark-row": await handleApiMarkRow(req, id)
        return
    else:
        path = req.url.path

    case path
    of "/server-events": await handleServerEvents(req)
    of "/validate-email": await handleValidateEmail(req) # validate email field
    of "/submit-form": await handleSubmit(req) # get formdata and save in DB
    of "/clear-form": await handleClearForm(req)
    else: # static
        var (dir, file, ext) = splitFile(Path(req.url.path))
        if $dir == "/" and ($file).len == 0: 
            file = Path("index")
            ext = ".html"

        if not ext.isEmptyOrWhitespace:
            await handleStatic(req, $file, ext)
        else:
            await req.respond(Http404, "<h1>Request '" & $req.url.path & "' not known</h1>", newHttpHeaders([("Content-Type", "text/html")]))


if isMainModule:
    initMimeTable()

    let server = newAsyncHttpServer()
    echo "Server running at http://localhost:8080 (Ctrl+C to stop)"
    waitFor server.serve(Port(8080), router)