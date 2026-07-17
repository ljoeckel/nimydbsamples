import std/[strutils, strformat]
import mummy, mummy/routers, mummy/datastar
import nimrss
import wmFeedConfig
import std/[times, os, algorithm, sugar]

const MAX_COUNT = 3000

type
    FileEntry = object
        kind: PathComponent
        path: string
        info: FileInfo


proc toDateTimeString(tm: Time): string =
    let dt = times.inZone(tm, local())
    dt.format("dd.MM.YYYY HH:mm:ss")

proc toPermissionString(p: set[FilePermission]): string =
      if fpUserRead in p: result.add("r") else: result.add("-")
      if fpUserWrite in p: result.add("w") else: result.add("-")
      if fpUserExec in p: result.add("x") else: result.add("-")
      if fpGroupRead in p: result.add("r") else: result.add("-")
      if fpGroupWrite in p: result.add("w") else: result.add("-")
      if fpGroupExec in p: result.add("x") else: result.add("-")                  
      if fpOthersRead in p: result.add("r") else: result.add("-")                  
      if fpOthersWrite in p: result.add("w") else: result.add("-")
      if fpOthersExec in p: result.add("x") else: result.add("-")


proc stripId(id: string): string =
    result = id.replace("/", "").replace(".", "").replace("_", "")


proc stripTitle(id: string, title: string): string = 
    if title.startsWith(id):
        let pos = title.rfind("/")
        if pos > 0:
            result = title[pos+1..^1]
        else:
            result = title
    else:
        result = title


proc dir(item: FileEntry): string =
    let id = item.path
    let title = item.path

    result = fmt"""
        <li>
            <details data-on:toggle="$isOpen=evt.target.open; $dir='{id}'; @post('/api/select-dir')">
                <summary>{stripTitle(id, title)}</summary>
                <ul id='{stripId(id)}'></ul>
            </details>
        </li>
    """


proc file(item: FileEntry): string = 
    let id = item.path
    let title = item.path
    let size = hrb(item.info.size)
    let permissions = toPermissionString(item.info.permissions)
    let lastWriteTime = toDateTimeString(item.info.lastWriteTime)
    #let creationTime = toDateTimeString(item.info.creationTime)
    #let lastAccessTime = toDateTimeString(item.info.lastAccessTime)
    #let kind = item.kind

    result = fmt"""
        <tr>
            <td><a href='#{stripId(id)}'>{stripTitle(id, title)}</a></td>
            <td>{lastWriteTime}</td>
            <td>{size}</td>
            <td>{permissions}</td>
        </tr>
    """


proc scanDir(directory: string, id: string): seq[FileEntry] =
    var items: seq[FileEntry]
    var dirs: seq[FileEntry]
    var count = 0
    for kind, path in walkDir(directory):
        var fileEntry: FileEntry
        fileEntry.kind = kind
        fileEntry.path = path

        let rpath = path
        if count <= MAX_COUNT:
            if kind in {pcDir, pcLinkToDir}:
                dirs.add(fileEntry)
            else:
                try:
                  # Retrieve metadata
                  fileEntry.info = getFileInfo(path)
                  items.add(fileEntry)
                except OSError as e:
                  echo "Failed to read file info: ", e.msg                
        inc count

    if count > MAX_COUNT:
        echo fmt"For directory '{directory}': There are {count - MAX_COUNT} more items. Ignored"

    items.sort((x, y) => (
      let c = cmp(x.path, y.path)
      c
    ))
    dirs.sort((x, y) => (
      let c = cmp(x.path, y.path)
      c
    ))

    result.add(dirs)
    result.add(items)


proc getHTML(id: string, items: seq[FileEntry]): string =
    result.add(fmt"<ul class='tree' id='{stripId(id)}'>")
    result.add("<table>")
    for item in items:
        if item.kind in {pcDir, pcLinkToDir}:
            result.add(dir(item))
        else:
            result.add(file(item))
    result.add("</table>")
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
    else:
        let html = fmt"""
            <li id='{stripId(dir)}'>
                <details data-on:toggle="$isOpen=evt.target.open; $id='{stripId(dir)}'; @post('/api/select-dir')">
                    <summary>{stripId(dir)}</summary>
                </details>
            </li>
            """

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