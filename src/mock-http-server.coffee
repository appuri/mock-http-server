http          = require 'http'
https         = require 'https'
querystring   = require 'querystring'
proxy         = require '../lib/recording-proxy'

maxSockets = 100

exports.createRecordingProxyServer = (options) ->
  recordingProxy = new proxy.RecordingProxy(options)
  handler = (req, res) -> recordingProxy.proxyRequest(req, res)
  server = (if options.https then https.createServer(options.https, handler) else http.createServer(handler))
  server.on "close", -> recordingProxy.close()
  server.recordingProxy = recordingProxy
  server.listen(options.port)
  server

exports.getMaxSockets = -> maxSockets
exports.setMaxSockets = (value) -> maxSockets = value
exports._getAgent = (options) ->
  throw new Error("options.host is required to create an Agent.") if not options?.host
  options.port ||= (if options.https then 443 else 80)
  Agent = (if options.https then https.Agent else http.Agent)
  agent = new Agent { host: options.host, port: options.port }
  agent.maxSockets = options.maxSockets || maxSockets
  agent

exports._getProtocol = (options) -> if options.https then https else http

exports._getBase = (options) ->
  result = ->
  if options.https and typeof options.https is "object"
    for key in [ "ca", "cert", "key" ]
      result::[key] = options.https[key] if options.https[key]
  result

exports._generateFilename = (method, url, hash) ->
  # Start with the method name
  filename = method
  # Followed by the path with dangerous characters stripped
  filename += querystring.escape(url.replace(/[\/.:\\?&\[\]'"= ]+/g, '-'))
  # Append the hash of the body
  if hash
    filename += '-'
    filename += hash
  filename



###

  saveResponse = (req, res, next) ->
    console.log ">>> mock-http-server.coffee:6 XXX #{req.method} #{req.url}"
    req.httpVersion = '1.0'
    delete req.headers.connection
    req.on 'data', (chunk) -> console.log ">>> mock-http-server.coffee:7 DATA", chunk.length
    req.on 'end', -> console.log ">>> mock-http-server.coffee:8 END"
    _writeHead = res.writeHead
    res.writeHead = (statusCode, headers) ->
      console.log ">>> mock-http-server.coffee:11 writeHead #{statusCode}", headers
      _writeHead.apply res, arguments
    next()
  httpProxy = require("http-proxy")
  httpProxy.createServer(saveResponse, targetPort, targetHost, {enable: { xforward: false}}).listen(port)


  httpProxy = require("http-proxy")
  proxy = new httpProxy.RoutingProxy()
  http.createServer((req, res) ->
    # buffer = httpProxy.buffer(req)
    # issueProxyRequest = ->
    #   proxyOptions =
    #     host: targetHost
    #     port: targetPort
    #     buffer: buffer
    #   proxy.proxyRequest req, res, proxyOptions
    console.log ">>> mock-http-server.coffee:8 $$$ #{req.method} #{req.url}"
    proxy.proxyRequest req, res, { host: targetHost, port: targetPort }
    # req.on 'end', ->
      # console.log ">>> mock-http-server.coffee:11 end #{req.method} #{req.url}"
    # process.nextTick(issueProxyRequest)
  ).listen(port, '127.0.0.1')
  proxy.on 'end', -> console.log ">>> mock-http-server.coffee:21"

  httpProxy.createServer((req, res, proxy) ->
    req.connection.setKeepAlive false
    buffer = httpProxy.buffer(req)
    console.log ">>> mock-http-server.coffee:8 start #{req.method} #{req.url}"
    req.on 'data', (chunk) ->
      console.log ">>> mock-http-server.coffee:7 data", chunk.length
    req.on 'end', ->
      console.log ">>> mock-http-server.coffee:11 end #{req.method} #{req.url}"
    issueProxyRequest = ->
      proxyOptions =
        host: targetHost
        port: targetPort
        buffer: buffer
      proxy.proxyRequest req, res, proxyOptions
    setTimeout issueProxyRequest, 3000
  ).listen(port)


  saveResponse = (req, res, next) ->
    req.on 'data', (chunk) ->
      console.log ">>> mock-http-server.coffee:7", chunk.length
    req.on 'end', ->
      console.log ">>> mock-http-server.coffee:9 end"
    next()
  httpProxy = require("http-proxy")
  httpProxy.createServer(saveResponse, targetPort, targetHost).listen(port)
###