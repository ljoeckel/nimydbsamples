## Run in the src/datastar directory: nim c -r form.nim
## Then open http://localhost:8080 in your browser
## Save formdata with Transaction
## 
import std/[asyncdispatch, asynchttpserver, times, json, strutils, strformat, paths, uri]
import datastarutils
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
proc shutdown() {.noconv.} =
    echo "\nShutting down..."
    quit(0)
setControlCHook(shutdown)

# Validate E-Mail
proc validateEmail(req: Request) {.async.} =
    let signals = parseJson(req.body)
    let email = signals["email"].getStr()
    let isInvalid = email.len > 0 and not email.contains("@")
    await patchSignals(req, %*{
        "emailInvalid": isInvalid,
        "canSubmit": not isInvalid
    })

# Create a table row
proc newTableRow(msg: Registration): Future[string] {.async.} =
    let marked = if msg.status.startsWith("Marked"): "<button>✅</button>" else: "" 
    let markbtn = fmt"<button data-on:click__stop=""@post('/api/mark-row/:{msg.id}')""><i class='bi bi-alarm'></i></button>"
    let marker = if marked == "": markbtn else: marked
    let dataclass = "{selected: $id===" & $msg.id & "}"
    result = fmt"""
        <tr data-on:click__stop="$id={msg.id}; @post('/api/select-row/:{msg.id}')" data-class="{dataclass}">
            <td>{msg.formId}</td>
            <td>{msg.id}</td>
            <td>{msg.name}</td>
            <td>{msg.email}</td>
            <td>{msg.message}</td>
            <td>{msg.status}</td>
            <td>
                <button data-on:click__stop="@post('/api/delete-row/:{msg.id}')"><i class="bi bi-trash"></i></button>
                {marker}
                <button data-on:click__stop="@post('/api/edit-row/:{msg.id}')"><i class="bi bi-pencil"></i></button>
            </td>
        </tr>
        """

# Load Tabledata
proc getTableRows(req: Request) {.async.} =
    var signals: string
    # Handle Post and Get requests
    if req.url.query.isEmptyOrWhitespace:  # POST
        signals = req.body 
    else: 
        let encodedValue = req.url.query.split('=')[1]
        signals = decodeUrl(encodedValue)

    let data = parseJson(signals)
    # Zugriff auf einzelne Felder
    echo "Max Rows: ", data["maxrows"].getInt()
    echo "page: ", data["page"].getInt()

    var rows = "<tbody id='user-table-body'>"
    for id in orderItr ^Registration:
        var registration: Registration
        bingoser.load(@[id], registration)
        rows.add(await newTableRow(registration))
    rows.add("</tbody>")
    await patchElements(req, rows)

# Select Row and show data in the form
proc selectRow(req: Request, id: string, close: bool = true) {.async.} =
    var reg = Registration()
    bingoser.load(@[id], reg) # load from DB
    await patchSignals(req, %reg, close) # update gui with attributes from registration

# Delete Row
proc deleteRow(req: Request, id: string) {.async.} =
    dsl.kill: ^Registration(id)
    await getTableRows(req)

# Edit Row
proc editRow(req: Request, id: string) {.async.} =
    setvar: ^Registration(id,"status") = "Edited " & $now()
    await patchSignals(req, %*{ # clear technical fields
        "emailInvalid": false,
        "canSubmit": true,
        "id": id,
        "page": 1
    }, close = false)
    await selectRow(req, id, close = false)
    await forward(req, "html/form.html")

# Mark Row (Update Timestamp)
proc markRow(req: Request, id: string) {.async.} =
    setvar: ^Registration(id,"status") = "Marked " & $now()
    await getTableRows(req)

# Reset the form, clear response-message on form
proc clearForm(req: Request) {.async.} =
    var reg = Registration()
    await patchSignals(req, %reg, close=false) # json clear Registration fields
    await patchSignals(req, %*{ # clear technical fields
        "emailInvalid": false,
        "canSubmit": true,
        "id": -1
    }, close=false)
    await patchElements(req, "<div id='response-message'></div>") # clear response-message

# Save Registration
proc submit(req: Request) {.async.} =
    let signals = $(parseJson(req.body))
    let rc = Transaction(signals):
        let signals = $cast[cstring](param)
        var reg = parseJson(signals).to(Registration)
        if reg.id == -1: # assign new id to new Registration
            reg.id = increment ^CNT("registration")
        bingoser.store(@[$(reg.id)], reg) # Save to DB

    if rc == YDB_OK:
        await patchElements(req, "<div id='response-message' class='formsuccess'>Thank you,data received!</div>", close=false)
        await getTableRows(req)

# Route requests (static, /api, /others)
proc router(req: Request) {.async.} =
    var path: string
    if req.url.path.startsWith("/api/"):     #  /api/xxxx/<id>
        let ss = req.url.path.split("/:")
        path = ss[0]
        let id = if ss.len >= 2: ss[1] else: ""
        case path
        of "/api/submits": await getTableRows(req)
        of "/api/select-row": await selectRow(req, id)
        of "/api/delete-row": await deleteRow(req, id)
        of "/api/edit-row": await editRow(req, id)
        of "/api/mark-row": await markRow(req, id)
        return
    else:
        path = req.url.path

    case path
    of "/update-clock": await updateClock(req)
    of "/validate-email": await validateEmail(req) # validate email field
    of "/submit-form": await submit(req) # get formdata and save in DB
    of "/clear-form": await clearForm(req)
    else: # static
        var (dir, file, ext) = splitFile(Path(req.url.path))
        if $dir == "/" and ($file).len == 0: 
            file = Path("index")
            ext = ".html"

        if not ext.isEmptyOrWhitespace:
            await serveStatic(req, $file, ext)
        else:
            await req.respond(Http404, "<h1>Request '" & $req.url.path & "' not known</h1>", newHttpHeaders([("Content-Type", "text/html")]))


if isMainModule:
    initMimeTable()

    let server = newAsyncHttpServer()
    echo "Server running at http://localhost:8080 (Ctrl+C to stop)"
    waitFor server.serve(Port(8080), router)