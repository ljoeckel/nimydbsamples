import std/[json, strutils]
import mummy, mummy/routers, mummy/datastar
import nimrss
import wmFeedConfig

proc handleLogin(req: Request) =
    let userid = getSignal(req, USERID)
    if userid == "guest":  #TODO: password validation
        # Check for user ^Feed configuration
        checkFeedConfiguration(userid)

        SSE(req):
            patchSignals(sse, %*{"loggedIn": true})
            forward(sse, "./html/livefeed.html")


proc handleLogout(req: Request) =
    SSE(req):
        patchSignals(sse, %*{
            "loggedIn": false,
            "userid": "",
        })        
        forward(sse, "./html/index.html")

proc handleEditRegistration(req: Request) =
    echo "handleRegistration"
    let signals = getSignals(req)
    echo "signals=", $signals
    

# Callback for router registration
proc register*(router: var Router) =
    router.post("/login", handleLogin)
    router.get("/logout", handleLogout)
    router.get("/edit-registration", handleEditRegistration)


# Create module instance
let wmLoginModule* = WebModule(
    name: "wmLogin",
    register: register
)