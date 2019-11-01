package test

default allow = false

allow {
	startswith(input.http_request.path, "/api/pets")
	input.http_request.method == "GET"
}

allow {
	input.http_request.path == "/api/pets/2"
	any({
		input.http_request.method == "GET",
		input.http_request.method == "DELETE",
	})
}
