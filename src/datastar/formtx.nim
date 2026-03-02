## Run 'nimble demo'

import std/[os, times, json, strutils, strformat]
import mummy, mummy/routers, mummy/datastar
import yottadb
import macros
import types

const COUNTRY_FORM_FIELDS = @["id", "country", "calling_code"]

type
    RowStatus = enum 
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

proc newRegistrationRow(msg: Registration): string =
    # Create a table row for class Registration
    let marked = if msg.status.startsWith("Marked"): "<button>✅</button>" else: "" 
    let markbtn = fmt"<button data-on:click__stop=""$id={msg.id}; @post('/api-mark-row')""><i class='bi bi-alarm'></i></button>"
    let marker = if marked == "": markbtn else: marked
    let dataclass = "{" & fmt"selected: $id==='{$msg.id}'" & "}"
    result = fmt"""
        <tr data-on:click__stop="$id='{msg.id}'; @post('/api-select-row')" data-class="{dataclass}">
            <td>{msg.id}</td>
            <td>{msg.name}</td>
            <td>{msg.email}</td>
            <td>{msg.message}</td>
            <td>{msg.status}</td>
            <td>
                <button data-on:click__stop="$id='{msg.id}'; @post('/api-delete-row')"><i class="bi bi-trash"></i></button>
                {marker}
                <button data-on:click__stop="$id='{msg.id}'; @post('/api-edit-row')"><i class="bi bi-pencil"></i></button>
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
        var obj = loadObject[T](@[id])
        when T is Registration:
            rows.add(newRegistrationRow(obj))
        elif T is Country:
            rows.add(newCountryRow(obj))
    rows.add("</tbody>")
    # Update Browser
    patchElements(sse, rows)


# Load Tabledata
proc handleGetTableRows(req: Request) =
    var sse = req.respondSSE(); defer: sse.close()
    getTableRows[Registration](sse)


proc selectRow(sse: SSEConnection) =
    let id = getId(sse.request)
    var reg = loadObject[Registration](@[$id]) # load from DB
    patchSignals(sse, %reg) # update gui with attributes from registration
    echo "selectRow id:", id

# Select Row and show data in the form
proc handleSelectRow(req: Request) =
    var sse = req.respondSSE(); defer: sse.close()
    selectRow(sse)


proc deleteRow(sse: SSEConnection) =
    let id = getId(sse.request)
    deleteObject[Registration](@[$id])

# Delete Row
proc handleDeleteRow(req: Request) =
    var sse = req.respondSSE(); defer: sse.close()
    deleteRow(sse)
    getTableRows[Registration](sse)


proc setRowStatus(sse: SSEConnection, status: RowStatus) =
    let id = getId(sse.request)
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
    getTableRows[Registration](sse)
    selectRow(sse)

#------------------------
# Country table
#------------------------
proc newCountryRow(msg: Country): string =
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
proc handleGetCountryRows(req: Request) =
    var sse = req.respondSSE(); defer: sse.close()
    getTableRows[Country](sse)

# Select Row and show data in the form
proc handleSelectCountryRow(req: Request) =
    let id = getId(req)
    let country = loadObject[Country](@[id]) # load from DB
    let filter = filterPatch(country, COUNTRY_FORM_FIELDS)
    var sse = req.respondSSE(); defer: sse.close()
    patchSignals(sse, %filter) # update gui with attributes from registration

# Delete Row
proc handleDeleteCountryRow(req: Request) =
    let id = getId(req)
    var sse = req.respondSSE(); defer: sse.close()
    deleteObject[Country](@[$id])
    getTableRows[Country](sse)


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
    if reg.id == "": # assign new id to new Registration
        reg.id = $(Increment ^CNT("registration"))
    saveObject(@[$(reg.id)], reg)

    # Update browser
    var sse = req.respondSSE(); defer: sse.close()
    patchElements(sse, "<div id='response-message' class='formsuccess'>Registration saved!</div>")
   
    # jump back to calling page (if any)    
    if lastFormId != "" and lastFormId != formId:
        setRowStatus(sse, EDIT)
        let path = fmt"html/{lastFormId}.html"
        forward(sse, path)
    else:
        getTableRows[Registration](sse)

    echo "formId:" , formId
    if formId == "form": 
        clearForm[Registration](sse)

# Get Country data
proc getCountry(req: Request) =
    var sse = req.respondSSE(); defer: sse.close()
    let signals = getSignals(req)
    let id = toUpper(signals["id"].getStr())
    var country = loadObject[Country](@[id])
    if country.id == "": country.id = id # hold back the last 'id' field
    # Update form fields
    patchSignals(sse, %filterPatch(country, COUNTRY_FORM_FIELDS))
    
# Save Country
proc submitCountry(req: Request) =
    let signals = getSignals(req)
    let formId = signals["formId"].getStr()
    let lastFormId = signals["lastFormId"].getStr()
    var country: Country
    country.fillFrom(signals)
    if country.id == "": # assign new id to new Registration
        country.id = "X" & $(Increment ^CNT("country"))
    saveObject(@[country.id], country)

    # Update browser
    var sse = req.respondSSE(); defer: sse.close()
    patchElements(sse, "<div id='response-message' class='formsuccess'>Country saved!</div>")
   
    # jump back to calling page (if any)    
    if lastFormId != "" and lastFormId != formId:
        setRowStatus(sse, EDIT)
        let path = fmt"html/{lastFormId}.html"
        forward(sse, path)
    else:
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
      patchElements(sse, fmt"<h3 id='clock'>{msg}</h3>")
      patchSignals(sse, %*{"time": msg})
      sleep(msToNextMinute)
    except:
      echo "Leaving handleUpdateClock: ", getCurrentExceptionMsg()
      break

proc handleInitForm(req: Request) {.gcsafe.} =
    var sse = req.respondSSE(); defer: sse.close()        
    clearFormFields(sse)

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

    router.get("/country-submits", handleGetCountryRows)
    router.post("/select-country-row", handleSelectCountryRow)
    router.post("/delete-country-row", handleDeleteCountryRow)

    router.get("/update-clock", handleUpdateClock)
    router.get("/clear-form", handleClearForm)
    router.post("/validate-email", isRegisteredEmail)
    router.post("/submit-form", submitForm)
    router.post("/submit-country", submitCountry)
    router.post("/get-country", getCountry)
    # Standard handlers
    router.get("/init-form", handleInitForm)
    router.notFoundHandler = serveStatic

    let (host, port) = ("192.168.1.159", 8080)
    let server = newServer(router)
    echo fmt"Simple SSE / Datastar server - Open http://{host}:{port} in your browser"

    server.serve(Port(port), host)
