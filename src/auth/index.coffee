module.exports = (authType) ->
  switch authType
    when 'noAuth' then require './noAuthHandler'
    when 'cAuth' then require './cAuth'
    when 'multiUser' then require './multiUserAuth'
    when 'publicKey' then require './publicKeyAuth'
    else null
