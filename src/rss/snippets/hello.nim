import yottadb

let userid = "4711"

Set:
    User(1, "name") = "Alice"
    ^UserSession(userid, "name") = "Lothar"
    ^UserSession(userid, "token") = "1ab2cd3d9d3a3d"

echo "Username: ", Get User(1, "name")

for key, value in QueryItr ^UserSession.kv:
    echo key, "=", value

Kill ^UserSession(userid)

