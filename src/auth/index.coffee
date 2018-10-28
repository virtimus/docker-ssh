module.exports = (authType) ->
  console.log 'authType:', authType
  switch authType
    when 'noAuth' then require './noAuthHandler'
    when 'simpleAuth' then require './simpleAuthHandler'
    when 'cAuth' then require './cAuth'
    when 'multiUser' then require './multiUserAuth'
    when 'publicKey' then require './publicKeyAuth'
    else null
