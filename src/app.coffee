# **app.coffee**
# Script that is used to create `./bin/mock-http-server`.
#

http    = require 'http'
url     = require 'url'
{argv}  = require 'optimist'
{_}     = require 'underscore'
mock    = require '../src/mock-http-server'

{createRecordingProxyServer, createPlaybackServer} = mock


DEFAULT_FIXTURES = 'fixtures'

help = ->
  console.log "Usage: mock-http-server port [options]"
  console.log "  Where port is to listen on for incoming requests"
  console.log ""
  console.log "Options:"
  console.log "  --record=host:port to record (optional)"
  console.log "       capture all requests and return results"
  console.log "       Note: when this flag is NOT set, mockserver"
  console.log "             will return previously recorded results and"
  console.log "             non-recorded requests will return a 404"  
  console.log "  --fixtures=directory to store files relative to cwd (default ./#{DEFAULT_FIXTURES})"
  console.log ""
  console.log "Examples:"
  console.log "  mock-http-server 9000 --record=www.google.com:80 --fixtures=test"
  console.log "    Forward all requests to www.google.com and record results in ./test"
  console.log "  mock-http-server 9000 --fixtures=test"
  console.log "    Reply to all requests with results recorded from target"

if argv.help or argv._.length < 1
  help()
  process.exit 1

port = parseInt(argv._[0])
if not port? || port == 0
  console.log "Error: must specify a port"
  help()
  process.exit 1

fixtures = argv.fixtures || DEFAULT_FIXTURES
target = argv.record

options = { port, fixtures }
if target?
  targetHostPort = target.split(":")
  targetHost = targetHostPort[0]
  targetPort = (if targetHostPort.length > 1 then parseInt(targetHostPort[1]) else 80)
  console.log "Running in recording mode"
  console.log "  Recording calls to " + target
  options.target = { host: targetHost, port: targetPort }
  # See recording-proxy.coffee
  createRecordingProxyServer options
else
  console.log "Running in playback mode"
  # See playback-server.coffee
  createPlaybackServer options

console.log "  Fixtures directory: ./#{fixtures}"
console.log "  Listening at http://localhost:#{port}/"
