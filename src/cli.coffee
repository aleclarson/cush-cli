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
log.prefix log.lgreen '[cli]'

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

if dev
  bun.save = ->
    {content, map} = await @_result
    await fs.mkdir path.dirname(dest)
    await fs.write dest, content + @getSourceMapURL map
    return dest

else
  {sha256} = require 'cush/utils'
  bun.save = ->
    {content, map} = await @_result
    name = path.basename(dest); i = name.indexOf '.'
    name = name.slice(0, i) + '.' + sha256(content, 8) + name.slice(i)
    name = path.join path.dirname(dest), name
    await fs.mkdir path.dirname(name)
    await fs.write name, content + @getSourceMapURL name
    await fs.write name + '.map', map.toString()
    return name

promise = null
refresh = ->
  result = await bun.read()
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
    name = await bun.save()
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
