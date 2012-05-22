mock-http-server
================

Generic HTTP Server that can record requests as a proxy and playback as an HTTP server.

Overview
========

`mock-http-server` runs in two modes:

- Recording Mode
- Playback Mode

*Recording Mode* will record all requests to a target server and record the responses.  The 
request signature forms the filename and is derived from the HTTP verb, the path and sha1 hash 
of the request body (if present).  The requests are saved in the fixtures directory.

*Playback Mode* will return the request data saved in the fixtures directory if the request has
been recorded or will return a 404 and display the verb and path on the console output.

Requirements
============

`mock-http-server` requires Node 0.6.0+ and NPM.  It has been tested on 0.6.15.

Setup
=====

If you are generating all traffic from a single machine, then you can run `mock-http-server` locally
and specify the `--record=remote_host:remote_port` to point to the remote service.

If you are stubbing out a service that is accessed by multiple client machines, then 
run `mock-http-server` on the same box as the server it is targeting and either move the 
server to a new port or update clients to point to `mock-http-server`'s listening port.

To install a clean version:

    git clone <your repo>/mock-http-server.git
    cd mock-http-server
    npm install -d

This will install necessary NPM modules.

Verify installation by running:

    npm test

For more information on options:

    ./bin/mock-http-server --help

Example:

    [Start the Recording Proxy]
    ./bin/mock-http-proxy 9000 --record=www.google.com
    Running in recording mode
      Recording calls to www.google.com
      Fixtures directory: ./fixtures
      Listening at http://localhost:9000/
    
    curl http://localhost:9000
    <HTML><HEAD><meta http-equiv="content-type" content="text/html;charset=utf-8">
    <TITLE>302 Moved</TITLE></HEAD><BODY>
    <H1>302 Moved</H1>
    The document has moved
    <A HREF="http://www.google.com/">here</A>.
    </BODY></HTML>
    [Stop the Recording Proxy with Ctrl+C]
    
    [See the fixture data]
    ls -al fixtures/
    cat fixtures/GET-.response
    {
      "method": "GET",
      "url": "/",
      "data": ["PEhUTUw+PEhFQUQ+..."],
      "filename": "GET-.response",
      "statusCode": 302,
      "headers": {
        "location": "http://www.google.com/",
        "cache-control": "private",
        "content-type": "text/html; charset=UTF-8",
        "x-content-type-options": "nosniff",
        "date": "Mon, 21 May 2012 21:36:01 GMT",
        "server": "sffe",
        "content-length": "219",
        "x-xss-protection": "1; mode=block"
      }
    }

    [Start the Playback Server]
    ./bin/mock-http-proxy 9000
    curl http://localhost:9000
    <HTML><HEAD><meta http-equiv="content-type" content="text/html;charset=utf-8">
    <TITLE>302 Moved</TITLE></HEAD><BODY>
    <H1>302 Moved</H1>
    The document has moved
    <A HREF="http://www.google.com/">here</A>.
    </BODY></HTML>
    [Stop the Playback Server with Ctrl+C]

