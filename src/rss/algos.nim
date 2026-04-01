import rssatom
import macros
import std/[options, strutils, strformat, typetraits, enumerate]
import yottadb

import httpclient

proc saveInDB(path: seq[string], feed: RSS) =
    # Save the RSS feed
    saveObject(path, feed)

    # # Update the GUID index
    # var upath = path
    # for keys in OrderItr ^RSSItem(upath, -1).keys:
    #     let guid = Get ^RSSItem(keys,"guid")
    #     Set: ^RSSItemGUID(guid,keys) = ""
    #     # + back
    #     let ids = Query ^RSSItemGUID(guid, keys).keys
    #     let title = Get ^RSSItem(keys, "title")
    #     echo "guid:", guid, ", title:", title


# proc saveInDB(line: int, path: seq[string], value: string) =
#     if value.len == 0: return
#     echo $line, ": ", join(path, "."), "=", value
#     Set: ^RSS(path) = value

# proc traverseRSS[T: object | tuple | RSSItem](obj: T, path: var seq[string], itemCnt: var int) =
#   for name, value in fieldPairs(obj):
#     when value is Option[string]:
#       let val = if value.isSome: value.get() else: ""
#       path.add(name)
#       saveInDB(itemCnt, path, val)
#       discard path.pop()
#     elif value is string:
#       path.add(name)
#       saveInDB(itemCnt, path, value)
#       discard path.pop()
#     elif value is seq:
#       if value.len > 0:
#         for i, item in value:
#             itemCnt = i
#             when type(item) is RSSItem:
#                 path.add(name)
#                 path.add($i)
#                 let itm = cast[RSSItem](item)
#                 #let guid = if itm.guid.isSome: itm.guid.get() else: ""
#                 #echo "GUID:", guid
#                 traverseRSS(itm, path, itemCnt)
#                 discard path.pop()            
#                 discard path.pop()
#             else:
#                 path.add(name)
#                 path.add($i)
#                 saveInDB(itemCnt, path, item)
#                 discard path.pop()
#                 discard path.pop()
#     elif value is RSS:
#         path.add(name)
#         traverseRSS(value, path, itemCnt)
#         discard path.pop()
#     elif value is FeedType:
#         discard
#     elif value is RSSEnclosure:
#         path.add(name)        
#         traverseRSS(value, path, itemCnt)
#         discard path.pop()
#     elif value is RSSCloud:
#         path.add(name)        
#         traverseRSS(value, path, itemCnt)
#         discard path.pop()
#     elif value is RSSImage:
#         path.add(name)        
#         traverseRSS(value, path, itemCnt)
#         discard path.pop()
#     elif value is RSSTextInput:
#         path.add(name)        
#         traverseRSS(value, path, itemCnt)
#         discard path.pop()
#     elif value is RSSItem:
#         path.add(name)        
#         traverseRSS(value, path, itemCnt)
#         discard path.pop()
#     elif value is Author:
#         path.add(name)        
#         traverseRSS(value, path, itemCnt)
#         discard path.pop()
#     else:
#         path.add(name)        
#         traverseRSS(value, path, itemCnt)
#         discard path.pop()


