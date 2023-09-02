#!/usr/bin/env ruby
# encoding: binary

require '../common'
require './P58common'

if (i = $*.index('-d'))
  SEARCH_DEPTH = $*.delete_at(i+1).to_i
  $*.delete_at(i)
else
  SEARCH_DEPTH = 4
end
BMPfName = $*[0]

def colorDiff(b,g,r, paletteInd) # stackoverflow.com/a/9085524
  b2 = PALETTE[paletteInd*3]
  g2 = PALETTE[paletteInd*3+1]
  r2 = PALETTE[paletteInd*3+2]
  rmean = (r+r2)/2
  dr = r-r2; dg = g-g2; db = b-b2
  return (((512+rmean)*dr*dr)>>8) + 4*dg*dg + (((767-rmean)*db*db)>>8)
end
def bestColorInd(b, g, r) # if rgb color is given, which indexed color is the most similar
  score = 655360 # `colorDiff` will never give a value >= 655360
  ind = 0
  for i in 0...16
    s = colorDiff(b,g,r, i)
    if s < score
      score = s
      ind = i
    end
  end
  return ind
end

# sequential search algorithm to find repeating data
def findRepTimes(array, startInd, endInd, pattern) # pattern can be a single char or an array
  if pattern.is_a?(Array) then l = pattern.length else l = 1; p = pattern end
  curPos = startInd + l
  while curPos < endInd
    p = pattern[(curPos-startInd)%l] if l > 1
    break if array[curPos] != p
    curPos += 1
  end
  return curPos-startInd
end
def findSimElem(array1, startInd, endInd, array2) # same/inverted data from previous planes
  curPos = startInd
  invert = false
  if (t = array1[curPos]) != (p = array2[curPos]) # not "same"
    invert = true
    return 0 if t != (~p &0xFF) # not even "inverted"
  end
  curPos += 1
  while curPos < endInd
    p = array2[curPos]
    p = ~p &0xFF if invert
    break if array1[curPos] != p
    curPos += 1
  end
  # the sign indicates whether to copy or invert
  if invert then startInd-curPos else return curPos-startInd end
end

def main
# 1) Read input BMP
  raise "#{BMPfName} is not a valid file." unless File.exist?(BMPfName)
  f = open(BMPfName, 'rb')
  raise('Not a BMP file!') if f.read(2) != 'BM'
  f.seek(10)
  offset = getc(f, 4)
  case headersize=getc(f, 4)
  when 12,16,64 # OS/2
    width = getc(f, 2)
    height = getc(f, 2)
    bottomUp = true # os/2 bmp writes the last row first
    winFormat = false
  when 40,52,56,108,124 # Windows
    width = getc(f, 4)
    height = getc(f, 4, true) # postive: bottom-top; negative: top-bottom
    bottomUp = (height > 0)
    height = -height unless bottomUp
    winFormat = true
  else raise "Unsupported DIB header size: #{headersize}."
  end
  raise("The width must be a multiple of 8. Got #{width}") unless (width%8).zero?
  raise("The width should not exceed 640, and the height should not exceed 400. Got #{width} and #{height}.") if width > 640 or height > 400
  raise 'The number of color planes must be 1.' if getc(f, 2) != 1
  bitDepth = getc(f, 2)
  if winFormat
    raise 'Compression is not supported.' unless getc(f, 4).zero?
  end
  cArray = Array.new(height) {Array.new}
  heightEnumerator = bottomUp ? (height-1).step(0, -1) : (0...height) # bottom-up or top-down
  case bitDepth
  when 4 # should check look-up table
    f.seek(14+headersize)
    if winFormat # RGBA format; 4-byte rather than 3-byte
      matchLUT = true
      for i in 0...16
        for j in 0...3
          if getc(f) != PALETTE[3*i+j]
            matchLUT = false; break
          end
        end
        f.getc # don't care the 4-th byte
      end
    else
      matchLUT = (f.read(48) == PALETTE.pack('C*'))
    end
    unless matchLUT
      puts 'WARNING: The BMP file is 4-bit, but its palette does not seem to match that of the game. If you choose to continue anyway, the palette from the game will be assumed, and the colors of the generated picture will likely look different from the original BMP.'
      pause unless YES
    end
    f.seek(offset)
    for i in heightEnumerator
      (width/8).times do
        cArray[i].push f.read(4).unpack('N')[0] # big-endian 32-bit long
      end
    end

  when 24
    puts 'WARNING: The BMP file is 24-bit, but the game uses indexed 4-bit images. The program will try to convert this BMP file into a 4-bit image (assuming the palette from the game), but the color may or may not look similar to the original BMP.'
    puts "Converting #{BMPfName}..."
    f.seek(offset)
    for i in heightEnumerator
      (width/8).times do
        colorInd_8pack = 0 # 8-nybble long, containing 8* pixels (4-bit, 0-15 from the palette) in the same row
        7.step(0, -1) do |j|
          colorInd_8pack |= bestColorInd(getc(f), getc(f), getc(f)) << (4*j)
        end
        cArray[i].push colorInd_8pack
      end
    end

    tmpFName = suffix+'_4bit.bmp'
    f2 = open(tmpFName, 'wb')
    f2.write('BM') # see also: unpackP58.rb
    f2.write([74+width*height/2, 0, 74, 12, width, height, 1, 4].pack('L4S4'))
    f2.write(PALETTE.pack('C*')) # lookup table
    cArray.reverse_each {|i| f2.write(i.pack('N*'))}
    f2.close
    puts "The converted, 4-bit BMP is saved to #{tmpFName}."
    if WIN_OS and (!YES)
      print 'An image viewer window will show to display this new BMP. '; pause
      system "rundll32 shimgvw.dll, ImageView_Fullscreen #{File.expand_path(tmpFName).gsub('/', "\\")}"
      print 'If you are satisfied, '
    end
    pause unless YES

  else raise "The bit depth must be 4 (16-color) or 24 (RGB). Got #{bitDepth}."
  end
  puts "Bitmap of size #{width}*#{height}*#{bitDepth} loaded successfully."

# 2) Convert to BRGE plane data
  width /= 8 # now is 1/8 of width
  pSize = width*height

  brgePlane = color2plane(cArray, width, height)

# 3) Compress and write data!
  tmpFName = suffix+'.P58'
  if File.exist? tmpFName
    puts "Warning: #{tmpFName} already exists. If you choose to continue, the file will be overwritten! "
    pause unless YES
  end
  f3 = open(tmpFName, 'wb')
  f3.write('XX')
  f3.write([width, height].pack('S2'))

  for i in 0...4
    curPlane = brgePlane[i]
    pos = 0
    # greedy algorithm
    while pos < pSize
      curChar = curPlane[pos]
      reduction = 0 # the number of bytes saved
      mode = 0 # 0: write directly; 1: 1-char repetition; 2: multi-char rotational repetition; 3: plane copy/invert

unless SEARCH_DEPTH < 1 # when 0: do not compress
      # compression mode 1: repetition (1 char)
      re_tmp = findRepTimes(curPlane, pos, pSize, curChar)
      reduction_tmp = re_tmp - 3
      case curChar
      when 0
        opCode_tmp = 0 # 58 00 TT
      when 0xFF
        opCode_tmp = 2
      else # 58 04 TT CC CC
        opCode_tmp = 4; reduction_tmp -= 2
      end
      if re_tmp > 255 # ; 58 00 TT -> 58 01 TT TT
        opCode_tmp += 1; reduction_tmp -= 1
      end
      if reduction_tmp > 0
        re = re_tmp; reduction = reduction_tmp; opCode = opCode_tmp; mode = 1
      end

      # compression mode 2: rotational repetition
      for l in 2..SEARCH_DEPTH
      # larger SEARCH_DEPTH is not necessarily better, given the greedy algorithm
      # e.g. XX [00 *6] XX [00 *6] is more efficent than [XX 00 00 00 00 00 00]*2
      # one can further optimize this, but I will give up and leave it as is for now
        re_tmp = findRepTimes(curPlane, pos, pSize, curPlane[pos, l])
        reduction_tmp = re_tmp - 3 - l
        opCode_tmp = 2*l
        if re_tmp > 255
          opCode_tmp += 1; reduction_tmp -= 1
        end
        if reduction_tmp > reduction
          re = re_tmp; reduction = reduction_tmp; opCode = opCode_tmp; mode = 2
        end
      end

      # compression mode 3: copy/invert a previous plane
      for j in 0...i
        re_tmp = findSimElem(curPlane, pos, pSize, brgePlane[j])
        invert = (re_tmp < 0)
        re_tmp = -re_tmp if invert
        reduction_tmp = re_tmp - 3
        opCode_tmp = 0x32+4*j
        opCode_tmp += 2 if invert
        if re_tmp > 255
          opCode_tmp += 1; reduction_tmp -= 1
        end
        if reduction_tmp > reduction
          re = re_tmp; reduction = reduction_tmp; opCode = opCode_tmp; mode = 3
        end
      end
end

      if mode == 0
        if curChar == 0x58 then f3.write("\x58\x63") else f3.write(curChar.chr) end # escape char 0x58
        pos += 1
      else
        f3.write([0x58, opCode].pack('C2'))
        f3.write([re].pack(re>255 ? 'S' : 'C'))
        if mode == 1
          f3.write(curChar.chr*2) if opCode > 3
        elsif mode == 2
          f3.write(curPlane[pos, opCode/2].pack('C*'))
        end
        pos += re
      end
    end

    puts "Plane#{i} packed."
  end
  puts "P58 file saved to: #{tmpFName}"
  f3.close
  f.close
end

if BMPfName.nil?
  puts "Usage: packP58 [-y] [-d <depth>] <BMP file>\n-y\tOptional: Suppress confirming prompts on warning messages.\n-d <n>\tOptional: Specify the maximum length of repeating patterns to search for during the Mode-2 compression of the P58 data; 0 means no compression (i.e., supressing all other modes of compression as well). Default is 4. You can try increasing the number (up to 16) to maximize the compression, but note that\n\t1) it will take longer time, and\n\t2) given that this is a greedy algorithm, a larger search depth does not necessarily lead to improvement (sometimes can be even worse)!\n\n<file>\tThe BMP file to be converted into P58. This must be an uncompressed, 4-bit indexed 16-color or 24-bit RGB-color BMP file. For an indexed 16-color BMP, its palette must be the same with that from the game; for an RGB-color BMP, it will be first converted to an indexed 16-color BMP, but the color fidelity cannot guaranteed."
else
  begin; main()
  rescue; printErr
  end
end
pauseExit
