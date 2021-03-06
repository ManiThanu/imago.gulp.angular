fs      = require 'fs'
restler = require 'restler'
walk    = require 'walkdir'
YAML    = require 'js-yaml'
mime    = require 'mime'
hash    = require 'mhash'
Q       = require 'q'

class Upload

  constructor: (inpath, @cb) ->

    @inpath      = inpath
    @opts        = {}
    @exclude     = ['theme.yaml', 'index.html', 'coffee.js', 'scripts.js', 'templates.js', 'application.js', 'application.js.map']
    @domain      = ''
    @version     = null
    @totalfiles  = 0
    @callcounter = 0

    console.log 'this inpath', @inpath

    @run()

  run: ->
    console.log 'getting configuration...'
    @parseYaml()
    @getDomain()
    console.log 'domain is', @domain
    @getNextVersion()

  gaeVersion: ->
    if @opts.gaeversion is 'default'
      return ''
    return '.'+@opts.gaeversion

  getDomain: ->
    @domain = 'http://imagoblobs.appspot.com'
    @domain = 'http://localhost:8080' if @opts.debug

  parseYaml: =>
    yamlPath = @inpath+'/theme.yaml'
    process.kill() unless fs.existsSync yamlPath
    @opts = YAML.safeLoad(fs.readFileSync(yamlPath))

  getNextVersion: ->
    getNextDone = (data) =>
      # console.log 'data', data
      @version = parseInt data
      console.log 'themeversion is', @version
      @walkFiles()

    url = @domain + '/themeupload/next?ns='+ @opts.tenant
    restler.get(url).on('complete', getNextDone)

  pathFilter: (path) =>
    fname = path.split('/')[path.split('/').length-1]
    return false if fs.lstatSync(path).isDirectory()
    return false if fname in @exclude
    return false if fname.indexOf('.') is 0
    true

  walkFiles: ->
    paths        = walk.sync @inpath
    paths        = paths.filter @pathFilter
    @totalfiles  = paths.length
    @callcounter = @totalfiles
    console.log 'starting deployment for', @totalfiles, 'files'
    objs = (@uploadFile filepath for filepath in paths)
    # promisewhen promiseall(objs), @cleanup
    Q.all(objs).then (resolved) =>
      @cleanup()

  flushCache: =>
    console.log 'flushing the cache'
    data =
      data : {key: 'UWSMJGaPRcAmgXbNjOhHYrT2VzIkufKqy9eptsExCQnFD'}
    url = @domain + '/themeupload/flushcache'
    restler.post(url, data).on('complete', (data, response) =>
      console.log('deployment done!')
      @cb()
    )

  cleanup: =>
    console.log 'done uploading files...'
    if @opts.setdefault
      console.log 'going to set the default version to', @version
      url = @domain + '/themeupload/setdefault/' + @opts.tenant + '/' + @version
      restler.get(url).on('complete', @flushCache)
    else
      @flushCache()

  uploadFile: (filepath) ->

    defer = Q.defer()

    uploadBinary = (body) =>
      stats = fs.statSync(filepath)

      data =
        multipart : true
        data : { file : restler.file(filepath, null, stats.size, null, mimetype) }
      console.log 'uploading ->', serving_path

      restler.post(body, data).on('complete', (data, response) =>
          defer.resolve()
        )


    postData = (filedata) =>
      url     = @domain + '/themeupload/uploadurl'
      filedata.namespace = @opts.tenant
      payload = JSON.stringify(filedata)
      restler.post(url, {data : payload}).on('complete', uploadBinary)

    # post the request with the data and get the uploadurl
    serving_path = filepath.split(@inpath)[1]
    mimetype     = mime.lookup serving_path

    filedata =
      path     : serving_path
      mimetype : mimetype
      version  : @version
      sha      : 0

    fs.readFile filepath, (err, data) ->
      filedata.sha = hash('sha224', data)

      postData filedata

    return defer.promise

module.exports = (dest) ->
  defer = Q.defer()

  if fs.existsSync(dest) and fs.existsSync(dest)
    new Upload(dest, -> defer.resolve())

  else
    defer.resolve()
    console.log 'something went wrong'

  defer.promise
