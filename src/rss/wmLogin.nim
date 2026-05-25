import std/[json, strutils, times]
import mummy, mummy/routers, mummy/datastar
import nimrss
import wmFeedConfig


proc getRegistration(req: Request): Registration =
    let userid = getSignal(req, "userid")
    loadObject[Registration](userid)


proc handleLogin(req: Request) =
    let password = getSignal(req, "password")
    let reg = getRegistration(req)
    if reg.password == generateSHA1(password):
        checkFeedConfiguration(reg.userid)
        SSE(req):
            patchSignals(sse, %*{
                "loggedIn": true,
            })
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

proc handleClearForm(req: Request) =
    SSE(req):
        clearForm(sse)


proc handleSubmitRegistration(req: Request) =
    # Save Registration
    var reg: Registration
    reg.fillFrom(getSignals(req))
    reg.password = generateSHA1(reg.password)
    reg.time = $now()
    saveObject(reg.userid, reg)

    # Update browser
    SSE(req):
        patchElements(sse, "<div id='response-message' class='formsuccess'>Registration saved!</div>")
        clearForm(sse)
        forward(sse, "./html/login.html")


proc handleEditRegistration(req: Request) =
    var reg = getRegistration(req)
    SSE(req):
        forward(sse, "./html/registration-update.html")
        # fill the form fields
        patchSignals(sse, %*{
            "userid": reg.userid, "name": reg.name, "email": reg.email, "country": reg.country,
            "terms": reg.terms, "plan": reg.plan, "emailInvalid": false, "useridInvalid": false,
        })


proc handleUpdateRegistration(req: Request) =
    var reg = getRegistration(req)
    reg.fillFrom(getSignals(req))
    reg.password = generateSHA1(reg.password) # in signal 'password' is the plain pw
    reg.time = $now()
    saveObject(reg.userid, reg)
    
    SSE(req):
        forward(sse, "./html/livefeed.html")


proc handleValidateEmail(req: Request) =
    # check if email is already registered
    let email = getSignal(req, "email")
    if email != "":
        let isInvalid = 0 < Data ^RegistrationEMAIL(email)
        SSE(req):
            patchSignals(sse, %*{
                "emailInvalid": isInvalid,
                "canSubmit": not isInvalid
            })


proc handleValidateUserid(req: Request) =
    # check if a userid is already registered
    let userid = getSignal(req, "userid")
    if userid != "":
        let isInvalid = 0 < Data ^Registration(userid)
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
    router.post("/update-registration", handleUpdateRegistration)    
    router.post("/validate-email", handleValidateEmail)
    router.post("/validate-userid", handleValidateUserid)


# Create module instance
let wmLoginModule* = WebModule(
    name: "wmLogin",
    register: register
)