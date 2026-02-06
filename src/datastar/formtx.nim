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
        id: int
        formId: string
        name: string
        password: string
        email: string
        message: string
        country: string
        plan: string
        terms: bool
        status: string
        time: string

# Shutdown
proc handleSignal() {.noconv.} =
    echo "\nShutting down..."
    quit(0)
setControlCHook(handleSignal)

# Serve static resources (html, css, etc.
proc handleStatic(req: Request, file: Path, ext: string) {.async.} =
    let path = Path("html/" & $file & ext)
    try:
        let data = readFile($path)
        await req.respond(Http200, data, newHttpHeaders([("Content-Type", getMimeType(ext))]))
    except:
        await req.respond(Http404, "<h1>File '" & $path & "' not found</h1>", newHttpHeaders([("Content-Type", "text/html")]))


# Validate E-Mail
proc handleValidateEmail(req: Request) {.async.} =
    echo $req.body
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


# Display row data on the Admin page
proc handleApiSelectRow(req: Request, id: string) {.async.} =
    var reg: Registration
    bingoser.load(@[id], reg)
    let sse = await req.newSSEGenerator(); defer: req.closeSSE()
    await sse.patchSignals(%*{
        "id": reg.id,
        "name": reg.name,
        "password": reg.password,
        "email": reg.email,
        "country": reg.country,
        "message": reg.message,
        "status": reg.status
    })


proc handleApiDeleteRow(req: Request, id: string) {.async.} =
    dsl.kill: ^Registration(id)
    await handleApiGetSubmits(req)


proc handleApiEditRow(req: Request, id: string) {.async.} =
    setvar: ^Registration(id,"status") = "Edited " & $now()
    await handleApiGetSubmits(req)

proc handleApiMarkRow(req: Request, id: string) {.async.} =
    setvar: ^Registration(id,"status") = "Marked " & $now()
    await handleApiGetSubmits(req)


# Send the servertime to the client each second
proc handleClearForm(req: Request) {.async.} =
    let sse = await req.newSSEGenerator(); defer: req.closeSSE()
    await sse.patchSignals(%*{
        "emailInvalid": false,
        "password": "",
        "country": "",
        "canSubmit": true,
        "terms": false,
        "menuOpen": false,
        "name": "",
        "email": "",
        "message": "",
        "status": "",
        "plan": "starter",
        "selectedId": -1
    })
    await sse.patchElements("<div id='response-message'></div>")


proc handleSubmit(req: Request) {.async.} =
    let signals = $(parseJson(req.body))
    let rc = Transaction(signals):
        let signals = $cast[cstring](param)
        var registration = parseJson(signals).to(Registration)
        echo "submit: registration=", registration
        # assign id to new Registration
        if registration.id == -1:
            registration.id = increment ^CNT("registration")
        # Save to DB
        bingoser.store(@[$(registration.id)], registration)

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


proc router(req: Request) {.async.} =
    var path, id: string
    if req.url.path.startsWith("/api/"):
        let ss = req.url.path.split("/:")
        path = ss[0]
        if ss.len >= 2:
            id = ss[1]
    else:
        path = req.url.path
    echo "path=", path, " id=", id

    case path
    of "/server-events": await handleServerEvents(req)
    of "/validate-email": await handleValidateEmail(req) # validate email field
    of "/submit-form": await handleSubmit(req) # receive formdata
    of "/clear-form": await handleClearForm(req)
    of "/api/submits": await handleApiGetSubmits(req)
    of "/api/select-row": await handleApiSelectRow(req, id)
    of "/api/delete-row": await handleApiDeleteRow(req, id)
    of "/api/edit-row": await handleApiEditRow(req, id)
    of "/api/mark-row": await handleApiMarkRow(req, id)
    else: # static
        var (dir, file, ext) = splitFile(Path(req.url.path))
        if $dir == "/" and ($file).len == 0: 
            file = Path("index")
            ext = ".html"

        if ext.len > 0:
            await handleStatic(req, file, ext)
        else:
            echo "Error: Not found: ", $req.url.path
            await req.respond(Http404, "<h1>Request '" & $req.url.path & "' not known</h1>", newHttpHeaders([("Content-Type", "text/html")]))


if isMainModule:
    initMimeTable()

    let server = newAsyncHttpServer()
    echo "Server running at http://localhost:8080 (Ctrl+C to stop)"
    waitFor server.serve(Port(8080), router)