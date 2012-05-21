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

exports._generateResponseFilename = (method, url, hash) ->
  # Start with the method name
  filename = method
  # Followed by the path with dangerous characters stripped
  filename += querystring.escape(url.replace(/[\/.:\\?&\[\]'"= ]+/g, '-'))
  # Append the hash of the body
  if hash
    filename += '-'
    filename += hash
  filename += '.response'
  filename
