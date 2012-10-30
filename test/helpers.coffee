http        = require 'http'
net         = require 'net'
assert      = require 'assert'
querystring = require 'querystring'

responseWrapper = exports.responseWrapper = (handler, encoding) ->
  (response) ->
    data = []
    response.on 'error', (e) -> handler e
    response.on 'data', (chunk) -> data.push chunk
    response.on 'end', () ->
      concatenateData = ->
        # Copy data into buffer
        totalLength = 0
        for chunk in data
          totalLength += chunk.length
        body = new Buffer(totalLength)
        offset = 0
        for chunk in data
          chunk.copy(body, offset)
          offset += chunk.length
        return if encoding? then body.toString(encoding) else body
      result =
        headers: response.headers
        statusCode: response.statusCode,
        body: concatenateData()
      handler null, result

testHTTPRunning = exports.testHTTPRunning = (message, port=80, host='localhost') ->
  {
    topic: ->
      callback = @callback
      http.get({host, port}, responseWrapper(callback)).on('error', ((e)-> callback(e, null)))
      return

    'should be running': (error, response) ->
      if error or not response
        console.error "\n\n#{error}\n\n#{message}\n\n"
        throw "HTTP server not running"
      else
        assert.equal response.statusCode, 200
  }

requestOptions = exports.requestOptions = (host, port, path = '/', method = 'GET', contentType = 'application/json') ->
  options =
    host: host
    port: port
    method: method
    path: path

  if method == 'POST'
    options.headers =
      'Content-Type': contentType
      'Content-Length': 0
  options

postOptions = (options, body) ->
  options.headers['Content-Length'] = body.length
  {options, body}  

postJSONOptions = exports.postJSONOptions = (host, port, path = '/', params) ->
  options = requestOptions host, port, path, 'POST'
  body = if params? then JSON.stringify params else ''
  postOptions options, body

serialTest = exports.serialTest = (spec) ->
  res = {}
  steps = ({key, func} for key, func of spec when key != 'catch')
  resultsKey = null
  next = (err, args...) ->
    return spec.catch(err) if err
    res[resultsKey] = args[0] if resultsKey and args[0]?
    if steps.length > 0
      {key, func} = steps.shift()
      resultsKey = key
      func.call(next, res) 
  next null
  return

sendRawHttpRequest = exports.sendRawHttpRequest = (options, callback) ->
  {port, host, path} = options
  response = ''
  socket = net.connect port, () -> socket.write("GET http://#{host}#{path} HTTP/1.1\r\nHost: #{host}\r\nAccept: */*\r\n\r\n")
  socket.on 'data', (data) ->
    response += data
    socket.end()
  socket.on 'end', () ->
    httpRegex = /HTTP\/[0-9.]+ ([0-9]+) /gm
    match = httpRegex.exec(response)
    statusCode = match?[1]
    callback(null, { statusCode, response })
  socket.setEncoding()
