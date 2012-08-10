mock-http-server
================

Generic HTTP Server that can record requests as a proxy and playback as an HTTP server.

Overview
========

`mock-http-server` runs in these modes:

- Recording Mode
- Playback Mode
- Simulator Mode

*Recording Mode* will record all requests to a target server and record the responses.  The 
request signature forms the filename and is derived from the HTTP verb, the path and sha1 hash 
of the request body (if present).  The requests are saved in the fixtures directory.

*Playback Mode* will return the request data saved in the fixtures directory if the request has
been recorded or will return a 404 and display the verb and path on the console output.

*Simulator Mode* will return the request data saved in the fixtures directory if the request has
been recorded or will pass the request to a simulator file to handle.  The simulator allows templating
of responses for uses where the data can be algorithmically generated such as load testing.

Requirements
============

`mock-http-server` requires Node 0.8.0+ and NPM.  It has been tested on 0.8.2+.

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
    npm install

This will install necessary NPM modules.

Verify installation by running:

    npm test

For more information on options:

    ./bin/mock-http-server --help

Example:

    [Start the Recording Proxy]

    ./bin/mock-http-server 9000 --record=www.google.com
    Running in recording mode
      Recording calls to www.google.com
      Fixtures directory: ./fixtures
      Listening at http://localhost:9000/
    
    curl http://localhost:9000
    (HTTP response)
    
    [Stop the Recording Proxy with Ctrl+C]
    
    [See the fixture data]

    ls -al fixtures/
    cat fixtures/GET-.response
    {
      "method": "GET",
      "url": "/",
      "filename": "GET-.response",
      "statusCode": 200,
      "headers": {
        ...
      }
      "data": []
    }

    [Start the Playback Server]

    ./bin/mock-http-server 9000
    curl http://localhost:9000
    (HTTP response)

    [Stop the Playback Server with Ctrl+C]

    [Start the Playback Server with Request Simulation]

    ./bin/mock-http-server 9000 --simulator /full/path/to/simulator.js
    curl http://localhost:9000/pattern/specified/in/simulator
    (HTTP response)

    [Stop the Playback Server with Ctrl+C]


Usage:

    ./bin/mock-http-server --help

Request Simulation 
------------------

This section describes what request simulation is and how to set it up during playback mode. 

Given there is a captured request with path `/user/323345`, where `323345` is a user id, request simulation can be used to respond to paths with `/user/:user_id` pattern, e.g. `/user/1000`. To achieve this, write a simulator.js script and convert the captured request into a suitable template.

simulator.js:

    module.exports = function(requestSimulator) {
      requestSimulator.register(  '/users/:user_id', 
                                  'templates/user.template', 
                                  'GET');
    }

templates/user.template:

    {
      "method": "GET",
      "statusCode": 200,
      "headers": {
        "content-type": "application/json",
        "date": "Thu, 02 Aug 2012 23:44:56 GMT",
        "connection": "keep-alive",
        "transfer-encoding": "chunked"
      },
      "body": "{\"message\": \"Hello to user {{user_id}}\" }"
    }

Usage:

    ./bin/mock-http-server 9000 --simulator /full/path/to/simulator.js
    curl http://localhost:9000/users/2000
    {"message": "Hello to user 2000"}


Here the simulator registers for a path with format `/users/:user_id`. When a request that matches this path (e.g. `http://localhost:9000/users/2000`) is received, the corresponding template `templates/user.template` is loaded and is processed using [handlebars](http://handlebarsjs.com/expressions.html), passing in any paramters that were found on the path (`{user_id: 2000}`). The resulting JSON is used to respond to the request.

Notes:

* Only `url.pathname` (e.g. `/path/here` from `http://somehost.com:9000/path/here?param1=blah`) is used for matching.
* template path specified in simulator is relative to `` `pwd` ``

### Data transformation

Use data transformation callback when a given template needs additional parameters or some of the parameters found on the URL need to be transformed (for example, the template needs `username` but URL has `user_id`).

See data transformation callback specified in the `requestSimulator.register()` function call below.

simulator.js:

    module.exports = function(requestSimulator) {
      requestSimulator.register(  '/users/:user_id', 
                                  'templates/user.template', 
                                  'GET', 
                                  function(data, callback) {
                                    var users = {2000: "Mr. Bean"}
                                    data.user_name = users[data.user_id] || "User " + data.user_id 

                                    callback(data)
                                  }
                                );


templates/user.template:

    {
      "method": "GET",
      "statusCode": 200,
      "headers": {
        "content-type": "application/json",
        "date": "Thu, 02 Aug 2012 23:44:56 GMT",
        "connection": "keep-alive",
        "transfer-encoding": "chunked"
      },
      "body": "{\"message\": \"Hello {{user_name}}\" }"
    }

Usage:

    ./bin/mock-http-server 9000 --simulator /full/path/to/simulator.js

    curl http://localhost:9000/users/2000
    {"message": "Hello Mr. Bean"}

    curl http://localhost:9000/users/9999
    {"message": "Hello User 9999"}
