"use strict";

var fs = require('fs');

var FSHandler = (function() {
	
	function FSHandler() {
		this.sftpStream = null;
		this.reqid = null;
		this.rootDir ='/i3c/data/sftp';
	}
	
	FSHandler.prototype.doStat = function(path, statkind,statresponder){
		console.log('FSHandler.doStat');
		fs.stat(this.rootDir+path, function (err, stats) {
			   if (err) {
			      console.error(err);
			      return statresponder.nofile();
			   }
			   console.log(stats);
			   console.log("Got file info successfully!");
			   
			   // Check file type
			   console.log("isFile ? " + stats.isFile());
			   console.log("isDirectory ? " + stats.isDirectory());
			   if (stats.isFile()){//file
				    statresponder.is_file();           // Tells statresponder that we're describing a file.
				    statresponder.permissions = 0o644; // Octal permissions, like what you'd send to a chmod command
				    statresponder.uid = stats.uid;             // User ID that owns the file.
				    statresponder.gid = stats.gid;             // Group ID that owns the file.
				    statresponder.size = stats.size;         // File size in bytes.
				    statresponder.atime = stats.atime/ 1000 | 0;      // Created at (unix style timestamp in seconds-from-epoch).
				    statresponder.mtime = stats.mtime/ 1000 | 0;     // Modified at (unix style timestamp in seconds-from-epoch).
				    statresponder.file();   // Tells the statter to actually send the values above down the wire.				   
			   } else if (stats.isDirectory()) {//dir
			        statresponder.is_directory(); // Tells statresponder that we're describing a directory.
			        statresponder.permissions = 0o755; // Octal permissions, like what you'd send to a chmod command
			        statresponder.uid = stats.uid; // User ID that owns the file.
			        statresponder.gid = stats.gid; // Group ID that owns the file.
			        statresponder.size = stats.size;  // File size in bytes.
			        statresponder.atime = stats.atime/ 1000 | 0; // Created at (unix style timestamp in seconds-from-epoch).
			        statresponder.mtime = stats.mtime/ 1000 | 0; // Modified at (unix style timestamp in seconds-from-epoch).
			        statresponder.file(); // Tells the statter to actually send the values above down the wire.				   
			   } else {
				      console.error("[FSHandler] Unimplemented for fileType:"+stats);
				      return statresponder.nofile();				   
			   }
			});
	}
	
	FSHandler.prototype.doReadDir = function(path, responder){
		console.log('[FSHandler.doReadDir] start ...');
	      var dirs, i, j, results;
	      
	      var rootPath = (path.endsWith("/"))?this.rootDir+path:this.rootDir+path+"/";
	      console.warn("Readdir request for path: " + path);
	      dirs = [];
	      fs.readdirSync(rootPath).forEach(file => {
	    	  console.log('[FSHandler.doReadDir] file:'+file);
	    	  dirs.push(file);
	    	})
		 i = 0;
	     responder.on("dir", function() {
	         if (dirs[i]) {
	           console.warn("Returning directory "+rootPath+" entry: " + dirs[i]);
	           var stats = fs.statSync(rootPath+dirs[i]);
	           
	           var attrs = {
	        			'mode': ((stats.isDirectory())?fs.constants.S_IFDIR:fs.constants.S_IFREG) | 0o644, 	// Bit mask of file type and permissions 
	        			'permissions': 0o644, 					// Octal permissions, like what you'd send to a chmod command
	        			'uid': stats.uid, 								// User ID that owns the file.
	        			'gid': stats.gid, 								// Group ID that owns the file.
	        			'size': stats.size, 							// File size in bytes.
	        			'atime': stats.atime/ 1000 | 0,					// Created at (unix style timestamp in seconds-from-epoch).
	        			'mtime': stats.mtime/ 1000 | 0 					// Modified at (unix style timestamp in seconds-from-epoch).
	        		}
	           
	           responder.file(dirs[i], attrs);
	           return i++;
	         } else {
	           return responder.end();
	         }
	     });
	}
	
	FSHandler.prototype.doReadFile = function(path, writestream){
		console.log('[FSHandler.doReadFile] start ...file:'+path);	
    	var rootPath = this.rootDir+path;
        return fs.createReadStream(rootPath).pipe(writestream);
    }
	
	FSHandler.prototype.doWriteFile = function(path, readstream){
		console.log('[FSHandler.doWriteFile] start ...');
		var rootPath = this.rootDir+path;
        var something;
        something = fs.createWriteStream(rootPath);
        readstream.on("end",function() {console.warn("Writefile request has come to an end!!!")});
        return readstream.pipe(something);
	}	
	
	return FSHandler;
})();


module.exports = FSHandler