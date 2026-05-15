import regex
import yottadb
import ../common

let hexpattern = re2"\b[0-9a-fA-F]+\b"
let yearPattern = re2"^[12]\d{3}$"

proc scan() =
    var total, text, hex, year = 0
    for key in OrderItr ^RSSItemFTI:
        inc total
        if yearPattern in key:
            inc year
        elif hexpattern in key:
            inc hex
        else:
            inc text

    echo "Total  :", total
    echo "Year   :", year
    echo "Hex    :", hex
    echo "Text   :", text

if isMainModule:
    let rc = meassure:
        scan()
    echo "rc=", rc