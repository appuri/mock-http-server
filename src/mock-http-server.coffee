http          = require 'http'
https         = require 'https'
crypto        = require 'crypto'
querystring   = require 'querystring'
recording     = require '../src/recording-proxy'
playback      = require '../src/playback-server'

FILEVERSION = 1

exports.createRecordingProxyServer = (options) ->
  recordingProxy = new recording.RecordingProxy(options)
  handler = (req, res) -> recordingProxy.proxyRequest(req, res)
  server = (if options.https then https.createServer(options.https, handler) else http.createServer(handler))
  server.recordingProxy = recordingProxy
  server.listen(options.port)
  server

exports.createPlaybackServer = (options) ->
  playbackServer = new playback.PlaybackServer(options)
  handler = (req, res) -> playbackServer.playbackRequest(req, res)
  server = (if options.https then https.createServer(options.https, handler) else http.createServer(handler))
  server.playbackServer = playbackServer
  server.listen(options.port)
  server

exports._generateResponseFilename = (req, hash) ->
  { method, url } = req

  if url.length > 100
    # Hash URL if it is too long
    urlHash = crypto.createHash 'sha1'
    urlHash.update url
    url = urlHash.digest('hex')

  host = ''
  if req.headers?.host
    host = req.headers.host.split(':')[0]

  # Dangerous characters stripped
  filename = querystring.escape("#{method}-#{url}-#{host}".replace(/[\/.:\\?&\[\]'"= ]+/g, '-'))
  
  # Append the hash of the body
  if hash
    filename += '-'
    filename += hash
  filename += '.response'
  { filename, FILEVERSION }
