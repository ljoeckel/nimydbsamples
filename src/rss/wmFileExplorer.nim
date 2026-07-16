import std/[json, strutils, strformat, times, oids]
import mummy, mummy/routers, mummy/datastar
import nimrss
import wmFeedConfig
import std/[os, algorithm, sugar]

const MAX_COUNT = 3000

proc stripId(id: string): string =
    result = id.replace("/", "").replace(".", "").replace("_", "")

proc dir(id: string, title: string): string =
    let selector = fmt"""data-on:toggle="$isOpen=evt.target.open; $dir='{id}'; @post('/api/select-dir')" """
    result.add("<li>")
    result.add("<details " & selector & ">")
    result.add("<summary>" & title & "</summary>")
    result.add("<ul id='" & stripId(id) & "'></ul>")
    result.add("</details>")
    result.add("</li>")


proc file(id: string, title: string): string = 
    result = "<li><a href='#" & stripId(id) & "'>" & title & "</a></li>"


proc scanDir(directory: string, id: string): seq[(PathComponent, string)] =
    var items: seq[(PathComponent, string)]
    var dirs: seq[(PathComponent, string)]
    var count = 0
    for kind, path in walkDir(directory):
        let rpath = path
        if count <= MAX_COUNT:
            if kind in {pcDir, pcLinkToDir}:
                dirs.add((kind, rpath))
            else:
                items.add((kind, rpath))
        inc count

    if count > MAX_COUNT:
        echo fmt"For directory '{directory}': There are {count - MAX_COUNT} more items. Ignored"

    items.sort((x, y) => (
      let c = cmp(x[1], y[1])
      c
    ))
    dirs.sort((x, y) => (
      let c = cmp(x[1], y[1])
      c
    ))

    result.add(dirs)
    result.add(items)


proc getHTML(id: string, items: seq[(PathComponent, string)]): string =
    result.add(fmt"<ul class='tree' id='{stripId(id)}'>")
    for (kind, path) in items:
        if kind in {pcDir, pcLinkToDir}:
            result.add(dir(id=path, title=path))
        else:
            result.add(file(id=path, title=path))

    result.add("</ul>")


proc handleListGlobals(req: Request) =
    # Initial load of the 'dir' given from the signal
    let ctx = getContext(req)
    let dir = ctx.getStr("dir")    
    let items = scanDir(dir, "tree")
    let html = getHTML("tree", items)
    SSE(req):
        patchElements(sse, html, selector="#tree")


proc handleSelectDir(req: Request) =
    let ctx = getContext(req)
    let dir = ctx.getStr("dir")
    let isOpen = ctx.getBool("isOpen")

    if isOpen:
        let items = scanDir(dir, dir)
        let html = getHTML(dir, items)
        SSE(req):
            patchElements(sse, html, selector=fmt"#{stripId(dir)}")
            echo "#" & stripId(dir)
    else:
        let html = fmt"""
            <li id='{stripId(dir)}'>
            <details data-on:toggle="$isOpen=evt.target.open; $id='{stripId(dir)}'; @post('/api/select-dir')">
            <summary>{stripId(dir)}</summary>
            </details>
            </li>
            """
        # let html = fmt"""
        #     <li id='{stripId(dir)}'>
        #     <details data-on:toggle="$isOpen=evt.target.open; $id='html'; @post('/api/select-dir')">
        #     <summary>{stripId(dir)}</summary>
        #     </details>
        #     </li>
        #     """


        SSE(req):
            patchElements(sse, html, selector=fmt"#{stripId(dir)}")


# Callback for router registration
proc register*(router: var Router) =
    router.post("/api/list-globals", handleListGlobals)
    router.post("/api/select-dir", handleSelectDir)


# Create module instance
let wmFileExplorer* = WebModule(
    name: "wmFileExplorer",
    register: register
)
