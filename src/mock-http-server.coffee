http    = require 'http'

createRecordingProxyServer = exports.createRecordingProxyServer = (options) ->
  { port, targetHost, targetPort } = options
  saveResponse = (req, res, next) ->
    next()
  httpProxy = require("http-proxy")
  httpProxy.createServer(saveResponse, targetPort, targetHost).listen(port)
