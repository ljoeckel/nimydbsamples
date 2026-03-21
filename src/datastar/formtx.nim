## Run 'nimble demo'

import std/[os, times, json, strutils, strformat, tables]
import mummy, mummy/routers, mummy/datastar
import yottadb
import types
import macros

template SSE(req: Request, body: untyped) =
    var sse {.inject.} = req.respondSSE() # sse for body
    defer: sse.close()
    body

const
    HTML_DIR = "html/"
    ALL_STATS = @["status", "country", "terms", "plan"]

proc handleUpdateClock(req: Request) =
    # /update-clock (Do not close the connection)
    var sse = req.respondSSE()
    while true:
        let nowTime = now()
        let msToNextMinute = 60000 - (nowTime.second * 1000 + nowTime.nanosecond div 1_000_000)
        let msg = nowTime.format("dd.MM.yyyy - HH:mm")
        try:
            patchElements(sse, fmt"<h3 id='wallclock'>{msg}</h3>")
            sleep(msToNextMinute)
        except:
            echo "Leaving handleUpdateClock: ", getCurrentExceptionMsg()
            sse.close()
            break

proc getIndexStats[T](indexName: string): string =
    # Scan through index and count entries (Status, Country,..) g.E. '^TRegistrationSTATUS'
    var counts = initCountTable[string]()
    let gbl = "^" & $T & indexName.toUpper
    for keys in QueryItr @gbl.keys:
        counts.inc(keys[0])
    
    var total = 0
    for k,v in counts:
        result.add(fmt"{k}({v}) ")
        inc(total, v)
    result.add(fmt" - Total({total})")

proc getStats(sse: SSEConnection, names: seq[string] = ALL_STATS) =
    # Get statistics
    patchSignals(sse, %*{
        "statusStats": getIndexStats[Registration]("status"),
        "countryStats": getIndexStats[Registration]("country"),
        "termsStats": getIndexStats[Registration]("terms"),
        "planStats": getIndexStats[Registration]("plan")
    })

proc handleGetStats(req: Request) =
    SSE(req):
        getStats(sse)


proc clearForm[T](sse: SSEConnection) =
    # clear form fields from given class T
    patchSignals(sse, %T())

proc clearFormFields(sse: SSEConnection) =
    # clear all fields from all form classes
    clearForm[Registration](sse)
    clearForm[Country](sse)

proc clearTechFields(sse: SSEConnection) =
    # clear technical form fields
    patchSignals(sse, %*{
        "lastFormId": "",
        "emailInvalid": false,
        "canSubmit": true,
        "id": "",
        "page": 1
    })
    patchElements(sse, "<div id='response-message'></div>") # clear response-message

proc handleClearForm(req: Request) =
    # Reset the form, clear response-message on form
    SSE(req):
        clearFormFields(sse)
        clearTechFields(sse)

proc handleGoto(req: Request) =
    # process menu links g.E. <a href="#form" data-on:click="$menuOpen = false; @get('goto/form.html')">Registration</a>
    let page = req.path.split("/goto/")[1]
    SSE(req):
        clearFormFields(sse)
        clearTechFields(sse)
        forward(sse, HTML_DIR & page)

proc getId(req: Request):string =
    # get the Id field from the current form
    let signals = getSignals(req)
    trimString($signals["id"])

proc getRow[T](id: string): string =
    let obj = loadObject[T](id)
    when T is Registration:
        result = getRegistrationRow(obj)
    elif T is Country:
        result = getCountryRow(obj)

proc getTableRows[T](sse: SSEConnection) =
    var rows = "<tbody id='user-table-body'>"
    let gbl = "^" & $T

    # Load Tabledata 
    let signals = getSignals(sse.request)
    let maxrows = if signals.contains("maxrows"): signals["maxrows"].getInt() else: 0
    if maxrows > 0:  # table paging
        var rowcount = maxrows
        var page = signals["page"].getInt()
        var skipcount = (page-1) * maxrows

        for id in OrderItr @gbl:
            if skipcount > 0:
                dec skipcount
                continue
            rows.add(getRow[T](id))
            dec rowcount
            if rowcount <= 0: break
    
        # Add Spacer rowx to preserve row-height
        while rowcount > 0:
            rows.add("""<tr></tr>""")
            dec rowcount

    else:  # all rows at once
        for id in OrderItr @gbl:
            rows.add(getRow[T](id))

    rows.add("</tbody>")
    # Update Browser
    patchElements(sse, rows)

# -------------------
# Registration table
# -------------------
proc isEmailRegistered(req: Request) =
    # check if email is already registered
    let signals = getSignals(req)
    let email = signals["email"].getStr()
    if email != "":
        let isInvalid = 0 < Data ^RegistrationEMAIL(email)
        SSE(req):
            patchSignals(sse, %*{
                "emailInvalid": isInvalid,
                "canSubmit": not isInvalid
            })

proc getRegistrationRow(msg: Registration): string =
    # Create a table row for class Registration
    let marked = if msg.status.startsWith("Marked"): "<button>✅</button>" else: "" 
    let markbtn = fmt"<button data-on:click__stop=""$id={msg.id}; @post('/mark-registration-row')""><i class='bi bi-alarm'></i></button>"
    let marker = if marked == "": markbtn else: marked
    let dataclass = "{" & fmt"selected: $id==='{$msg.id}'" & "}"
    result = fmt"""
        <tr id='Registration{msg.id}' data-on:click__stop="$id='{msg.id}'; @post('/select-registration-row')" data-class="{dataclass}">
            <td>{msg.id}</td>
            <td>{msg.name}</td>
            <td>{msg.email}</td>
            <td>{msg.message}</td>
            <td>{msg.status}</td>
            <td>
                <button data-on:click__stop="$id='{msg.id}'; @post('/delete-registration-row')"><i class="bi bi-trash"></i></button>
                {marker}
                <button data-on:click__stop="$id='{msg.id}'; @post('/edit-registration-row')"><i class="bi bi-pencil"></i></button>
            </td>
        </tr>
        """

proc handleGetRegistrations(req: Request) =
    # Load Tabledata
    SSE(req):
        getTableRows[Registration](sse)

proc selectRegistrationRow(sse: SSEConnection, id: string) =
    var reg = loadObject[Registration](id) # load from DB
    patchSignals(sse, %reg) # update gui with attributes from registration

proc handleSelectRegistrationRow(req: Request) =
    # Select Row and show data in the form
    let id = getId(req)
    SSE(req):
        selectRegistrationRow(sse, id)

proc handleDeleteRegistrationRow(req: Request) =
    # Delete Row
    let id = getId(req)
    deleteObject[Registration](id)
    SSE(req): 
        getTableRows[Registration](sse)
        getStats(sse)

proc setRowStatus(sse: SSEConnection, id: string, status: RowStatus) =
    # update Registration in DB
    Set:
        ctx("id") = id
        ctx("status") = $status

    discard Transaction:
        let id = Get ctx("id")
        var reg = loadObject[Registration](id)
        reg.status = Get ctx("status")
        reg.time = $now()
        saveObject(id, reg)
    
    # Read Updated Registration and update the form fields
    var reg = loadObject[Registration](id)
    let row = getRegistrationRow(reg)
    patchElements(sse, row)
    patchSignals(sse, %reg)

proc handleEditRow(req: Request) =
    # Edit Row
    let id = getId(req)
    SSE(req):
        patchSignals(sse, %*{"lastFormId": "admin"})
        selectRegistrationRow(sse, id)
        forward(sse, HTML_DIR & "form.html")

proc handleMarkRow(req: Request) =
    # Mark Row (Update Timestamp)
    SSE(req):
        let id = getId(sse.request)
        setRowStatus(sse, id, MARKED)
        getStats(sse)
        selectRegistrationRow(sse, id)

proc submitRegistration(req: Request) =
    # Save Registration
    let signals = getSignals(req)
    Set: ctx("signals") = $signals

    discard Transaction:
        let signals = parseJson(Get ctx("signals"))
        var reg: Registration
        reg.fillFrom(signals)
        reg.time = $now()
        if reg.id == "": # assign new id to new Registration
            reg.id = $Increment ^CNT("registration")
            reg.status = $NEW
        else:
            reg.status = $EDIT
            
        saveObject(reg.id, reg)

    # Update browser
    SSE(req):
        patchElements(sse, "<div id='response-message' class='formsuccess'>Registration saved!</div>")

        let formId = signals["formId"].getStr()
        let lastFormId = signals["lastFormId"].getStr()  
        # jump back to 'admin' if from there    
        if lastFormId == "admin" and lastFormId != formId:
            let path = fmt"{HTML_DIR}{lastFormId}.html"
            forward(sse, path)
        else:
            getTableRows[Registration](sse)
            clearForm[Registration](sse)
            getStats(sse)

#------------------------
# Country table
#------------------------
proc getCountryRow(msg: Country): string =
    let dataclass = "{" & fmt"selected: $id==='{$msg.id}'" & "}"
    result = fmt"""
        <tr id='Country{msg.id}' data-on:click__stop="$id='{msg.id}'; @post('/select-country-row')" data-class="{dataclass}">
            <td>{msg.id}</td>
            <td>{msg.country}</td>
            <td>{msg.calling_code}</td>
            <td>
                <button data-on:click__stop="$id='{msg.id}'; @post('/delete-country-row')"><i class="bi bi-trash"></i></button>
            </td>
        </tr>
        """

proc handleGetCountries(req: Request) =
    # Create Country table
    SSE(req):
        getTableRows[Country](sse)

proc handleSelectCountryRow(req: Request) =
    # Select Row and show data in the form
    let id = getId(req)
    let country = loadObject[Country](id) # load from DB
    SSE(req):
        patchSignals(sse, %country) # update gui with attributes

proc handleDeleteCountryRow(req: Request) =
    # Delete Row
    Set: ctx("id") = getId(req)
    discard Transaction:
        let id = Get ctx("id")
        deleteObject[Country](id)

    SSE(req):
        clearForm[Country](sse)
        getTableRows[Country](sse)

proc handleGetCountry(req: Request) =
    # Get Country data
    let signals = getSignals(req)
    let id = toUpper(signals["id"].getStr())
    var country = loadObject[Country](id)
    if country.id == "": country.id = id # hold back the last 'id' field
    # Update form fields
    SSE(req):
        patchSignals(sse, %country)
        executeScript(sse, fmt"reveal('Country{country.id}')")
   
proc handleSubmitCountry(req: Request) =
    # Save Country
    Set: ctx("signals") = $getSignals(req)
    discard Transaction:
        let signals = parseJson(Get ctx("signals"))
        var country: Country
        country.fillFrom(signals)
        if country.id == "": # assign new id to new Country
            country.id = "X" & $(Increment ^CNT("country"))
        
        country.time = $now()
        saveObject(country.id, country)

    # Update browser
    SSE(req):
        patchElements(sse, "<div id='response-message' class='formsuccess'>Country saved!</div>")
        getTableRows[Country](sse)
        clearForm[Country](sse)


if isMainModule:
    ## Handler für Ctrl+C (SIGINT)
    proc shutdown() {.noconv.} =
        echo "\nShutting down..."
        quit(0)
    setControlCHook(shutdown)

    var router = Router()
    router.get("/get-registrations", handleGetRegistrations)
    router.get("/get-stats", handleGetStats)

    router.post("/select-registration-row", handleSelectRegistrationRow)
    router.post("/delete-registration-row", handleDeleteRegistrationRow)
    router.post("/edit-registration-row", handleEditRow)
    router.post("/mark-registration-row", handleMarkRow)
    router.post("/submit-registration", submitRegistration)

    router.get("/get-countries", handleGetCountries)
    router.post("/select-country-row", handleSelectCountryRow)
    router.post("/delete-country-row", handleDeleteCountryRow)
    router.post("/submit-country", handleSubmitCountry)
    router.post("/get-country", handleGetCountry)

    router.get("/update-clock", handleUpdateClock)
    router.get("/clear-form", handleClearForm)
    router.post("/validate-email", isEmailRegistered)
    # Standard handlers
    router.get("/goto/**", handleGoto)
    router.notFoundHandler = serveStatic

    let (host, port) = ("localhost", 8080)
    let server = newServer(router)
    echo fmt"Simple SSE / Datastar server - Open http://{host}:{port} in your browser"

    server.serve(Port(port), host)
