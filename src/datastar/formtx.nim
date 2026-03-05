## Run 'nimble demo'

import std/[os, times, json, strutils, strformat]
import mummy, mummy/routers, mummy/datastar
import yottadb
import macros
import types

const 
    HTML_DIR = "html/"
    COUNTRY_FORM_FIELDS = @["id", "country", "calling_code"]

type
    RowStatus = enum 
        NEW = "New"
        EDIT = "Edit"
        MARKED = "Marked"

proc getClearPatch*[T](obj: T): JsonNode =
  ## Iterates over fields and returns a JSON object containing 'null' for every non-empty field.
  result = newJObject()
  for name, value in obj.fieldPairs:
    when value is string:
      if value.strip() != "":
        result[name] = newJNull()
    elif value is bool:
      if value:
        result[name] = newJNull()

proc filterPatch*[T](obj: T, fields:seq[string]): JsonNode =
    # add only fields from 'obj' which are also in 'fields'
    var json = newJObject()
    for name, value in obj.fieldPairs: 
        for nm in fields:
            if nm == name: json[name] = %value
    return json

proc clearForm[T](sse: SSEConnection) =
    # clear form fields from given class T
    var obj: T
    patchSignals(sse, %obj)

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

proc isRegisteredEmail(req: Request) =
    # check if email is already registered
    let signals = getSignals(req)
    let email = signals["email"].getStr()
    if email != "":
        let isInvalid = 0 < Data ^RegistrationEMAIL(email)
        var sse = req.respondSSE(); defer: sse.close()
        patchSignals(sse, %*{
            "emailInvalid": isInvalid,
            "canSubmit": not isInvalid
        })

proc getId(req: Request):string =
    # get the Id field from the current form
    let signals = getSignals(req)
    trimString($signals["id"])

proc getRegistrationRow(msg: Registration): string =
    # Create a table row for class Registration
    let marked = if msg.status.startsWith("Marked"): "<button>✅</button>" else: "" 
    let markbtn = fmt"<button data-on:click__stop=""$id={msg.id}; @post('/mark-row')""><i class='bi bi-alarm'></i></button>"
    let marker = if marked == "": markbtn else: marked
    let dataclass = "{" & fmt"selected: $id==='{$msg.id}'" & "}"
    result = fmt"""
        <tr id='Registration{msg.id}' data-on:click__stop="$id='{msg.id}'; @post('/select-row')" data-class="{dataclass}">
            <td>{msg.id}</td>
            <td>{msg.name}</td>
            <td>{msg.email}</td>
            <td>{msg.message}</td>
            <td>{msg.status}</td>
            <td>
                <button data-on:click__stop="$id='{msg.id}'; @post('/delete-row')"><i class="bi bi-trash"></i></button>
                {marker}
                <button data-on:click__stop="$id='{msg.id}'; @post('/edit-row')"><i class="bi bi-pencil"></i></button>
            </td>
        </tr>
        """

proc getTableRows[T](sse: SSEConnection) =
    # Load Tabledata 
    let signals = getSignals(sse.request)
    # Table paging (todo)
    let maxrows = signals["maxrows"].getInt()
    let page = signals["page"].getInt()

    # Create the table from DB data
    var rows = "<tbody id='user-table-body'>"
    let gbl = "^" & $T
    for id in OrderItr @gbl:
        var obj = loadObject[T](id)
        when T is Registration:
            rows.add(getRegistrationRow(obj))
        elif T is Country:
            rows.add(getCountryRow(obj))
    rows.add("</tbody>")
    # Update Browser
    patchElements(sse, rows)

proc handleGetRegistrations(req: Request) =
    # Load Tabledata
    var sse = req.respondSSE(); defer: sse.close()
    getTableRows[Registration](sse)

proc selectRow(sse: SSEConnection, id: string) =
    var reg = loadObject[Registration](id) # load from DB
    patchSignals(sse, %reg) # update gui with attributes from registration

# Select Row and show data in the form
proc handleSelectRow(req: Request) =
    let id = getId(req)
    var sse = req.respondSSE(); defer: sse.close()
    selectRow(sse, id)

# Delete Row
proc handleDeleteRow(req: Request) =
    let id = getId(req)
    deleteObject[Registration](id)
    var sse = req.respondSSE(); defer: sse.close()
    getTableRows[Registration](sse)

proc setRowStatus(sse: SSEConnection, id: string, status: RowStatus) =
    # update Registration in DB
    var reg = loadObject[Registration](id)
    reg.status = $status
    reg.time = $now()
    saveObject(id, reg)
    # Update table and form fields
    let row = getRegistrationRow(reg)
    patchElements(sse, row)
    patchSignals(sse, %reg)

# Edit Row
proc handleEditRow(req: Request) =
    var sse = req.respondSSE(); defer: sse.close()
    let id = getId(req)
    setRowStatus(sse, id, EDIT)
    patchSignals(sse, %*{"lastFormId": "admin"})
    selectRow(sse, id)
    forward(sse, HTML_DIR & "form.html")

# Mark Row (Update Timestamp)
proc handleMarkRow(req: Request) =
    var sse = req.respondSSE(); defer: sse.close()
    let id = getId(sse.request)
    setRowStatus(sse, id, MARKED)
    selectRow(sse, id)

#------------------------
# Country table
#------------------------
proc getCountryRow(msg: Country): string =
    let dataclass = "{" & fmt"selected: $id==='{$msg.id}'" & "}"
    result = fmt"""
        <tr data-on:click__stop="$id='{msg.id}'; @post('/select-country-row')" data-class="{dataclass}">
            <td>{msg.id}</td>
            <td>{msg.country}</td>
            <td>{msg.calling_code}</td>
            <td>
                <button data-on:click__stop="$id='{msg.id}'; @post('/delete-country-row')"><i class="bi bi-trash"></i></button>
            </td>
        </tr>
        """

# Load Tabledata
proc handleGetCountries(req: Request) =
    var sse = req.respondSSE(); defer: sse.close()
    getTableRows[Country](sse)

# Select Row and show data in the form
proc handleSelectCountryRow(req: Request) =
    let id = getId(req)
    let country = loadObject[Country](id) # load from DB
    let filter = filterPatch(country, COUNTRY_FORM_FIELDS)
    var sse = req.respondSSE(); defer: sse.close()
    patchSignals(sse, %filter) # update gui with attributes from registration

# Delete Row
proc handleDeleteCountryRow(req: Request) =
    let id = getId(req)
    var sse = req.respondSSE(); defer: sse.close()
    deleteObject[Country](id)
    clearForm[Country](sse)
    getTableRows[Country](sse)


# Reset the form, clear response-message on form
proc handleClearForm(req: Request) =
    let signals = getSignals(req)
    var sse = req.respondSSE(); defer: sse.close()
    clearFormFields(sse)
    clearTechFields(sse)

# Save Registration
proc submitRegistration(req: Request) =
    let signals = getSignals(req)
    let formId = signals["formId"].getStr()
    let lastFormId = signals["lastFormId"].getStr()  
    var reg: Registration
    reg.fillFrom(signals)
    if reg.id == "": # assign new id to new Registration
        reg.id = $Increment ^CNT("registration")
        reg.status = $NEW
    reg.time = $now()
    saveObject(reg.id, reg)

    # Update browser
    var sse = req.respondSSE(); defer: sse.close()
    patchElements(sse, "<div id='response-message' class='formsuccess'>Registration saved!</div>")
   
    # jump back to 'admin' if from there    
    if lastFormId == "admin" and lastFormId != formId:
        let path = fmt"{HTML_DIR}{lastFormId}.html"
        forward(sse, path)
    else:
        getTableRows[Registration](sse)
        clearForm[Registration](sse)

# -------------------
# Country
# -------------------
proc getCountry(req: Request) =
    # Get Country data
    var sse = req.respondSSE(); defer: sse.close()
    let signals = getSignals(req)
    let id = toUpper(signals["id"].getStr())
    var country = loadObject[Country](id)
    if country.id == "": country.id = id # hold back the last 'id' field
    # Update form fields
    patchSignals(sse, %filterPatch(country, COUNTRY_FORM_FIELDS))
    
proc submitCountry(req: Request) =
    # Save Country
    let signals = getSignals(req)
    var country: Country
    country.fillFrom(signals)
    if country.id == "": # assign new id to new Country
        country.id = "X" & $(Increment ^CNT("country"))
    country.time = $now()
    saveObject(country.id, country)

    # Update browser
    var sse = req.respondSSE(); defer: sse.close()
    patchElements(sse, "<div id='response-message' class='formsuccess'>Country saved!</div>")
    getTableRows[Country](sse)
    clearForm[Country](sse)

proc handleUpdateClock(req: Request) =
  # /update-clock (Do not close the connection)
  let sse = req.respondSSE()
  while true:
    let nowTime = now()
    let msToNextMinute = 60000 - (nowTime.second * 1000 + nowTime.nanosecond div 1_000_000)
    let msg = nowTime.format("dd.MM.yyyy - HH:mm")
    try:
      patchElements(sse, fmt"<h3 id='wallclock'>{msg}</h3>")
      sleep(msToNextMinute)
    except:
      echo "Leaving handleUpdateClock: ", getCurrentExceptionMsg()
      break

proc handleGotoForm(req: Request) =
    # process menu links
    # <a href="#form" data-on:click="$menuOpen = false; @get('goto/form.html')">Registration</a>
    let page = req.path.split("/goto/")[1]
    let sse = req.respondSSE()
    clearFormFields(sse)
    forward(sse, HTML_DIR & page)

if isMainModule:
    ## Handler für Ctrl+C (SIGINT)
    proc shutdown() {.noconv.} =
        echo "\nShutting down..."
        quit(0)
    setControlCHook(shutdown)

    var router = Router()
    router.get("/get-registrations", handleGetRegistrations)
    router.post("/select-row", handleSelectRow)
    router.post("/delete-row", handleDeleteRow)
    router.post("/edit-row", handleEditRow)
    router.post("/mark-row", handleMarkRow)
    router.post("/submit-registration", submitRegistration)

    router.get("/get-countries", handleGetCountries)
    router.post("/select-country-row", handleSelectCountryRow)
    router.post("/delete-country-row", handleDeleteCountryRow)
    router.post("/submit-country", submitCountry)
    router.post("/get-country", getCountry)

    router.get("/update-clock", handleUpdateClock)
    router.get("/clear-form", handleClearForm)
    router.post("/validate-email", isRegisteredEmail)
    # Standard handlers
    router.get("/goto/**", handleGotoForm)
    router.notFoundHandler = serveStatic

    let (host, port) = ("192.168.1.159", 8080)
    let server = newServer(router)
    echo fmt"Simple SSE / Datastar server - Open http://{host}:{port} in your browser"

    server.serve(Port(port), host)
