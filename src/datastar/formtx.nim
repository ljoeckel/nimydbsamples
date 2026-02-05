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

# Shutdown
proc handleSignal() {.noconv.} =
    echo "\nShutting down..."
    quit(0)
setControlCHook(handleSignal)

#-------------
# Handler's
#-------------
proc handleStatic(req: Request, file: Path, ext: string) {.async.} =
    let path = Path("html/" & $file & ext)
    try:
        let data = readFile($path)
        await req.respond(Http200, data, newHttpHeaders([("Content-Type", getMimeType(ext))]))
    except:
        await req.respond(Http404, "<h1>File '" & $path & "' not found</h1>", newHttpHeaders([("Content-Type", "text/html")]))


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

type 
    SubmitMessage = object
        formid: string
        key: string
        name: string
        email: string
        message: string
        status: string


proc tableRow(key: string, msg: SubmitMessage): Future[string] {.async.} =
    result = """
        <tr data-on:click__stop="$selectedId={key}; @post('/api/select-row')" data-class="{selected: $selectedId==={key}}">
            <td>{formid}</td>
            <td>{key}</td>
            <td>{name}</td>
            <td>{email}</td>
            <td>{message}</td>
            <td>{status}</td>
            <td>
                <button data-on:click__stop="$selectedId={key}; @post('/api/delete-row')"><i class="bi bi-trash"></i></button>
                <button data-on:click__stop="$selectedId={key}; @post('/api/edit-row')"><i class="bi bi-alarm"></i></button>
            </td>
        </tr>
        """
    result = result.replace("{formid}", msg.formid)
    result = result.replace("{key}", msg.key)
    result = result.replace("{name}", msg.name)
    result = result.replace("{email}", msg.email)    
    result = result.replace("{message}", msg.message) 
    result = result.replace("{status}", msg.status) 

proc handleApiGetSubmits(req: Request) {.async.} =
    let sse = await req.newSSEGenerator(); defer: req.closeSSE()
    var rows = "<tbody id='user-table-body'>"
    for key in orderItr ^datastar:
        let name = getvar ^datastar(key, "name")
        if name.len > 0:
            var msg: SubmitMessage
            msg.formid = getvar ^datastar(key, "formID")
            msg.key = key
            msg.name = name
            msg.email = getvar ^datastar(key, "email")
            msg.message = getvar ^datastar(key, "message")
            msg.status = getvar ^datastar(key, "status")
            var row = await tableRow(key, msg)
            rows.add(row)
    rows.add("</tbody>")
    await sse.patchElements(rows)


# Display row data on the Admin page
proc handleApiSelectRow(req: Request) {.async.} =
    let signals = parseJson(req.body)
    let id = signals["selectedId"]
    let gbl = fmt"^datastar({id})"
    let name = getvar @gbl("name")
    let email = getvar @gbl("email")
    let message = getvar @gbl("message")
    let status = getvar @gbl("status")
    let sse = await req.newSSEGenerator(); defer: req.closeSSE()
    await sse.patchSignals(%*{
        "name": name,
        "email": email,
        "message": message,
        "status": status
    })

proc handleApiDeleteRow(req: Request) {.async.} =
    let signals = parseJson(req.body)
    let id = signals["selectedId"]
    dsl.kill: ^datastar(id)
    await handleApiGetSubmits(req)

proc handleApiEditRow(req: Request) {.async.} =
    let signals = parseJson(req.body)
    let id = signals["selectedId"]
    setvar: ^datastar(id,"status") = "Marked " & $now()
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


# Handle Form submit
proc handleSubmit(req: Request) {.async.} =
    let signals = parseJson(req.body)
    let email = signals["email"].getStr()
    let name = signals["name"].getStr()
    let message = signals["message"].getStr()
    let formID = signals["formID"].getStr()
    var msg:string
    if name.len > 0 and email.len > 0 and message.len > 0:
        # Save all signals in the database for each form submit
        # 1. Create the TX-Context (pass 'signals' to yottadb environment)
        # because YottaDB calls the Transaction callback in a separate thread via C
        for key in signals.keys:
            setvar: context(key) = strip($signals[key], chars={'"'})
        # 2. Run the Transaction
        let rc = Transaction:
            var id = parseInt(getvar(context("selectedId")))
            if id < 0:
                id = increment ^datastar("submits")
            for subs in queryItr context.keys:
                let key = subs[0]
                setvar: ^datastar(id, key) = getvar context(key)

        msg = "<div id='response-message' class='formsuccess'>Thank you '" & name & "', Data received!</div>"
    else:
        msg = "<div id='response-message' class='formerror'>Sorry! Invalid or missing data!</div>"
        
    # Update the Browser
    let sse = await req.newSSEGenerator(); defer: req.closeSSE()
    await sse.patchElements(msg)

    # Update table on Admin page    
    if formID == "Admin":
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
    case req.url.path
    of "/server-events": await handleServerEvents(req)
    of "/validate-email": await handleValidateEmail(req) # validate email field
    of "/submit-form": await handleSubmit(req) # receive formdata
    of "/clear-form": await handleClearForm(req)
    of "/api/submits": await handleApiGetSubmits(req)
    of "/api/select-row": await handleApiSelectRow(req)
    of "/api/delete-row": await handleApiDeleteRow(req)
    of "/api/edit-row": await handleApiEditRow(req)
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