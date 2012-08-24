barista    = require "barista"
fs         = require "fs"
path       = require "path"
handlebars = require "handlebars"
url        = require "url"
extend     = require "xtend"

#
# RequestSimulator
# =================
# Serves templated responses for registered paths
#
exports.RequestSimulator = class RequestSimulator
  constructor: (@options = {}) ->
    @router = new barista.Router
    @simulatorPath = @options.simulatorPath # to locate templates at relative path to the simulator script
    @templates = {}

  # register()
  #   registers a parameterized path to simulate requests for
  #
  #   path        : rails route style path, e.g. /products/:product_id/users/:id
  #   template    : handlebars template that defines request JSON
  #   method      : http method, e.g. 'GET', optional, defaults to 'GET'
  #   dataHandler : callback function that can pre-process data before it is
  #                 applied to the template, optional, defauls to null
  register: (pathName, template, method, dataHandler) ->
    if not pathName or not template
      console.error "register() must be called with a path and a template"
      process.exit 1

    template = path.resolve(@simulatorPath, "..", template)

    if !fs.existsSync template
      console.error "Template #{template} does not exist" 
      process.exit 1

    if !fs.statSync(template).isFile()
      console.error "Template #{template} must be a file" 
      process.exit 1

    @router.match(pathName, method or "GET").to "",
      path: pathName
      template: template
      dataHandler: dataHandler

    # read and cache templates
    self = this
    fs.readFile template, "utf8", (err, templateContents) ->
      if err
        console.error "Could not open template file: %s", err
        process.exit 1
      try
        self.templates[template] = handlebars.compile templateContents + ""
      catch e
        console.error "Error using template #{template} - #{e}"

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

    # add url query params to the available vars
    url_parts = url.parse path, true
    query = url_parts.query
    extend(match, query)

    # get compiled template from cache
    template = @templates[match.template]

    if match.dataHandler
      # allow data handler to process data before applying to template
      match.dataHandler match, (processedData) ->
        callback template(processedData)

    else
      callback template(match)

    # simulator will handle this request
    return true

