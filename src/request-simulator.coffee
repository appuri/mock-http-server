barista    = require "barista"
fs         = require "fs"
handlebars = require "handlebars"

#
# RequestSimulator
# =================
# Serves templated responses for registered paths
#
exports.RequestSimulator = class RequestSimulator
  constructor: (@options = {}) ->
    @router = new barista.Router

  # register()
  #   registers a parameterized path to simulate requests for
  #
  #   path        : rails route style path, e.g. /products/:product_id/users/:id
  #   template    : handlebars template that defines request JSON
  #   method      : http method, e.g. 'GET', optional, defaults to 'GET'
  #   dataHandler : callback function that can pre-process data before it is
  #                 applied to the template, optional, defauls to null
  register: (path, template, method, dataHandler) ->
    if not path or not template
      console.error "register() must be called with a path and a template"
      process.exit 1
    @router.match(path, method or "GET").to "",
      path: path
      template: template
      dataHandler: dataHandler

  # respondTo()
  #   attempts to respond to the given path and http method
  #   returns true if it matches a registed path, false otherwise
  #
  #   path         : actual path to serve, e.g. /products/100/users/3
  #   method       : http method, e.g. 'GET', optional, defaults to 'GET'
  #   callback     : upon successfully creating data for the requested path, this
  #                  function is called, optional, defaults to a function that
  #                  simply outputs the data to console
  respondTo: (path, method, callback) ->
    unless callback
      callback = (data) ->
        console.log data
    match = @router.first(path, method or "GET")

    return false  unless match  # simulator will not handle this request

    fs.readFile match.template, "utf8", (err, templateContents) ->
      if err
        console.error "Could not open template file: %s", err
        process.exit 1
      template = handlebars.compile(templateContents + "")
      if match.dataHandler
        match.dataHandler match, (processedData) ->
          callback template(processedData)

      else
        callback template(match)

    # simulator will handle this request
    return true

