import std/macros
import std/json

proc getClearPatch*[T](obj: T): JsonNode =
  ## Iterates over fields and returns a JSON object containing 'null' for every non-empty field.
  result = newJObject()
  for name, value in obj.fieldPairs:
    when value is string:
      if value.strip() != "":
        result[name] = newJNull()
    elif value is bool:
      if value:
        result[name] = newJNull()

# proc extractFields*(node: JsonNode, fields: seq[string] = @[]): JsonNode =
#     if fields.len == 0:
#         return node
#     else:
#         result = %* {}
#         for field in fields:
#             try:
#               if node.contains(field):
#                   result.add(field, node[field])            
#             except:
#               echo "Error when adding field ", field, " to JsonNode"

proc filterPatch*[T](obj: T, fields:seq[string]): JsonNode =
    # add only fields from 'obj' which are also in 'fields'
    if fields.len == 0:
      return %obj
    else:
      result = newJObject()
      for name, value in obj.fieldPairs: 
          for nm in fields:
              if nm == name: result[name] = %value


macro getFieldAsString*(obj: auto, fieldName: string): string =
  let t = obj.getTypeInst()
  var impl = t.getTypeImpl()
  if impl.kind == nnkRefTy: impl = impl.getTypeImpl()
  
  # Wir nehmen die RecList des Objekts (Index 2 bei nnkObjectTy)
  let recList = impl[2] 
  let typeName = t.repr # Sicherer Weg, den Typnamen für die Fehlermeldung zu bekommen

  result = nnkCaseStmt.newTree(fieldName)
  for identDefs in recList:
    if identDefs.kind == nnkIdentDefs:
      for i in 0 .. identDefs.len - 3:
        let f = identDefs[i]
        result.add nnkOfBranch.newTree(
          newLit($f), 
          quote do: $(`obj`.`f`)
        )
  
  result.add nnkElse.newTree(quote do:
    (echo "WARNUNG: Feld '" & `fieldName` & "' existiert nicht in " & `typeName`; "")
  )

macro setFieldFromString*(obj: var auto, fieldName: string, value: string) =
  let t = obj.getTypeInst()
  var impl = t.getTypeImpl()
  if impl.kind == nnkRefTy: impl = impl.getTypeImpl()
  
  let recList = impl[2]
  let typeName = t.repr

  result = nnkCaseStmt.newTree(fieldName)
  for identDefs in recList:
    if identDefs.kind == nnkIdentDefs:
      let fType = identDefs[^2]
      for i in 0 .. identDefs.len - 3:
        let f = identDefs[i]
        
        let setter = if fType.eqIdent("string"):
                       quote do: `obj`.`f` = `value`
                     elif fType.eqIdent("int"):
                       quote do: `obj`.`f` = parseInt(`value`)
                     elif fType.eqIdent("float"):
                       quote do: `obj`.`f` = parseFloat(`value`)
                     elif fType.eqIdent("bool"):
                       quote do: `obj`.`f` = parseBool(`value`)
                     else:
                       quote do: discard
        
        result.add nnkOfBranch.newTree(newLit($f), setter)
  
  result.add nnkElse.newTree(quote do:
    echo "FEHLER: Kann Feld '" & `fieldName` & "' nicht setzen (unbekannt in " & `typeName` & ")"
  )

if isMainModule:
  # --- Test ---
  type
    Person = object
      id: int
      firstname: string
      calling_code: string

  let p = Person(id: 7, firstname: "Lothar", calling_code: "+49")
  let FIELDS = @["firstname", "calling_code", "id"]

  for field in FIELDS:
    # Das hier wird nun korrekt zu einem case-Statement evaluiert
    echo "Wert für ", field, ": ", p.getFieldAsString(field)