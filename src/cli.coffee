slurm = require 'slurm'
args = slurm
  o: true   # output path
  t: true   # target platform
  f: true   # bundle format
  p: true   # production mode
  h: true   # help


if /^(-h)?$/.test args._
  return do ->
    fs = require 'saxon/sync'
    path = require 'path'
    console.log fs.read path.resolve(__dirname, '../help.md')
    process.exit()


log = require 'lodge'
fatal = (err) ->

  if typeof err is 'string'
    log.error err
    process.exit 1

  if process.env.DEBUG
    stack = parseStack err

  log.error err.message +
    if stack then '\n' + log.gray(stack) else ''
  process.exit 1

parseStack = (err) ->
  if err.stack then err.stack.slice 1 + err.stack.indexOf('\n    at ')

#
# process the arguments
#

if !main = args[0]
  fatal 'must provide an entry path'

if !target = args.t
  fatal 'must provide a target (-t)'

path = require 'path'
CUSH_PATH = path.join process.cwd(), 'node_modules', 'cush'
try require.resolve CUSH_PATH
catch err
  CUSH_PATH = require.resolve 'cush'

cush = require CUSH_PATH

project = cush.project process.cwd()
bundles = project.config.bundles
if config = bundles?[main]
  {dest, format} = config

if !dest or= args.o
  fatal 'must provide an output path (-o)'

format or= args.f or
  path.extname(dest)?.slice(1)

if typeof format is 'string'
  format = cush.formats[format] or require(format)

if format?.constructor != Function
  fatal 'must provide a format (-f)'

config or= {}
config.target = target
config.format = format

# development mode
config.dev = dev = !args.p


#
# file watcher
#

wch = require 'wch'

watching = null

wch.on 'offline', ->
  if watching isnt false
    log.warn 'watch mode is ' + log.lred('disabled'), log.coal '(run `wch start` to enable it)'
    watching = false
  return

wch.on 'connect', ->
  if watching isnt true
    log 'watch mode is ' + log.lgreen 'enabled'
    watching = true
  return

wch.connect()


#
# bundler errors/warnings
#

cush.on 'error', (evt) ->
  fatal evt.error

cush.on 'warning', (evt) ->
  log.warn evt


#
# create the bundle
#

try bundle = cush.bundle main, config
catch err
  switch err.code
    when 'NO_FORMAT'
      fatal 'must provide a bundle format (-f)'
    else fatal err


#
# create dest directory (if needed)
#

fs = require 'saxon/sync'

if path.isAbsolute dest
  dest = path.relative process.cwd(), dest

parent = path.dirname dest
try fs.mkdir parent

# The root of any mapped sources (relative to the sourcemap).
sourceRoot = path.relative parent, ''


#
# the bundle saver
#

if dev
  bundle.save = ({content, map}) ->
    fs.write dest, content + @getSourceMapURL map
    return dest

else do ->
  {sha256} = require CUSH_PATH + '/utils'
  ext = path.extname dest
  bundle.save = ({content, map}) ->
    name = dest.slice(0, 1 - ext.length) + sha256(content, 8) + ext
    fs.write name, content + @getSourceMapURL path.basename(name)
    fs.write name + '.map', map.toString()
    return name


#
# the bundle reader
#

reading = null
readBundle = ->
  log.clear()
  log log.gray('building...')
  try result = await bundle.read()
  catch err

    if err.line?
      source = path.relative '', err.filename or err.file
      source += ':' + err.line + ':' + (err.col ? err.column ? 0)
      log ''
      log.error err.message + log.gray '\n    at ./' + source
      log '\n' + err.snippet if err.snippet
      log log.gray(stack) if stack = parseStack err
      log ''
      return

    throw err

  {state} = bundle
  if state.missing
    log ''
    log log.red 'Failed to resolve dependencies: 🔥'
    state.missing.forEach ([asset, dep]) ->
      log '  ' + dep.ref + log.coal(' from ') + bundle.relative asset.path()
    log ''
    return

  if result
    log ''
    log 'Bundled in ' + log.lyellow(state.elapsed + 'ms ⚡️')
    result.map.sourceRoot = sourceRoot
    name = await bundle.save result
    log "Saved as #{log.lblue name} 💎"
    log ''
    return


# The initial build.
readBundle().catch fatal

# Watch for changes in development mode.
dev and bundle.on 'invalidate', ->
  if !bundle.state.missing
    readBundle().catch fatal

# Exit after reading in production mode.
dev or reading.then ->
  process.exit 0
