# Cleanup

Delete the orders the QA agent created: every order whose description starts with "QA Agent:".

- Log in as `QA_USERNAME`.
- Find them with `GET /api/orders?search=QA%20Agent:`; it returns a JSON list of `{ id, description }`.
- Delete each one with `DELETE /api/orders/<id>`.
- Leave every other order alone.
