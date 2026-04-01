// Reveal a row identified by 'rowid' in a table
function reveal( rowid ) {
    const row = document.getElementById(rowid);
    if (!row) return;  // row with id not found
    const isEmpty = row.textContent.trim() === "";
    if (!isEmpty) {
        row.scrollIntoView({ behavior: 'smooth', block: 'center' });
    }
}