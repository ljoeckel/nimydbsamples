import httpclient
import strutils
import sequtils
import xmlparser
import xmltree
import streams
import sugar
import htmlparser
import options
import types

proc innerTexts*(n: XmlNode): Option[string] =
  if not isNil(n):
    result = some(n.innerText)
  else:
    result = none(string)


proc getAndMap(n: XmlNode, query: string, find: string = ""): seq[string] = 
  if n.isNil:
    echo "ERROR getAndMap node.isNil"
    return

  var find = if find == "": query else: find
  if not isNil(n.child(query)):
    for x in n.findAll(query):
      if x.kind == xnElement:
        for y in x.items:
          result.add(y.text)
      else:
        result.add(x.text)
    #result = map(n.findAll(find), (x: XmlNode) -> string => x.innerText)


proc parseTextxn(node:XmlNode, childQuery:string): Option[string] =
  let 
    tnode = node.child(childQuery)
  if not isNil(tnode):
    case tnode.innerText:
    of "":
      if len(tnode) > 0:
        if tnode[0].kind == xnCData:
          result = some(parseHtml(tnode[0].rawText).innerText)
    else:
      result = some(tnode.innerText)
  else:
    result = none(string)


template `-!`(n: XmlNode, childString: string, body) =
  if not isNil(n.child(childString)):
    body


proc parseMultiple(node:XmlNode, children:seq[string]): Option[string] =
  for kid in children:
    if not isNil(node.child(kid)):
      result = node.parseTextxn(kid)

      
proc getEnclosure(node:XmlNode): RSSEnclosure =
  var 
    encl: RSSEnclosure = RSSEnclosure()
  encl.url = node.attr("url")
  encl.length = node.attr("length")
  encl.enclosureType = node.attr("type")

  return(encl)


proc parseAtomtext(node:XmlNode, childQuery:string, attribute:string): Option[string] =
  let 
    tnode = node.child(childQuery)
  if not isNil(tnode):
    case tnode.attr(attribute):
    of "":
      result = none(string)
    else:
      result = some(tnode.attr(attribute))
  else:
    result = none(string)


proc parseItem(node: XmlNode): RSSItem =
  var 
    item: RSSItem = RSSItem()
  item.title = node.parseTextxn("title")
  item.link = node.parseTextxn("link")
  item.description = node.parseTextxn("description")
  item.author.name = node.parseMultiple(@["author", "dc:creator"])
  item.category = node.getAndMap("category")
  item.comments = node.parseTextxn("comments")
  item.topic = node.parseTextxn("welt:topic") # welt
  item.keywords = node.getAndMap("media:keywords") # welt
  node -! "enclosure":
    let enclosure = node.child("enclosure")
    item.enclosure = getEnclosure(enclosure)
  item.guid = node.parseTextxn("guid")
  item.pubDate = node.parseMultiple(@["pubDate", "created", "dc:date"])
  node -! "source":
    item.sourceUrl = some(node.child("source").attr("url"))
    item.sourceText = some(node.child("source").innerText)

  return item


proc getCloud(channelCloud:XmlNode): RSSCloud =
  var 
    cloud: RSSCloud = RSSCloud()
  cloud.domain = some(channelCloud.attr("domain"))
  cloud.port = some(channelCloud.attr("port"))
  cloud.path = some(channelCloud.attr("path"))
  cloud.registerProcedure = some(channelCloud.attr("registerProcedure"))
  cloud.protocol = some(channelCloud.attr("protocol"))

  return(cloud)


proc getImage(img:XmlNode): RSSImage =
  var 
    image: RSSImage = RSSImage()
  image.url = img.parseTextxn("url")
  if img.attr("rdf:resource").len != 0 and img.attr("rdf:resource") != "":
    image.url = some(img.attr("rdf:resource"))  
  image.title = img.parseTextxn("title")
  image.link = img.parseTextxn("link") 
  image.width = img.parseTextxn("width")
  image.height = img.parseTextxn("height")
  image.description = img.parseTextxn("description")

  return(image)


proc getTextInput(textNode:XmlNode): RSSTextInput =
  var 
    textInput: RSSTextInput = RSSTextInput()
  textInput.title = textNode.parseTextxn("title")
  textInput.description = textNode.parseTextxn("description")
  textInput.name = textNode.parseTextxn("name")
  textInput.link = textNode.parseTextxn("link")

  return(textInput)


proc parseRSS*(data: string): RSS =
  ## Parses the RSS from the given string.
  # Parse into XML.
  var root: XmlNode
  try:
    root = parseXML(newStringStream(data))
  except:
    echo "ERROR: Could not parse xmldata"
    return RSS()

  let channel: XmlNode = root.child("channel")

  # Create the return object.
  var rss: RSS = RSS()
  rss.feedType = RSSv2
  # Fill the required fields.
  if channel.isNil: return rss 
  rss.title = channel.parseTextxn("title")
  rss.link = channel.parseTextxn("link")
  rss.description = channel.parseTextxn("description")

  # Fill the optional fields.
  rss.language = channel.parseMultiple(@["language", "dc:language"])
  rss.copyright = channel.parseTextxn("copyright")
  rss.managingEditor = channel.parseTextxn("managingEditor")
  rss.webMaster = channel.parseTextxn("webMaster")
  rss.pubDate = channel.parseMultiple(@["pubDate", "created", "dc:date"])
  rss.lastBuildDate  = channel.parseTextxn("lastBuildDate")
  rss.category = channel.getAndMap("category")
  rss.generator = channel.parseMultiple(@["generator", "dc:publisher"])
  rss.docs = channel.parseTextxn("docs")
  channel -! "cloud":
    let channelCloud = channel.child("cloud")
    rss.cloud = getCloud(channelCloud)
  rss.ttl = channel.parseTextxn("ttl")
  channel -! "image":
    let img = channel.child("image")
    rss.image = getImage(img)
  rss.rating = channel.parseTextxn("rating")
  channel -! "textInput":
    let textNode = channel.child("textInput")
    rss.textInput = getTextInput(textNode)
  rss.skipHours = channel.getAndMap("skipHours", "hour")
  rss.skipDays = channel.getAndMap("skipDays", "day")

  if not isNil(channel.child("item")):
    rss.items = map(channel.findAll("item"), parseItem)
  else:
    rss.items = map(root.findAll("item"), parseItem)

  # Return the RSS data.
  return rss


proc getAuthor(node:XmlNode): Author =
  var author = Author()
  author.name = node.child("name").innerTexts
  author.email = node.child("email").innerTexts
  author.uri = node.child("uri").innerTexts

  return(author)


proc parseEntry(node: XmlNode): RSSItem =
  var item: RSSItem = RSSItem()
  item.guid = node.parseTextxn("id")
  item.title = node.parseTextxn("title")
  item.link = node.parseAtomtext("link", "href")
  item.description = node.parseTextxn("summary")
  item.content = node.parseTextxn("content")
  node -! "author":
    let authorship = node.child("author")
    item.author = getAuthor(authorship)
  node -! "category":
    item.category = map(node.findAll("category"), (x: XmlNode) -> string => x.attr("term"))
  item.comments = node.parseTextxn("comments")
  item.pubDate = node.parseTextxn("published")
  item.updated = node.parseTextxn("updated")
  node -! "source":
    item.sourceUrl = some(node.child("source").attr("url"))
    item.sourceText = some(node.child("source").innerText)

  return item


proc parseAtom*(data: string): RSS =
  ## Parses the RSS from the given string.
  # Parse into XML.
  var channel: XmlNode
  try:
    channel = parseXML(newStringStream(data))
  except:
    echo "ERROR: Cold not parse xmldata"
    return RSS()

  # Create the return object.
  var rss: RSS = RSS()
  rss.feedType = Atom
  # Fill the required fields.
  rss.id = channel.parseTextxn("id")
  rss.title = channel.parseTextxn("title")
  rss.link = channel.parseAtomtext("link", "href")
  rss.description = channel.parseTextxn("subtitle")
  channel -! "author":
    let authorship = channel.child("author")
    rss.author = getAuthor(authorship)
  rss.language = channel.parseMultiple(@["language", "dc:language"])
  rss.copyright = channel.parseTextxn("rights")
  rss.pubDate = channel.parseMultiple(@["published", "dc:date"])
  rss.lastBuildDate  = channel.parseTextxn("updated")
  channel -! "category":
    rss.category = map(channel.findAll("category"), (x: XmlNode) -> string => x.attr("term"))
  rss.generator = channel.parseMultiple(@["generator", "dc:publisher"])
  rss.docs = channel.parseTextxn("docs")
  rss.ttl = channel.parseTextxn("ttl")
  rss.skipHours = channel.getAndMap("skipHours", "hour")
  rss.skipDays = channel.getAndMap("skipDays", "day")

  if not isNil(channel.child("entry")):
    rss.items = map(channel.findAll("entry"), parseEntry)

  # Return the RSS data.
  return rss


proc loadRSS*(filename: string): RSS =
  ## Loads the RSS from the given ``filename``.

  # Load the data from the file.
  var rss: string = readFile(filename)

  return parseRSS(rss)


proc loadAtom*(filename: string): RSS =
  var
    rss: string = readFile(filename)

  result = parseAtom(rss)


proc getRSS*(url: string): RSS =
  ## Gets the RSS over from the specified ``url``.

  # Get the data.
  var rss: string = newHttpClient().getContent(url)

  return parseRSS(rss)


proc getSomething[T](op: Option[T]): T =
  if op.isSome():
    result = op.get()


proc unpackAuthorAtom(au: Author): XmlNode =
  var
    #author = newElement("author")
    name = newElement("name")
    email = newElement("email")
    uri = newElement("uri")
  name.add newText(au.name.getSomething())
  email.add newText(au.email.getSomething())
  uri.add newText(au.uri.getSomething())
  result = newXmlTree("author", [name, email, uri])


proc unpackEntries(entry: RSSItem): XmlNode =
  var
    id = newElement("id")
    published = newElement("published")
    updated = newElement("updated")
    author = unpackAuthorAtom(entry.author)
    link = newElement("link")
    title = newElement("title")
    summary = newElement("summary")

  id.add newText(entry.guid.getSomething())
  published.add newText(entry.pubDate.getSomething())
  updated.add newText(entry.updated.getSomething())
  link.attrs = {"type":"text/html", "href":entry.link.getSomething() }.toXmlAttributes
  title.add newText(entry.title.getSomething())
  summary.add newText(entry.description.getSomething())
  summary.attrs = {"type":"html"}.toXmlAttributes
  result = newXmlTree("entry", [id, published, updated, author, link, title, summary])

  
proc buildAtom*(atom: RSS): XmlNode = 
  var
   # feed = newElement("feed")
    id = newElement("id")
    title = newElement("title")
    subtitle = newElement("subtitle")
    link = newElement("link")
    rights = newElement("rights")
    generator = newElement("generator")
    author = unpackAuthorAtom(atom.author)
    updated = newElement("updated")
    feedAttr = {"xmlns": "https://datatracker.ietf.org/doc/html/rfc4287", "xml:lang": atom.language.getSomething() }.toXmlAttributes
  id.add newText(atom.id.getSomething())
  title.add newText(atom.title.getSomething())
  subtitle.add newText(atom.description.getSomething())
  subtitle.attrs = {"type":"html"}.toXmlAttributes
  link.attrs = {"rel":"self", "type": "application/atom+xml", "href":atom.link.getSomething()}.toXmlAttributes
  rights.add newText(atom.copyright.getSomething())
  generator.add newText(atom.generator.getSomething())
  updated.add newText(atom.lastBuildDate.getSomething())
  
  var
    feed = newXmlTree("feed", [id, title, subtitle, link, rights, author, updated, generator], feedAttr)
  if len(atom.items) > 0:
    for entry in atom.items:
      let someEntry = unpackEntries(entry)
      feed.add someEntry
  
  return(feed)



proc unpackItems(entry: RSSItem): XmlNode =
  var
    guid = newElement("guid")
    published = newElement("pubDate")
    author = newElement("author")
    link = newElement("link")
    title = newElement("title")
    description = newElement("description")

  guid.add newText(entry.guid.getSomething())
  author.add newText(entry.author.name.getSomething())
  published.add newText(entry.pubDate.getSomething())
  link.add newText(entry.link.getSomething())
  title.add newText(entry.title.getSomething())
  description.add newText(entry.description.getSomething())
  description.attrs = {"type":"html"}.toXmlAttributes
  result = newXmlTree("item", [guid, published, author, link, title, description])

  
proc buildRss*(atom: RSS): XmlNode = 
  var
    rss = newElement("rss")
    title = newElement("title")
    description = newElement("description")
    link = newElement("link")
    rights = newElement("copyright")
    generator = newElement("generator")
    author = newElement("author")
    updated = newElement("lastBuildDate")
    rssattrs = {"version": "2.0"}.toXmlAttributes
  title.add newText(atom.title.getSomething())
  description.add newText(atom.description.getSomething())
  link.add newText(atom.link.getSomething())
  rights.add newText(atom.copyright.getSomething())
  generator.add newText(atom.generator.getSomething())
  author.add newText(atom.author.name.getSomething())
  updated.add newText(atom.lastBuildDate.getSomething())
  
  var
    channel = newXmlTree("channel", [title, description, link, rights, author, updated, generator])
  if len(atom.items) > 0:
    for entry in atom.items:
      let someEntry = unpackItems(entry)
      channel.add someEntry

  rss.attrs = rssattrs
  rss.add channel
  return(rss)


proc dumpAtom*(filename: string, ob: Rss) =
  var
     strm = newFileStream(filename, fmWrite)
  
  let
    atom = buildAtom(ob)

  if not isNil(strm):
    strm.writeLine("""<?xml version="1.0" encoding="UTF-8"?>""")
    strm.write($atom)
    strm.close()


proc dumpRss*(filename: string, ob: Rss) =
  var
     strm = newFileStream(filename, fmWrite)
  
  let
    rss = buildRss(ob)

  if not isNil(strm):
    strm.writeLine("""<?xml version="1.0" encoding="UTF-8"?>""")
    strm.write($rss)
    strm.close()