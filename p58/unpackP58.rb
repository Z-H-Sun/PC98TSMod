#!/usr/bin/env ruby
SHOW_CHAR_ART = $*.delete('-p')
P58fName = $*

# for PC98 machines, it can display 4096 colors
# but the video RAM can only store 16 of them at a time
# these selected 16 colors are defined by the game progam
PALETTE = [ # BGR (RGB reversed)
0x44, 0x44, 0x44, # 0
0x22, 0x44, 0x77, # 1
0x44, 0x66, 0x99, # 2
0x66, 0x88, 0xBB, # 3
0x88, 0xAA, 0xDD, # 4
0xAA, 0xCC, 0xFF, # 5
0x66, 0x66, 0xDD, # 6
0x88, 0x88, 0xFF, # 7
0xAA, 0xCC, 0xAA, # 8
0xCC, 0xEE, 0xCC, # 9
0xBB, 0x88, 0x88, # A
0xDD, 0xAA, 0xAA, # B
0xFF, 0xCC, 0xCC, # C
0x66, 0x66, 0x66, # D
0xCC, 0xCC, 0xCC, # E
0xFF, 0xFF, 0xFF] # F

### trifling stuff
alias _raise raise
def pause
  if /cygwin|mswin|mingw|bccwin|wince|emx/ =~ RUBY_PLATFORM
    system('pause') # windows
  else
    print 'Press <ENTER> to continue ...'; STDIN.gets
  end
end
def printErr
  print $!.class; print ': '; puts $!
  puts $@[1..-1].join "\n"
  pause # do not immediately quit
  exit!
end
def raise(*argv)
  _raise(*argv)
rescue
  printErr
end
### end of pre-process

def getc(file, len=1) # read byte(s) as char/short/long/long long
  raise('Unexpected End of File.') if file.eof?
  bytes = file.read(len)
  case len
  when 1; p = 'C' # char (unsigned, same below)
  when 2; p = 'S' # short (word)
  when 4; p = 'L' # long (dword)
  when 8; p = 'Q' # long long
  else raise('Unsupported byte array unpacking method.')
  end
  return bytes.unpack(p)[0]
end

def main(p58)
  unless File.exist?(p58)
    puts "WARNING: #{p58} is not a file. Ignored."; puts
    return
  end
  f = open(p58, 'rb')
  suffix = p58.sub(/(.*)\..*$/, '\1')
  iIndex = 0
  while !f.eof?
    iIndex += 1
    d = f.gets(sep='XX').chop.chop # image begins
    if f.eof?
      puts "WARNING: No more data in #{p58}."; puts
      break
    end
    l = d.length
    puts("WARNING: #{l} dummy bytes `#{d.unpack('H*')[0]}` found before Image ##{iIndex} begins.") unless l.zero?
    puts "Processing Image ##{iIndex} in the stack #{File.basename(p58)}."
    width = f.read(2).unpack('S')[0] # 1/8 width
    height= f.read(2).unpack('S')[0]
    pSize = width*height # 1/8 total pixels
    raise("The width should not exceed 640, and the height should not exceed 400. Got #{width*8} and #{height}.") if width > 80 or height > 400
    bgrePlane = [[], [], [], []]
    for i in 0..3
      loop do
        d = getc(f)
        if d == 0x58 # indicates next byte is an operator
          d = getc(f)
          case d # operator
          when 99
            bgrePlane[i].push(0x58)
          when 0x40...99
            bgrePlane[i].push(d)
          when 0..3
            c = (d/2)*0xFF # 0,1: 0x00; 2,3: 0xFF
            t = getc(f, d%2+1) # 0,2: 1-byte char; 1,3: 2-byte word
            t.times {bgrePlane[i].push(c)} # repeat c (00 or FF) for t times
          when 4..0x27
            t = getc(f, d%2+1) # even number: 1-byte char; odd number: 2-byte word
            d /= 2
            pattern = f.read(d).unpack('C*')
            for j in 0...t # add the following (d//2) bytes for t times (on a rotational basis)
              bgrePlane[i].push pattern[j%d]
            end
          when 0x32..0x3D
            j = (d-50)/4 # the color plane of reference (0-2 = B/R/G, respectively)
            k = d % 4 # remainder: 0,1: invert; 2,3: copy; 0,2: 1-byte char; 1,3: 2-byte word
            t = getc(f, k%2+1)
            s = bgrePlane[i].length
            r = bgrePlane[j][s, t]
            if k > 1 # copy
              bgrePlane[i] += r
            else # invert
              r.each{|x| bgrePlane[i].push(~x &0xFF)}
            end
          else
            raise("Unknown operator: 0x#{d.to_s(16)}.")
          end
        else
          bgrePlane[i].push(d)
        end
        e = bgrePlane[i].length - pSize
        break if e.zero?
        raise("Pixel length larger than expected (#{e} more) in Plane#{i}.") if e>0
      end
      puts "Plane#{i} unpacked."
    end
    cArray = []; $charPaint = ''
    for y in 0...height
      colorInd_row = []
      for x in 0...width
        position = x*height+y
        colorInd_8pack = 0 # 8-byte long long, containing 8* pixels (4-bit, 0-15 from the palette) in the same row
        for i in 0...4 # each 1-byte integer in the 2D array contains 8 bits, each specifying the colors in one of the adjacent 8 columns
          byte = bgrePlane[i][position] # this determines the i-th bit of the color index
=begin
          for j in 0...8
            bit = (byte >> j) & 1 # only the j-th bit (big-endian) is important for the j-th column
            colorInd_8pack |= bit << 4*j+i # each of the 4 color planes specifies 1 bit of the 4-bit color
          end
=end # although the for-loop (commented out above) might be easier for understanding, the efficiency is ~3x slower than the bit manipulation below
          # below is the Morton 4D encode algorithm
          # asume `byte` writes 0000 0000 0000 0000 0000 0000 ABCD EFGH
          byte ^= byte<<12; byte &= 0x000f000f # 0000 0000 0000 ABCD 0000 0000 0000 EFGH after this step
          byte ^= byte<< 6; byte &= 0x03030303 # 0000 00AB 0000 00CD 0000 00EF 0000 00GH after this step
          byte ^= byte<< 3; byte &= 0x11111111 # 000A 000B 0000 000D 000E 000F 000G 000H after this step
          colorInd_8pack |= byte << i # i-th plane determines the i-th bit of the 4-bit color index
        end
        colorInd_row.push colorInd_8pack 
      end
      colorInd_row_bytes = colorInd_row.pack('N*') # big-endian packing of 32-bit long long
      cArray.push colorInd_row_bytes
      if SHOW_CHAR_ART
        $charPaint += colorInd_row_bytes.unpack('H*')[0].scan(/./).join(' ') + "\n" # show hex
        if $charPaint.length > 65535
          print 'WARNING: You have chosen to show the ASCII painting; however, this image might be too large to be shown. If you choose to continue anyway, it might take forever to proceed. '
          pause; puts $charPaint
          $charPaint = ''
        end
      end
    end
    puts "Bitmap reconstructed successfully."
    puts $charPaint if SHOW_CHAR_ART

    outFName = "#{suffix}_#{iIndex}.bmp"
    g=open(outFName,'wb')
    g.write('BM') # bmp header signature
    g.write([74+pSize*4].pack('L')) # bmp size
    g.write("\0\0\0\0") # reserved
    g.write([74].pack('L')) # offset = 14 (BMP header)+12 (DIB header)+48 (palette)
    g.write([12, width*8, height, 1, 4].pack('LS4')) # BITMAPCOREHEADER
    g.write(PALETTE.pack('C*')) # lookup table
    cArray.reverse_each {|i| g.write(i)} # note that bmp writes pixels from bottom to top
    g.close
    puts "Bitmap file saved to: #{outFName}"
    puts
  end
  f.close
end

puts "Usage: unpackP58 [-p] <p58 files>\n-p\tOptional: Turn on ASCII painting for each image (recommend off for large images).\n<paths>\tAn array of P58 image stack files to unpack into 16-color BMPs." if P58fName.empty?
for p58 in P58fName
  begin; main(p58)
  rescue; printErr
  end
end
pause
