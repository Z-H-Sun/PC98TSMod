#!/usr/bin/env ruby
# encoding: binary

require './readFDI'

begin
  fp = 'patchTS.txt' # first check pwd
  fp = File.join(APP_DIR, 'patchTS.txt') unless File.exist?(fp) # then check appdir
  open(fp, 'rb') {|f| PLIST = eval(f.read)}
rescue
  puts '`patchTS.txt` not found or corrupted. Please place a functional `patchTS.txt` in the current folder or in the same folder as this program.'; pauseExit
end
unless (fName = $*[0])
  puts "Usage: patchTS [-y] <exe or fdi filename> [exe filename]\n   -y    \tOptional: Suppress confirming prompts on warning messages.\n<exe/fdi>\tThe file to patch. It can be an executable, e.g., MTE.EXE, or an FDI image, e.g., mtower.fdi.\n  [exe]  \tIf an FDI image is given in the first param, you can specify the executable to patch that is located in the root dir in that FDI image. If this is left blank, this program will assume that the autoexec file is the one to patch.\nNote: This program will not backup your original EXE/FDI file. Be careful and backup the file yourself."
  pauseExit
end
f = open(fName, 'r+b')
if f.read(2) != 'MZ'
  begin
    exef = FDI.new(f)
  rescue
    puts fName + ' does not seem to be either an executable file or an FDI image.'
    f.close; pauseExit
  end
  unless (exeFname=$*[1])
    begin
      exeFname = exef.autoexec_exe_name
    rescue
      puts $!; exeFname = 'MTE.EXE'
    end
    print 'You have not specified which executable in the FDI image to be patched; therefore, the autoexec ' + exeFname + ' is assumed to be the one to work on.'
    if YES
      puts
    else
      print ' Is this correct? If yes, press <ENTER> to continue; if no, enter the filename: '
      exeFname = tmp unless (tmp=STDIN.gets.strip).empty?
    end
  end
  begin
    exef.get_file_offsets(exeFname)
  rescue
    printErr
    f.close; pauseExit
  end
else
  exef = f
end
print 'WARNING: This patch tool will not backup your original EXE/FDI file. To avoid potential loss of data, backup the file yourself before going on. You will be the only person who is responsible for any consequences.'
if YES then puts else print ' Please acknowledge this term and '; pause end
puts

begin
  puts 'You can manipulate the following items by entering their corresponding numbers. For example, `124` means that tasks #1, #2, and #4 will be performed.'; puts
  recommended = []
  PLIST.each_with_index do |x, i|
    puts "##{i+1} (recommended: %5s): %s" % x[0, 2]
    recommended << i if x[0]
  end
  puts; print 'If you enter nothing, tasks `'
  recommended.each {|i| print i+1}
  print '` will be performed by default. Indicate which items you would like to go for: '
  tasks = []
  for i in STDIN.gets.scan(/./)
    i = i.to_i-1
    tasks << i if i>=0 and i<PLIST.size
  end
  tasks = recommended if tasks.empty?
rescue Exception
  printErr
  pauseExit
end
for i in tasks.uniq
  begin
    x = PLIST[i][1..-1]
    puts; puts x.shift # x[1]
    warning1 = x.shift
    warning2 = x.shift
    whence = 0
    type = 0 # 1=original; 2=patched; 0=neither
    while !x.empty?
      offset = x.shift
      original = x.shift
      patched = x.shift
      len = original.size
      exef.seek(offset, whence) # first time: absolute offset; later: relative
      d = exef.read(len)
      case d
      when original
        if whence.zero? # first time
          type = 1
        else
          if type != 1 then type = 0; break end
        end
      when patched
        if whence.zero? # first time
          type = 2
        else
          if type != 2 then type = 0; break end
        end
      else
        type = 0; break
      end
      whence = 1 if whence.zero?
    end
    if type.zero?
      print 'The data of the executable file does not seem right. Continue anyway? Enter `R` to restore to the original data or `P` to patch it or anything else to cancel: '
      case STDIN.gets.strip.downcase
      when 'r'; type = 4
      when 'p'; type = 3
      else; next
      end
    end
    if type % 2 == 1
      if type == 1
        print 'This item is considered as ORIGINAL'
        if YES
          puts ' and will be PATCHED.'
        else
          print '. Press <ENTER> to PATCH it, or type anything to cancel: '
          next unless STDIN.gets.strip.empty?
        end
      end
      if warning1
        print warning1
        if YES
          puts
        else
          print ' Are you sure to continue anyway? Press <ENTER> to confirm, or type anything to cancel: '
          next unless STDIN.gets.strip.empty?
        end
      end
    else
      if type == 2
        print 'This item is considered as PATCHED'
        if YES
          puts ' and will be RESTORED.'
        else
          print '. Press <ENTER> to RESTORE it, or type anything to cancel: '
          next unless STDIN.gets.strip.empty?
        end
      end
      if warning2
        print warning2
        if YES
          puts
        else
          print ' Are you sure to continue anyway? Press <ENTER> to confirm, or type anything to cancel: '
          next unless STDIN.gets.strip.empty?
        end
      end
    end
    x = PLIST[i][4..-1] # ignore the first 4 elements
    whence = 0
    while !x.empty?
      offset = x.shift
      print ' +' unless whence.zero?
      print (whence.zero? ? '%08X: ' : '%6s: ') % offset
      len = x[0].size
      exef.seek(offset, whence)
      whence = 1 if whence.zero?
      d = exef.read(len)
      print 'Replaced ['+d.unpack('H*')[0].upcase
      exef.seek(-len, 1)
      d = x.shift(2)[2-type]
      puts '] with ['+d.unpack('H*')[0].upcase+'].'
      exef.write(d)
    end
  rescue
    printErr
    pause unless YES
    next
  end
end
f.close
pauseExit
