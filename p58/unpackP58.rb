#!/usr/bin/env ruby
# encoding: binary

require '../common'
require './P58common'

SHOW_CHAR_ART = $*.delete('-p')
COLORIZE_CHAR_ART = $*.delete('-c')
P58fName = $*

def paintChar(colorInd_8pack)
  nybbles = ('%08X' % colorInd_8pack).scan(/./)
  if COLORIZE_CHAR_ART
    cNybbles = ''
    nybbles.each {|i| cNybbles += "\e[48;5;#{CONSOLE_PALETTE[i.to_i(16)]}m #{i}"}
    $charPaint += cNybbles
  else
    $charPaint += ' ' + nybbles.join(' ')
  end
end
def paintCharNL()
  if COLORIZE_CHAR_ART
    $charPaint += "\e[0m\n"
  else
    $charPaint += "\n"
  end
  return $charPaint.size < 65536 # do not proceed if too large
end

def main(p58)
  unless File.exist?(p58)
    puts "WARNING: #{p58} is not a file. Ignored."
    return
  end
  f = open(p58, 'rb')
  basename = File.basename(p58)
  suffix = dropExt(p58)
  iIndex = 0
  while !f.eof?
    iIndex += 1
    d = f.gets(sep='XX').chop.chop # image begins
    puts
    if f.eof?
      puts "WARNING: No more data in #{p58}."
      break
    end
    l = d.length
    puts("WARNING: #{l} dummy bytes `#{d.unpack('H*')[0]}` found before Image ##{iIndex} begins.") unless l.zero?
    puts "Processing Image ##{iIndex} in the stack #{basename}."
    width = getc(f, 2) # 1/8 width
    height= getc(f, 2)
    pSize = width*height # 1/8 total pixels
    raise("The width should not exceed 640, and the height should not exceed 400. Got #{width*8} and #{height}.") if width > 80 or height > 400
    bgrePlane = Array.new(4) {Array.new(pSize, 0)}
    for i in 0..3
      pos = 0
      loop do
        d = getc(f)
        if d == 0x58 # indicates next byte is an operator
          d = getc(f)
          case d # operator
          when 99
            bgrePlane[i][pos] = 0x58; pos += 1
          when 0x40...99
            bgrePlane[i][pos] = d; pos += 1
          when 0..3
            c = (d/2)*0xFF # 0,1: 0x00; 2,3: 0xFF
            t = getc(f, d%2+1) # 0,2: 1-byte char; 1,3: 2-byte word
            t.times {bgrePlane[i][pos] = c; pos += 1} # repeat c (00 or FF) for t times
          when 4..0x27
            t = getc(f, d%2+1) # even number: 1-byte char; odd number: 2-byte word
            d /= 2
            pattern = f.read(d).unpack('C*')
            for j in 0...t # add the following (d//2) bytes for t times (on a rotational basis)
              bgrePlane[i][pos] = pattern[j%d]; pos += 1
            end
          when 0x32..0x3D
            j = (d-50)/4 # the color plane of reference (0-2 = B/R/G, respectively)
            k = d % 4 # remainder: 0,1: invert; 2,3: copy; 0,2: 1-byte char; 1,3: 2-byte word
            t = getc(f, k%2+1)
            if k > 1 # copy
              bgrePlane[i][pos, t] = bgrePlane[j][pos, t]
              pos += t
            else # invert
              t.times {bgrePlane[i][pos] = ~bgrePlane[j][pos] & 0xFF; pos += 1}
            end
          else
            raise("Unknown operator: 0x#{d.to_s(16)}.")
          end
        else
          bgrePlane[i][pos] = d; pos += 1
        end
        e = pos - pSize
        break if e.zero?
        raise("Pixel length larger than expected (#{e} more) in Plane#{i}.") if e>0
      end
      puts "Plane#{i} unpacked."
    end
    cArray = plane2color(bgrePlane, width, height)

    outFName = "#{suffix}_#{iIndex}.bmp"
    g = open(outFName, 'wb')
    g.write('BM') # bmp header signature
    g.write([74+pSize*4].pack('L')) # bmp size
    g.write("\0\0\0\0") # reserved
    g.write([74].pack('L')) # offset = 14 (BMP header)+12 (DIB header)+48 (palette)
    g.write([12, width*8, height, 1, 4].pack('LS4')) # BITMAPCOREHEADER
    g.write(PALETTE.pack('C*')) # lookup table
    cArray.reverse_each {|i| g.write(i.pack('N*'))} # big-endian packing of 32-bit long; note that bmp writes pixels from bottom to top
    g.close
    puts "Bitmap file saved to: #{outFName}"
  end
ensure
  f.close if f
end

system('title') if WIN_OS # this will enable ENABLE_VIRTUAL_TERMINAL_PROCESSING in Win32 console mode, which is critical in enabling ANSI escape sequences
puts "Usage: unpackP58 [-y] [-p [-c]] <p58 files>\n-y     \tOptional: Suppress confirming prompts on warning messages.\n-p     \tOptional: Turn on ASCII painting for each image (recommend off for large images; you may also need to enlarge the console window width (>= image width) in order to render the image properly).\n   -c  \tIf the colorization '-c' option is not set, monochrome chars 0-f will be displayed; if set, colorized pixel backgrounds will be shown (In doing so, your terminal must support ANSI escape sequences).\n\n<paths>\tAn array of P58 image stack files to unpack into 16-color BMPs." if P58fName.empty?
for p58 in P58fName
  begin; main(p58)
  rescue; printErr
  end
end
pauseExit
