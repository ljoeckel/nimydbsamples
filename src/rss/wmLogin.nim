import std/[json, strutils, times]
import mummy, mummy/routers, mummy/datastar
import nimrss
import wmFeedConfig


proc handleLogin(req: Request) =
    let userid = getSignal(req, "userid")
    let password = getSignal(req, "password")
    let reg = loadObject[Registration](userid)
    if reg.password == generateSHA1(password):
        checkFeedConfiguration(reg.userid)
        SSE(req):
            patchSignals(sse, %*{
                "loggedIn": true,
            }, userid)
            forward(sse, "./html/livefeed.html", userid)
    else:
        SSE(req):
            patchElements(sse, "<div id='response-message' class='formerror'>Invalid 'userid' or 'password'</div>", userid)


proc handleLogout(req: Request) =
    let userid = getSignal(req, "userid")
    SSE(req):
        patchSignals(sse, %*{
            "loggedIn": false,
            "userid": "",
            "password": "",
        }, userid)        
        forward(sse, "./html/index.html", userid)


proc clearForm(sse: SSEConnection, userid: string) =
    patchSignals(sse, %*{
        "userid": "", "password": "", "name": "", "email": "", "country": "",
        "terms": false, "plan": "", "emailInvalid": false, "useridInvalid": false,
    }, userid)

proc handleClearForm(req: Request) =
    let userid = getSignal(req, "userid")
    SSE(req):
        clearForm(sse, userid)


proc handleSubmitRegistration(req: Request) =
    # Save Registration
    var reg: Registration
    reg.fillFrom(getSignals(req))
    reg.password = generateSHA1(reg.password)
    reg.time = $now()
    saveObject(reg.userid, reg)

    # Update browser
    SSE(req):
        patchElements(sse, "<div id='response-message' class='formsuccess'>Registration saved!</div>", reg.userid)
        clearForm(sse, reg.userid)
        forward(sse, "./html/login.html", reg.userid)


proc handleEditRegistration(req: Request) =
    let userid = getSignal(req, "userid")
    let reg = loadObject[Registration](userid)
    SSE(req):
        forward(sse, "./html/registration-update.html", userid)
        # fill the form fields
        patchSignals(sse, %*{
            "userid": reg.userid, "name": reg.name, "email": reg.email, "country": reg.country,
            "terms": reg.terms, "plan": reg.plan, "emailInvalid": false, "useridInvalid": false,
        }, userid)


proc handleUpdateRegistration(req: Request) =
    let userid = getSignal(req, "userid")
    var reg = loadObject[Registration](userid)
    reg.fillFrom(getSignals(req))
    reg.password = generateSHA1(reg.password) # in signal 'password' is the plain pw
    reg.time = $now()
    saveObject(reg.userid, reg)
    
    SSE(req):
        forward(sse, "./html/livefeed.html", reg.userid)


proc handleValidateEmail(req: Request) =
    # check if email is already registered
    let userid = getSignal(req, "userid")
    let email = getSignal(req, "email")
    if email != "":
        let isInvalid = 0 < Data ^RegistrationEMAIL(email)
        SSE(req):
            patchSignals(sse, %*{
                "emailInvalid": isInvalid,
                "canSubmit": not isInvalid
            }, userid)


proc handleValidateUserid(req: Request) =
    # check if a userid is already registered
    let userid = getSignal(req, "userid")
    if userid != "":
        let isInvalid = 0 < Data ^Registration(userid)
        SSE(req):
            patchSignals(sse, %*{
                "useridInvalid": isInvalid,
                "canSubmit": not isInvalid
            }, userid)


# Callback for router registration
proc register*(router: var Router) =
    router.post("/login", handleLogin)
    router.get("/logout", handleLogout)
    router.get("/clear-form", handleClearForm)
    router.post("/submit-registration", handleSubmitRegistration)
    router.get("/edit-registration", handleEditRegistration)
    router.post("/update-registration", handleUpdateRegistration)    
    router.post("/validate-email", handleValidateEmail)
    router.post("/validate-userid", handleValidateUserid)


# Create module instance
let wmLoginModule* = WebModule(
    name: "wmLogin",
    register: register
)