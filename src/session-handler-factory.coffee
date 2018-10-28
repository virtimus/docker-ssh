bunyan  = require 'bunyan'
Docker  = require 'dockerode'
ssh2 = require 'ssh2'
tmp = require 'tmp'
fs = require 'fs'
FSHandler = require './fsHandler'
constants = require 'constants'

SFTPSession = require './node-sftp-server'
#SFTPSession = sftpServerMod.SFTPSession
OPEN_MODE = ssh2.SFTP_OPEN_MODE
STATUS_CODE = ssh2.SFTP_STATUS_CODE

log     = bunyan.createLogger name: 'sessionHandler'

docker  = new Docker socketPath: '/var/run/docker.sock'


spaces = (text, length) ->(' ' for i in [0..length-text.length]).join ''
header = (container) ->
  "\r\n" +
  " ###############################################################\r\n" +
  " ## Docker SSH ~ Because every container should be accessible ##\r\n" +
  " ###############################################################\r\n" +
  " ## container | #{container}#{spaces container, 45}##\r\n" +
  " ###############################################################\r\n" +
  "\r\n"

module.exports = (filters, shell, shell_user) ->
  instance: ->
    session = null
    channel = null
    stream = null
    resizeTerm = null
    session = null
#    sftpSession = null

    closeChannel = ->
      channel.exit(0) if channel
      channel.end() if channel
    stopTerm = ->
      stream.end() if stream

    close: -> stopTerm()
    handler: (accept, reject) ->
      session = accept()
      termInfo = null
      _container = null
      flt = filters
      flt = {"name":["^/#{process.env.CNAME}$"]} if (process.env.CNAME)
      log.info {envFilters:process.env.CNAME}, 'Exec0'	  

      docker.listContainers {filters:flt}, (err, containers) ->
        containerInfo = containers?[0]
        _containerName = containerInfo?.Names?[0]
        _container = docker.getContainer containerInfo?.Id

        session.once 'exec', (accept, reject, info) ->
          log.info {envFilters:process.env.CNAME, container: _containerName, command: info.command}, 'Exec'
          channel = accept()
          execOpts =
            Cmd: [shell, '-c', info.command]
            AttachStdin: true
            AttachStdout: true
            AttachStderr: true
            Tty: false
          execOpts['User'] = shell_user if shell_user
          _container.exec execOpts, (err, exec) ->
            if err
              log.error {container: _containerName}, 'Exec error', err
              return closeChannel()
            exec.start {stdin: true, Tty: true}, (err, _stream) ->
              stream = _stream
              stream.on 'data', (data) ->
                channel.write data.toString()
              stream.on 'error', (err) ->
                log.error {container: _containerName}, 'Exec error', err
                closeChannel()
              stream.on 'end', ->
                log.info {container: _containerName}, 'Exec ended'
                closeChannel()
              channel.on 'data', (data) ->
                stream.write data
              channel.on 'error', (e) ->
                log.error {container: _containerName}, 'Channel error', e
              channel.on 'end', ->
                log.info {container: _containerName}, 'Channel exited'
                stopTerm()

        session.on 'err', (err) ->
          log.error {container: _containerName}, err

        session.on 'shell', (accept, reject) ->
          log.info {container: _containerName}, 'Opening shell'
          channel = accept()
          channel.write "#{header _containerName}"
          execOpts =
            Cmd: [shell]
            AttachStdin: true
            AttachStdout: true
            AttachStderr: true
            Tty: true
          execOpts['User'] = shell_user if shell_user
          _container.exec execOpts, (err, exec) ->
            if err
              log.error {container: _containerName}, 'Exec error', err
              return closeChannel()
            exec.start {stdin: true, Tty: true}, (err, _stream) ->
              stream = _stream
              forwardData = false
              setTimeout (-> forwardData = true; stream.write '\n'), 500
              stream.on 'data', (data) ->
                if forwardData
                  channel.write data.toString()
              stream.on 'error', (err) ->
                log.error {container: _containerName}, 'Terminal error', err
                closeChannel()
              stream.on 'end', ->
                log.info {container: _containerName}, 'Terminal exited'
                closeChannel()

              stream.write 'export TERM=linux;\n'
              stream.write 'export PS1="\\w $ ";\n\n'

              channel.on 'data', (data) ->
                stream.write data
              channel.on 'error', (e) ->
                log.error {container: _containerName}, 'Channel error', e
              channel.on 'end', ->
                log.info {container: _containerName}, 'Channel exited'
                stopTerm()

              resizeTerm = (termInfo) ->
                if termInfo then exec.resize {h: termInfo.rows, w: termInfo.cols}, -> undefined
              resizeTerm termInfo # initially set the current size of the terminal
        
        # refs: https://github.com/mscdex/ssh2#password-and-public-key-authentication-and-non-interactive-exec-command-execution      
        session.on 'sftp', (accept, reject) ->
        	log.info {}, 'Client SFTP session'
        	openFiles = {}
        	handleCount = 0
        	sftpStream = accept()
        	log.info 'SFTPSession' , SFTPSession
        	sftpSession = new SFTPSession(sftpStream)
        	fsHandler = new FSHandler()
        	sftpSession.on 'stat' , (path, statkind, statresponder) ->
        	  log.info 'statBegin'
        	  fsHandler.doStat(path, statkind,statresponder)
        	sftpSession.on 'readdir', (path, responder) ->
        	  log.info 'readdirBegin'
        	  fsHandler.doReadDir(path,responder)
          sftpSession.on 'readfile', (path, writestream) ->
            log.info 'readfileBegin'
            fsHandler.doReadFile(path, writestream)
          sftpSession.on 'writefile', (path, readstream) ->
            log.info 'writefileBegin'
            fsHandler.doWriteFile(path, readstream)        	  

          #return _this._session_start_callback(session);          
        	#// `sftpStream` is an `SFTPStream` instance in server mode
        	#// see: https://github.com/mscdex/ssh2-streams/blob/master/SFTPStream.md
        	#sftpStream = accept()
        	sftpStream.on 'OPEN1', (reqid, filename, flags, attrs) ->
        		#// only allow opening /tmp/foo.txt for writing
        		if (filename != '/tmp/foo.txt' || !(flags & OPEN_MODE.WRITE))
        		  return sftpStream.status(reqid, STATUS_CODE.FAILURE);
        		#// create a fake handle to return to the client, this could easily
        		#// be a real file descriptor number for example if actually opening
        		#// the file on the disk
        		handle = new Buffer(4)
        		openFiles[handleCount] = true
        		handle.writeUInt32BE(handleCount++, 0, true)
        		sftpStream.handle(reqid, handle)
        		log.info {}, 'Opening file for write'
        	sftpStream.on 'WRITE1', (reqid, handle, offset, data) ->
        		if (handle.length != 4 || !openFiles[handle.readUInt32BE(0, true)])
        			return sftpStream.status(reqid, STATUS_CODE.FAILURE)
        		#// fake the write
        		sftpStream.status(reqid, STATUS_CODE.OK)
        		inspected = require('util').inspect(data)
        		log.info 'Write to file at offset %d: %s', offset, inspected
        	sftpStream.on 'CLOSE1', (reqid, handle) ->
        		fnum = null
        		if (handle.length != 4 || !openFiles[(fnum = handle.readUInt32BE(0, true))])
        		  return sftpStream.status(reqid, STATUS_CODE.FAILURE)
        		delete openFiles[fnum]
        		sftpStream.status(reqid, STATUS_CODE.OK)
        		log.info 'Closing file'
          sftpStream.on 'READLINK1', (reqid, handle, offset, length) ->
            log.info 'handler onREADLINK'
            if (handle.length != 4 || !openFiles[handle.readUInt32BE(0, true)])
              return sftpStream.status(reqid, STATUS_CODE.FAILURE)
            #// fake the read
            state = openFiles[handle.readUInt32BE(0, true)]
            if (state.read)
              sftpStream.status(reqid, STATUS_CODE.EOF)
            else
              state.read = true
              sftpStream.data(reqid, 'bar')
              log.info 'Read from file at offset %d, length %d', offset, length        		
        	sftpStream.on 'STAT1', (reqid, path) ->
        	  log.info 'handler onSTAT'
	          if (path != '/tmp/foo.txt')
	            return sftpStream.status(reqid, STATUS_CODE.FAILURE)
	          mode = constants.S_IFREG; #// Regular file
	          mode |= constants.S_IRWXU; #// read, write, execute for user
	          mode |= constants.S_IRWXG; #// read, write, execute for group
	          mode |= constants.S_IRWXO; #// read, write, execute for other
	          sftpStream.attrs(reqid, {
	            mode: mode,
	            uid: 0,
	            gid: 0,
	            size: 3,
	            atime: Date.now(),
	            mtime: Date.now()
	          })
          sftpStream.on 'LSTAT1', (reqid, path) ->
            if (path != '/tmp/foo.txt')
              return sftpStream.status(reqid, STATUS_CODE.FAILURE)
            mode = constants.S_IFREG; #// Regular file
            mode |= constants.S_IRWXU; #// read, write, execute for user
            mode |= constants.S_IRWXG; #// read, write, execute for group
            mode |= constants.S_IRWXO; #// read, write, execute for other
            sftpStream.attrs(reqid, {
              mode: mode,
              uid: 0,
              gid: 0,
              size: 3,
              atime: Date.now(),
              mtime: Date.now()
            }) 	                  	            

        session.on 'pty', (accept, reject, info) ->
          x = accept()
          termInfo = info

        session.on 'window-change', (accept, reject, info) ->
          log.info {container: _containerName}, 'window-change', info
          resizeTerm info
