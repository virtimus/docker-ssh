bunyan  = require 'bunyan'
log     = bunyan.createLogger name: 'simpleAuth'
env     = require '../env'

username = process.env.AUTH_USER
password = process.env.AUTH_PASSWORD

module.exports = (ctx) ->
  if ctx.method is 'password'
    if ctx.password is password
      log.info {container: ctx.username}, 'Authentication succeeded'
      process.env.CNAME = ctx.username
      return ctx.accept()
    else
      log.warn {user: ctx.username, password: ctx.password}, 'Authentication failed'
  ctx.reject(['password'])
