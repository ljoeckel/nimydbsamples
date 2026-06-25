import std/[json, strutils, strformat, times, oids]
import mummy, mummy/routers, mummy/datastar
import nimrss
import wmFeedConfig


proc cleanSession(userid: string) =
    for val in @["oid", "keyword", "lastPubDate", "lastIdxRef", "lastRun"]:
        Kill ^Session(userid, val)


proc handleLogin(req: Request) =
    let ctx = getContext(req)
    cleanSession(ctx.userid)

    let password = ctx.getStr("password")
    let reg = loadObject[Registration](ctx.userid)
    if reg.password == generateSHA1(password): # valid password given
        checkFeedConfiguration(reg.userid)
        let oid = $genOid()
        var sse = req.respondSSE(cookie=fmt"token={oid}; Secure; HttpOnly; SameSite=Strict; Path=/")
        defer: sse.close()
        ctx.save("oid", oid)
        patchSignals(sse, %*{
            "loggedIn": true,
        })
        forward(sse, "html/livefeed.html")
    else:
        SSE(req):
            patchElements(sse, "<div id='login-message'>Invalid [userid] or [password]</div>")


proc handleLogout(req: Request) =
    let ctx = getContext(req)
    cleanSession(ctx.userid)

    var sse = req.respondSSE(cookie=fmt"token=; Max-Age=0; Secure; HttpOnly; Path=/; SameSite=Strict;")
    defer: sse.close()
    patchSignals(sse, %*{
        "loggedIn": false,
        "userid": "",
        "password": "",
    })        
    forward(sse, "./html/index.html")


proc clearForm(sse: SSEConnection, userid: string) =
    patchSignals(sse, %*{
        "userid": "", "password": "", "name": "", "email": "", "country": "",
        "terms": false, "plan": "", "emailInvalid": false, "useridInvalid": false,
    })

proc handleClearForm(req: Request) =
    let ctx = getContext(req)
    SSE(req):
        clearForm(sse, ctx.userid)


proc handleSubmitRegistration(req: Request) =
    # Save Registration
    var reg: Registration
    reg.fillFrom(getSignals(req))
    reg.password = generateSHA1(reg.password)
    reg.time = $now()
    saveObject(reg.userid, reg)

    # Update browser
    SSE(req):
        clearForm(sse, reg.userid)
        forward(sse, "./html/login.html")


proc handleEditRegistration(req: Request) =
    let ctx = getContext(req)
    if ctx.userid == "guest":
        SSE(req):
            patchElements(sse, "<div id='info' class='error'>You may not change the 'guest' profile</div>")        
            return

    let reg = loadObject[Registration](ctx.userid)
    SSE(req):
        forward(sse, "./html/registration-update.html")
        # fill the form fields
        patchSignals(sse, %*{
            "userid": reg.userid, "name": reg.name, "email": reg.email, "country": reg.country,
            "terms": reg.terms, "plan": reg.plan, "emailInvalid": false, "useridInvalid": false,
        })


proc handleUpdateRegistration(req: Request) =
    let ctx = getContext(req)
    var reg = loadObject[Registration](ctx.userid)
    reg.fillFrom(getSignals(req))
    reg.password = generateSHA1(reg.password) # in signal 'password' is the plain pw
    reg.time = $now()
    saveObject(reg.userid, reg)
    
    SSE(req):
        forward(sse, "./html/livefeed.html")


proc handleValidateEmail(req: Request) =
    # check if email is already registered
    let ctx = getContext(req)
    let email = ctx.getStr("email")
    if email != "":
        let isInvalid = 0 < Data ^RegistrationEMAIL(email)
        SSE(req):
            patchSignals(sse, %*{
                "emailInvalid": isInvalid,
                "canSubmit": not isInvalid
            })


proc handleValidateUserid(req: Request) =
    # check if a userid is already registered
    let ctx = getContext(req)
    if ctx.userid != "":
        let isInvalid = 0 < Data ^Registration(ctx.userid)
        SSE(req):
            patchSignals(sse, %*{
                "useridInvalid": isInvalid,
                "canSubmit": not isInvalid
            })


# Callback for router registration
proc register*(router: var Router) =
    router.post("/login", handleLogin)
    router.post("/logout", handleLogout)
    router.post("/clear-form", handleClearForm)
    router.post("/submit-registration", handleSubmitRegistration)
    router.post("/edit-registration", handleEditRegistration)
    router.post("/update-registration", handleUpdateRegistration)    
    router.post("/validate-email", handleValidateEmail)
    router.post("/validate-userid", handleValidateUserid)


# Create module instance
let wmLoginModule* = WebModule(
    name: "wmLogin",
    register: register
)