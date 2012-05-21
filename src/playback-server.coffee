events      = require 'events'
http        = require 'http'
fs          = require 'fs'
path        = require 'path'
crypto      = require 'crypto'
{_}         = require 'underscore'
mock        = require '../lib/mock-http-server'

exports.PlaybackServer = class PlaybackServer extends events.EventEmitter
  constructor: (@options = {}) ->
    @responses = {}
    @notfound = {}
    fixtureDir = options.fixtures || 'fixtures'
    @fixturePath = "#{__dirname}/../#{fixtureDir}"

  playbackRequest: (req, res) ->
    self = @
    errState = false

    playbackFilename = (filename) ->
      respondWithNotFound = ->
        if @options.printUnknownRequests
          unless @notfound[filename]
            if _.isEmpty(@notfound)
              console.log "Unrecorded requests:"
            @notfound[filename] = true
            console.log "?? #{req.method} #{req.url}"
        res.writeHead 404
        res.end()

      respondWithFileContents = (contents) ->
        undefined
      res.writeHead 555
      res.end()

    req.on "data", (chunk) ->
      req.bodyHash ||= crypto.createHash 'sha1'
      req.bodyHash.update chunk

    req.on "end", ->
      filename = mock._generateResponseFilename(req.method, req.url, req.bodyHash?.digest('hex'))
      playbackFilename filename


  close: ->




