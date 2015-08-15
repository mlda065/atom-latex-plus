fs = require 'fs'

errorFileLineMessagePattern = ///
  ^(\.\/|[A-D:])(.*\.tex):(\d*):\s(.*)
  ///

module.exports =
class LogParser
  parseLogFile: (log, callback) ->
    errors = []
    fs.readFile log, (err, data) ->
      if(err)
        return err

      bufferString = data.toString().split('\n').forEach (line) ->
        logErrorLine = line.match(errorFileLineMessagePattern)

        unless logErrorLine?
          return

        errorInfo = line.match(errorFileLineMessagePattern)
        error = {
          file:     errorInfo[2]
          line:     errorInfo[3]
          message:  errorInfo[4]
        }

        errors.push error
      callback(errors)