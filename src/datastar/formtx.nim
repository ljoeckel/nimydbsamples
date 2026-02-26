## Run 'nimble demo'

import std/[os, times, json, strutils, strformat]
import mummy, mummy/routers, mummy/datastar
import yottadb
import macros


type
    RowStatus = enum 
        EDIT = "Edit"
        MARKED = "Marked"

    Country = object of RootObj
        id: int = -1
        cname: string
        ccode: string
        cprefix: string

    Registration = object of RootObj
        id: int = -1
        formId: string = "form"
        name: string
        password: string
        email {.INDEX: "id".} : string
        message: string
        country {.INDEX: "id".} : string
        plan: string = "starter"
        terms : bool
        status: string
        time: string


proc clearFormFields(sse: SSEConnection) =
    # create empty Registration
    var reg = Registration()
    patchSignals(sse, %reg) # json clear Registration fields
    var country = Country()
    patchSignals(sse, %country)


proc clearTechFields(sse: SSEConnection) =
    patchSignals(sse, %*{ # clear technical fields
        "lastFormId": "",
        "emailInvalid": false,
        "canSubmit": true,
        "id": -1,
        "page": 1
    })
    patchElements(sse, "<div id='response-message'></div>") # clear response-message


# Validate E-Mail
proc validateEmail(req: Request) =
    let signals = parseJson(req.body)
    let id = signals["id"].getInt()
    let email = signals["email"].getStr()
    if email != "":
        let isInvalid = 0 < Data ^RegistrationEMAIL(email)
        var sse = req.respondSSE(); defer: sse.close()
        patchSignals(sse, %*{
            "emailInvalid": isInvalid,
            "canSubmit": not isInvalid
        })


proc getRowId(req: Request):int =
    let signals = getSignals(req)
    result = signals["id"].getInt()

# Create a table row
proc newTableRow(msg: Registration): string =
    let marked = if msg.status.startsWith("Marked"): "<button>✅</button>" else: "" 
    let markbtn = fmt"<button data-on:click__stop=""$id={msg.id}; @post('/api-mark-row')""><i class='bi bi-alarm'></i></button>"
    let marker = if marked == "": markbtn else: marked
    let dataclass = "{selected: $id===" & $msg.id & "}"
    result = fmt"""
        <tr data-on:click__stop="$id={msg.id}; @post('/api-select-row')" data-class="{dataclass}">
            <td>{msg.formId}</td>
            <td>{msg.id}</td>
            <td>{msg.name}</td>
            <td>{msg.email}</td>
            <td>{msg.message}</td>
            <td>{msg.status}</td>
            <td>
                <button data-on:click__stop="$id={msg.id}; @post('/api-delete-row')"><i class="bi bi-trash"></i></button>
                {marker}
                <button data-on:click__stop="$id={msg.id}; @post('/api-edit-row')"><i class="bi bi-pencil"></i></button>
            </td>
        </tr>
        """

# Load Tabledata
proc getTableRows(sse: SSEConnection) =
    let signals = getSignals(sse.request)
    # Table paging (todo)
    let maxrows = signals["maxrows"].getInt()
    let page = signals["page"].getInt()

    # Create the table from DB data
    var rows = "<tbody id='user-table-body'>"
    for id in OrderItr ^Registration:
        var registration = loadObject[Registration](@[id])
        rows.add(newTableRow(registration))
    rows.add("</tbody>")
    # Update Browser
    patchElements(sse, rows)

# Load Tabledata
proc handleGetTableRows(req: Request) =
    var sse = req.respondSSE(); defer: sse.close()
    getTableRows(sse)


proc selectRow(sse: SSEConnection) =
    let id = getRowId(sse.request)
    var reg = loadObject[Registration](@[$id]) # load from DB
    patchSignals(sse, %reg) # update gui with attributes from registration

# Select Row and show data in the form
proc handleSelectRow(req: Request) =
    var sse = req.respondSSE(); defer: sse.close()
    selectRow(sse)


proc deleteRow(sse: SSEConnection) =
    let id = getRowId(sse.request)
    deleteObject[Registration](@[$id])

# Delete Row
proc handleDeleteRow(req: Request) =
    var sse = req.respondSSE(); defer: sse.close()
    deleteRow(sse)
    getTableRows(sse)


proc setRowStatus(sse: SSEConnection, status: RowStatus) =
    let id = getRowId(sse.request)
    Set: ^Registration(id, "status") = $status & " " & $now()

# Edit Row
proc handleEditRow(req: Request) =
    var sse = req.respondSSE(); defer: sse.close()
    patchSignals(sse, %*{"lastFormId": "admin"})
    selectRow(sse)
    forward(sse, fmt"html/form.html")

# Mark Row (Update Timestamp)
proc handleMarkRow(req: Request) =
    var sse = req.respondSSE(); defer: sse.close()
    setRowStatus(sse, MARKED)
    getTableRows(sse)
    selectRow(sse)


# Reset the form, clear response-message on form
proc handleClearForm(req: Request) =
    var sse = req.respondSSE(); defer: sse.close()
    clearFormFields(sse)
    clearTechFields(sse)


# Save Registration
proc submitForm(req: Request) =
    let signals = getSignals(req)
    let formId = signals["formId"].getStr()
    let lastFormId = signals["lastFormId"].getStr()  
    var reg: Registration
    reg.fillFrom(signals)
    if reg.id == -1: # assign new id to new Registration
        reg.id = Increment ^CNT("registration")
    saveObject(@[$(reg.id)], reg)

    # Update browser
    var sse = req.respondSSE(); defer: sse.close()
    patchElements(sse, "<div id='response-message' class='formsuccess'>Registration saved!</div>")
   
    # jump back to calling page (if any)    
    if lastFormId != "" and lastFormId != formId:
        setRowStatus(sse, EDIT)
        let path = fmt"html/{lastFormId}.html"
        forward(sse, path)

    clearFormFields(sse)


# Save Country
proc submitCountry(req: Request) =
    let signals = getSignals(req)
    let formId = signals["formId"].getStr()
    let lastFormId = signals["lastFormId"].getStr()
    var country: Country
    country.fillFrom(signals)
    if country.id == -1: # assign new id to new Registration
        country.id = Increment ^CNT("country")
    saveObject(@[$(country.id)], country)

    # Update browser
    var sse = req.respondSSE(); defer: sse.close()
    patchElements(sse, "<div id='response-message' class='formsuccess'>Country saved!</div>")
   
    # jump back to calling page (if any)    
    if lastFormId != "" and lastFormId != formId:
        setRowStatus(sse, EDIT)
        let path = fmt"html/{lastFormId}.html"
        forward(sse, path)

    clearFormFields(sse)


# /update-clock (Do not close the connection)
proc handleUpdateClock(request: Request) =
  var sse = request.respondSSE()
  while true:
    let tm = $now()
    try:
      patchElements(sse, fmt"<h3 id='clock'>{tm}</h3>")
      patchSignals(sse, %*{"time": $now()})
    except:
      echo "Leaving handleUpdateClock: ", getCurrentExceptionMsg()
      break
    sleep(1000)


if isMainModule:
    ## Handler für Ctrl+C (SIGINT)
    proc shutdown() {.noconv.} =
        echo "\nShutting down..."
        quit(0)
    setControlCHook(shutdown)

    var router = Router()
    router.get("/api-submits", handleGetTableRows)
    router.post("/api-select-row", handleSelectRow)
    router.post("/api-delete-row", handleDeleteRow)
    router.post("/api-edit-row", handleEditRow)
    router.post("/api-mark-row", handleMarkRow)
    router.get("/update-clock", handleUpdateClock)
    router.get("/clear-form", handleClearForm)
    router.post("/validate-email", validateEmail)
    router.post("/submit-form", submitForm)
    router.post("/submit-country", submitCountry)
    router.notFoundHandler = serveStatic

    let (host, port) = ("192.168.1.159", 8080)
    let server = newServer(router)
    echo fmt"Simple SSE / Datastar server - Open http://{host}:{port} in your browser"

    server.serve(Port(port), host)
