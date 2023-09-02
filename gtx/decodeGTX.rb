#!/usr/bin/env ruby
# encoding: binary

require '../common'
require './GTXcommon'

$cmap = {} # double-byte char map
loadCharMap() {|key, val| $cmap[key] = val}

GTXfName = $*[0]
unless GTXfName
  puts("Usage: decodeGTX [-y] [-p] [-o <offset>] <GTX filename>\n-y     \tSuppress confirming prompts on warning messages.\n-p     \tIndicates that `MTE.exe` has been patched to be able to display more Chinese (Kanji) chars, so 2-byte hiragana chars have not been encoded into 1-byte, and the default offset has been changed from 0xB0 to 0xF0.\n-o 0xNN\tIf the offset is not the default value (0xB0 or 0xF0), it can be assigned here. It must be an 8-bit unsigned int (0x00 to 0xFF).\n<path> \tThe GTX or CTX file to be decoded. The decoded, plain text file will be saved as <path>.TXT in UTF-8 encoding.\n\nIf any 1-byte or 2-byte GTX char could not be decoded, the prompt will be 'Conversion incomplete (... X retained)' where X > 0, and you will be able to see the retained chars in the form of [0xNNMM] in the output text file.")
  pauseExit
end

TXTfName = dropExt(GTXfName) + '.TXT'
if File.exist?(TXTfName)
  puts "Warning: #{TXTfName} already exists. If you choose to continue, the file will be overwritten! "
  pause unless YES
end

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
      byte = 0x2400 | (byte+0x10)
      c = $cmap[byte]
    when 0x65..0xbf # katakana
      byte = 0x2500 | (byte-0x45)
      c = $cmap[byte]
    when 0xc0..0xcf # punctuations
      byte = 0x2100 | (byte-0xa0)
      c = $cmap[byte]
    else
      last_byte = (byte-OFFSET) & 0xff # this is a 8-bit char
      next
    end
  else
    byte = last_byte << 8 | byte
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
puts "Conversion #{fail.zero? ? 'OK' : 'incomplete'} (#{succ} converted; #{fail} retained)."
pauseExit
