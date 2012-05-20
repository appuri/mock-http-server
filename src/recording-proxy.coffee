http = require 'http'

exports.RecordingProxy = class RecordingProxy
  constructor: (@options = {}) ->
    unless options.target?.host and options.target?.port
      throw new Error("options must contain target.host and target.port")
  proxyRequest: (req, res) ->
    res.writeHead 555, "Content-Type": "text/plain"
    res.end()
  close: -> undefined

