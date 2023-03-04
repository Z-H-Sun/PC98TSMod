#!/usr/bin/env ruby
# encoding: binary

def _exit()
  print('Press <Enter> to exit.'); STDIN.gets; exit
end
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
system('curl -O ' + URL) unless File.exist?(CHARfName) # download the char mapping table
# see also https://harjit.moe/jistables2/jisplane1b.html for a visual comparison
unless File.exist?(CHARfName) then puts("Cannot download char map! Alternatively, you can manually download the plain text file from #{URL}, place it in the same folder, and run this code again."); _exit end

$cmap = {} # double-byte char map
open(CHARfName).each do |line|
  d = line.sub(/#.*/, '').split # remove comments; will get ['0xAAAA', 'U+BBBB']
  next if d.length != 2
  key = d[0].to_i(16)
  if !key.zero? and d[1][/U\+(.{4})$/i] # U+BBBB+CCCC should be excluded
    $cmap[key] = $1.to_i(16)
  end
end
puts 'Char map loaded.'

GTXfName = $*[0]
unless GTXfName then puts("Usage: decodeGTX [-p] [-o <offset>] <GTX filename>\n-p     \tIndicates that `MTE.exe` has been patched to be able to display more Chinese (Kanji) chars, so 2-byte hiragana chars have not been encoded into 1-byte, and the default offset has been changed from 0xB0 to 0xF0.\n-o 0xNN\tIf the offset is not the default value (0xB0 or 0xF0), it can be assigned here. It must be an 8-bit unsigned int (0x00 to 0xFF).\n<path>\tThe GTX or CTX file to be decoded. The decoded, plain text file will be saved as <path>.TXT in UTF-8 encoding."); _exit end
TXTfName = GTXfName + '.TXT'

o = open(TXTfName, 'wb')
f = open(GTXfName, 'rb')
succ = fail = 0
tmp = (MASKHIRAGANA ? 0x65 : 0x10) # 0x65..0x64 will be an empty range
last_byte = -1 # read one more byte if >= 0
f.each_byte do |byte|
  if last_byte < 0
    case byte
    when 0
      c = "|\r\n" # one paragraph ends
    when 1
      c = ";\r\n" # line break
    when tmp..0x64 # hiragana (ignore if MASKHIRAGANA is set true)
      byte = 0x2400|(byte+0x10)
      c = $cmap[byte]
    when 0x65..0xbf # katakana
      byte = 0x2500|(byte-0x45)
      c = $cmap[byte]
    when 0xc0..0xcf # punctuations
      byte = 0x2100|(byte-0xa0)
      c = $cmap[byte]
    else
      last_byte = (byte-OFFSET) &0xff # this is a 8-bit char
      next
    end
  else
    byte = last_byte<<8|byte
    c = $cmap[byte]
    last_byte = -1
  end
    if c
      c = [c].pack('U') unless c.is_a?(String) # unicode to utf-8
      o.write(c); succ += 1
    else
      o.write('[0x'+byte.to_s(16)+']'); fail += 1
    end
end
o.close
f.close
puts "Conversion OK (#{succ} converted; #{fail} retained)."
_exit
