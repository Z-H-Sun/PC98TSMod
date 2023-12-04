MASKHIRAGANA = $*.delete('-p') # whether 2-byte hiragana have been encoded into 1-byte

if (i = $*.index('-o')) # assign offset
  offset_str = $*.delete_at(i+1)
  offset = offset_str.to_i # try both 10-base and 16-base to_i
  offset = offset.zero? ? offset_str.to_i(16) : offset
  while offset > 0xff
    offset >>= 8 # take only the highest byte
  end
  OFFSET = offset
  $*.delete_at(i)
else
  OFFSET = MASKHIRAGANA ? 0xF0 : 0xB0 # default offset
end

CHARfName = 'NEC-C-6226-visual.txt'
URL = 'https://harjit.moe/jistables/' + CHARfName
# see also https://harjit.moe/jistables2/jisplane1b.html for a visual comparison

if File.exist?(CHARfName)
  FullCHARfName = CHARfName
else
  fName = File.join(APP_DIR, CHARfName)
  if File.exist?(fName)
    FullCHARfName = fName
  else
    FullCHARfName = CHARfName
    if !system('curl -O ' + URL) # download the char mapping table
      print 'Will retry downlading the char map. '; pause unless YES
      system('curl -O ' + URL)
    end
    unless File.exist?(FullCHARfName)
      puts("Cannot download the char map! Alternatively, you can manually download the plain text file from #{URL}, place it in the same folder, and run this code again. ")
      pauseExit
    end
  end
end

def loadCharMap()
  open(FullCHARfName).each do |line|
    d = line.sub(/#.*/, '').split # remove comments; will get ['0xAAAA', 'U+BBBB']
    next if d.length != 2
    key = d[0].to_i(16)
    if !key.zero? and d[1][/U\+(.{4})$/i] # U+BBBB+CCCC should be excluded
      yield(key, $1.to_i(16)) # this will be replaced by codes in a block
    end
  end
  puts 'Char map loaded.'
end