import std/[json, strformat, oids]
import mummy, mummy/datastar
import ../nimrss

proc handleLogin(req: Request) =
    let userid = getSignal(req, "userid")
    let password = getSignal(req, "password")
    let reg = loadObject[Registration](userid)

    if reg.password == generateSHA1(password): # valid password given
        let oid = $genOid()
        var sse = req.respondSSE(cookie=fmt"token={oid}; Secure; HttpOnly; SameSite=Strict; Path=/")
        defer: sse.close()            
        Set: ^Session(userid, "oid") = oid
        patchSignals(sse, %*{ "loggedIn": true }, userid)
        forward(sse, "html/livefeed.html", userid)
    else:
        SSE(req):
            patchElements(sse, "<div id='response-message' class='formerror'>Invalid 'userid' or 'password'</div>", userid)
