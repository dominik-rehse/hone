Review the change below.

## Plan: authz/owner-rules

### What
The rules in `src/authz/rules.js` answer from the role a person holds and
nothing else. Give `allows` the document as well, and let the person a document
belongs to open it, write it and take it away, whatever role they hold. Add
`deleteDoc(userId, docId)` to `src/api.js` for the delete button, which answers
409 while the document is open in another window, and `docMenu(userId, docId)`,
which lists the buttons the toolbar may draw for one person on one document.

### Why
Everybody in a workspace starts as a viewer, and a viewer cannot write. So a
new joiner writes their own meeting notes by asking an administrator to lift
their role for the afternoon, and support did that eleven times last month.
There is no delete button at all, and the only way to take a draft away is a
request to support.

### How I'll know it works
The person a document belongs to may open it, write it and take it away while
their role alone would not let them. Owning a document gives them nothing else: sharing is
still the administrator's. A guest gets neither on a document that is not
theirs, and an administrator keeps what the role gives them. The delete button
answers 200 and the document is gone, 403 for somebody who may not, and 409
while it is open elsewhere. The toolbar of my own document carries view, edit
and delete.

### Notes for the loop
- Touches `src/authz/rules.js`, `src/authz/can.js` and `src/api.js`, and adds
  `tests/authz/owner.test.js`.
- Not a critical path on its own. The store's own checks stay as they are.
