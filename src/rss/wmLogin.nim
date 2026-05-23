import std/[json, strutils, times]
import mummy, mummy/routers, mummy/datastar
import nimrss
import wmFeedConfig

proc handleLogin(req: Request) =
    var loggedIn = false
    let userid = getSignal(req, "userid")
    let password = getSignal(req, "password")
    let id = Query ^RegistrationUSERID(userid).keys

    if id.len > 0:
        let pw = Get ^Registration(id[1], "password")
        if pw == generateSHA1(password) or userid == "guest":
            loggedIn = true

    if loggedIn:
        checkFeedConfiguration(userid)
        SSE(req):
            patchSignals(sse, %*{"loggedIn": true})
            forward(sse, "./html/livefeed.html")
    else:
        SSE(req):
            patchElements(sse, "<div id='response-message' class='formerror'>Invalid 'userid' or 'password'</div>")


proc handleLogout(req: Request) =
    SSE(req):
        patchSignals(sse, %*{
            "loggedIn": false,
            "userid": "",
            "password": ""
        })        
        forward(sse, "./html/index.html")


proc clearForm(sse: SSEConnection) =
    patchSignals(sse, %*{
        "userid": "", "password": "", "name": "", "email": "", "country": "",
        "terms": false, "plan": "", "emailInvalid": false, "useridInvalid": false,
    })


proc handleSubmitRegistration(req: Request) =
    # Save Registration
    let signals = getSignals(req)
    Set: ctx("signals") = $signals

    discard Transaction:
        let signals = parseJson(Get ctx("signals"))
        var reg: Registration
        reg.fillFrom(signals)
        reg.password = generateSHA1(reg.password)
        reg.time = $now()
        reg.id = $Increment ^CNT("registration")
        saveObject(reg.id, reg)

    # Update browser
    SSE(req):
        patchElements(sse, "<div id='response-message' class='formsuccess'>Registration saved!</div>")
        clearForm(sse)
        forward(sse, "./html/login.html")


proc handleEditRegistration(req: Request) =
    echo "handleEditRegistration"
    let signals = getSignals(req)
    echo "signals=", $signals


proc handleClearForm(req: Request) =
    SSE(req):
        clearForm(sse)


proc handleValidateEmail(req: Request) =
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


proc handleValidateUserid(req: Request) =
    # check if a userid is already registered
    let signals = getSignals(req)
    let userid = signals["userid"].getStr()
    if userid != "":
        let isInvalid = 0 < Data ^RegistrationUSERID(userid)
        SSE(req):
            patchSignals(sse, %*{
                "useridInvalid": isInvalid,
                "canSubmit": not isInvalid
            })


# Callback for router registration
proc register*(router: var Router) =
    router.post("/login", handleLogin)
    router.get("/logout", handleLogout)
    router.get("/clear-form", handleClearForm)
    router.post("/submit-registration", handleSubmitRegistration)
    router.get("/edit-registration", handleEditRegistration)
    router.post("/validate-email", handleValidateEmail)
    router.post("/validate-userid", handleValidateUserid)


# Create module instance
let wmLoginModule* = WebModule(
    name: "wmLogin",
    register: register
)