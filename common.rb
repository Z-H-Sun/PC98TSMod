#!/usr/bin/env ruby
# encoding: binary

APP_DIR = File.dirname($Exerb ? ExerbRuntime.filepath : $0) # __FILE__ and $0 will not work properly after packed by EXERB

WIN_OS = (/cygwin|mswin|mingw|bccwin|wince|emx/ =~ RUBY_PLATFORM)
def pause
  if WIN_OS then system('pause') else print 'Press <ENTER> to continue ...'; STDIN.gets end
end

YES = $*.delete('-y') # do not pause
def pauseExit
  pause unless YES
  exit!
end

def printErr
  print $!.class; print ': '; puts $!
  $@.each {|t| puts t}
end

def getc(file, len=1, signed=false) # read byte(s) as (signed/unsigned) char/short/long/long long
  raise('Unexpected EOF.') if file.eof?
  bytes = file.read(len)
  case len
  when 1; p = 'C' # char (unsigned, same below)
  when 2; p = 'S' # short (word)
  when 4; p = 'L' # long (dword)
  when 8; p = 'Q' # long long
  else raise('Unsupported byte array unpacking method.')
  end
  p.downcase! if signed
  return bytes.unpack(p)[0]
end

def dropExt(fName) # filename without extname
  slashInd = (fName.rindex(/[\/\\]/) || -1) + 1 # must exclude dirname first in case the dirname includes a dot
  return fName[0, slashInd] + fName[slashInd..-1].sub(/(.*)\..*$/, '\1')
end
