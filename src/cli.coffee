slurm = require 'slurm'
args = slurm
  o: true   # output path
  t: true   # target platform
  p: true   # production mode
  h: true   # help

if /^(-h)?$/.test args._
  return do ->
    fs = require 'saxon'
    path = require 'path'
    console.log await fs.read path.resolve(__dirname, '../help.md')
    process.exit()

log = require 'lodge'
fatal = (err) ->

  if typeof err is 'string'
    log.error err
    process.exit 1

  if process.env.DEBUG
    stack = err.stack.replace err.name + ': ' + err.message + '\n', ''
    stack = '\n' + log.gray stack

  log.error err.message + (stack or '')
  process.exit 1

if !main = args[0]
  fatal 'must provide an entry path'

if !dest = args.o
  fatal 'must provide an output path (-o)'

if !target = args.t
  # get the ".web" from "bundle.web.js"
  target = /\.([^./]+)\.[^./]+$/.exec dest
  if target then target = target[1]
  else fatal 'must provide a target (-t)'

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

fs = require 'saxon'
path = require 'path'
cush = require 'cush'

cush.on 'warning', (evt) ->
  log.warn evt

cush.on 'error', (evt) ->
  fatal evt.error

dev = !args.p
try bun = cush.bundle main, {target, dev}
catch err
  fatal err

if path.isAbsolute dest
  dest = path.relative process.cwd(), dest

parent = path.dirname dest
try require('fs').mkdirSync parent

# The root of any mapped sources (relative to the sourcemap).
sourceRoot = path.relative parent, ''

if dev
  bun.save = ({content, map}) ->
    await fs.write dest, content + @getSourceMapURL map
    return dest

else do ->
  {sha256} = require 'cush/utils'
  ext = path.extname dest
  bun.save = ({content, map}) ->
    name = dest.slice(0, 1 - ext.length) + sha256(content, 8) + ext
    await fs.write name, content + @getSourceMapURL path.basename(name)
    await fs.write name + '.map', map.toString()
    return name

promise = null
refresh = ->
  try result = await bun.read()
  catch err
    if err.line?
      log ''
      log.error err.message
      log '  ' + log.coal path.relative(process.cwd(), err.file) + ':' + err.line + ':' + err.column
      log ''
      return
    fatal err
  finally
    promise = null

  if bun.missed.length
    log ''
    log log.red 'failed to resolve dependencies: 🔥'
    bun.missed.forEach ([mod, i]) ->
      log '  ' + mod.deps[i].ref + log.coal(' from ') + bun.relative(mod)
    log ''
    return

  if result
    log ''
    log 'bundled in ' + log.lyellow(bun.elapsed + 'ms ⚡️')
    result.map.sourceRoot = sourceRoot
    name = await bun.save result
    log "saved as #{log.lblue name} 💎"
    log ''
    return

# The initial build.
promise = refresh().catch fatal

# Watch for changes in development mode.
dev and cush.on 'change', (file) ->
  if !bun.valid
    log.clear()
    promise or= refresh().catch fatal
  return

# Exit after building in production mode.
dev or promise.then ->
  process.exit 0
