#!/usr/bin/env ruby
# encoding: binary

require '../common'
require './P58common'

if (i = $*.index('-d'))
  d = $*.delete_at(i+1).to_i
  if d > 19
    d = 19
    puts 'WARNING: The P58 compression does not support a search depth greater than or equal to 20, so a depth of 19 will be used hereafter.'
    pause unless YES
  end
  SEARCH_DEPTH = d
  $*.delete_at(i)
else
  SEARCH_DEPTH = 16
end
QUICK_MODE = $*.delete('-q') # no optimization
if QUICK_MODE and SEARCH_DEPTH > 2
  puts 'WARNING: Quick mode, i.e., no optimization in the Mode-2 compression, is strongly discouraged with a search depth greater than 2.'
  pause unless YES
end
if (i = $*.index('-n'))
  P58INDEX = $*.delete_at(i+1).to_i
  $*.delete_at(i)
else
  P58INDEX = 1
end
if (i = $*.index('-o'))
  P58fNAME = $*.delete_at(i+1)
  $*.delete_at(i)
else
  P58fNAME = nil
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
  suffix = dropExt(BMPfName)
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

# 3) Compress
  tmpFName = P58fNAME || (suffix+'.P58')
  p58index = P58INDEX
  if File.exist? tmpFName
    puts "WARNING: #{tmpFName} already exists, and the file will be overwritten, with potential possibility of data loss! Please backup your file before continuing."
    if p58index < 1
      p58index = 1
      puts "WARNING: The 1-based P58 image index should be greater than or equal to 1 (got #{p58index}), so an index of 1 will be assumed hereafter."
    end
    pause unless YES
    overwrite = true
    f3 = open(tmpFName, 'r+b')
    p58index.times {f3.gets(sep='XX')}
    rpos = f3.pos - 2
    if f3.eof? # append
      noSizeLim = true
      rlen = -1
    else
      r = f3.gets(sep='XX')
      if f3.eof? # the last img
        rlen = r.size + 2 # the length of p58 to be replaced
        noSizeLim = true
      else
        rlen = r.size
        noSizeLim = false
      end
      f3.seek(rpos, 0)
    end
  else
    f3 = open(tmpFName, 'wb')
    if p58index != 1
      puts "WARNING: #{tmpFName} does exists and will thus be created with only 1 image, so the P58 image index (#{p58index}) will be ignored."
      pause unless YES
    end
    overwrite = false
  end
  
  f3.write('XX')
  f3.write([width, height].pack('S2'))
  tlen = 6 # the length of this p58 so far

  for i in 0...4
    curPlane = brgePlane[i]
    pos = 0

    no_deep_mode2_search_till = 0

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
      search_depth = (pos < no_deep_mode2_search_till ? 2 : SEARCH_DEPTH)
      for l in 2..search_depth
      # larger SEARCH_DEPTH is not necessarily better, given the greedy algorithm; see optimization section below. Therefore, do not use a large depth if optimization required
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

# 4) Optimize
      if (!QUICK_MODE) and mode == 2 and opCode > 4 # l > 2
        endInd = pos + re
        pos_tmp_rel = 0
        reduction_tmp_tot = 0
        while pos_tmp_rel < re
          mode_tmp = 0
          pos_tmp_abs = pos+pos_tmp_rel
          curChar_tmp = curPlane[pos_tmp_abs]
          curChar_00orFF = (curChar_tmp == 0 or curChar_tmp == 0xFF)
          re_tmp = findRepTimes(curPlane, pos_tmp_abs, pSize, curChar_tmp) # l_tmp = 1
          reduction_tmp = re_tmp - (curChar_00orFF ? 3 : 5)
  # Scenario 1: A subpattern is more efficent, e.g. XX [00 *6] XX [00 *6] is more efficent than [XX 00 00 00 00 00 00]*2
          if reduction_tmp > 0
            mode_tmp = 1
          else # not worth compressing when `l_tmp`=1
            re_tmp = findRepTimes(curPlane, pos_tmp_abs, pSize, curPlane[pos_tmp_abs, 2]) # l_tmp = 2
            reduction_tmp = re_tmp - 5
            mode_tmp = 2 if reduction_tmp > 0
          end
  # Scenario 2: Copying a previous plane may be more efficent, but the starting point is within the old long pattern
          for j in 0...i
            re_tmp_mode3 = findSimElem(curPlane, pos_tmp_abs, pSize, brgePlane[j]).abs
            reduction_tmp_mode3 = re_tmp_mode3 - 3
            if reduction_tmp_mode3 > 0 and reduction_tmp_mode3 > reduction_tmp
              mode_tmp = 3
              reduction_tmp = reduction_tmp_mode3
              re_tmp = re_tmp_mode3
            end
          end
          if reduction_tmp <= 0
            pos_tmp_rel += 1; next # next byte
          end

          re_tmp_after = pos_tmp_rel+re_tmp - endInd
  # Scenario 3: A subpattern is half within the old long pattern (at the end of it) and half outside, e.g. XX YY [00 *4] XX YY [00 *6] is more efficent than [XX YY 00 00 00 00] *2 00 00
          if re_tmp_after > 0 # if there is pattern after `endInd`, even following the old long pattern method, there may be additional reduction; should correct this part
            reduction_tmp_old_after = re_tmp_after - (((mode_tmp == 1 and curChar_00orFF) or (mode==3)) ? 3 : 5)
            reduction_tmp -= reduction_tmp_old_after if reduction_tmp_old_after > 0 # correction
            reduction_tmp_tot += reduction_tmp # `reduction_tmp` is always > 0
            endInd += re_tmp_after # `no_deep_mode2_search_till`
            break
          end

          reduction_tmp_tot += reduction_tmp
          break if reduction_tmp_tot > reduction # no need to search further
          pos_tmp_rel += re_tmp
        end
        if reduction_tmp_tot > reduction
          no_deep_mode2_search_till = endInd
          next
        end
      end

# 5) Write data
      if mode == 0
        if curChar == 0x58 # escape char 0x58
          f3.write("\x58\x63"); tlen += 2
        else
          f3.write(curChar.chr); tlen += 1
        end
        pos += 1
      else
        f3.write([0x58, opCode].pack('C2'))
        if re > 255
          f3.write([re].pack('S')); tlen += 4
        else
          f3.write([re].pack('C')); tlen += 3
        end
        if mode == 1
          if opCode > 3 # repeat 1 char Y, but in reality have to do this in another equivalent way, i.e. repeat 2 same chars YY
            f3.write(curChar.chr*2); tlen += 2
          end
        elsif mode == 2
          opCode /= 2
          f3.write(curPlane[pos, opCode].pack('C*')); tlen += opCode
        end
        pos += re
      end
    end

    puts "Plane#{i} packed."
  end
  if overwrite
    if rlen == -1
      puts "WARNING: #{tmpFName} does not contain that many (#{p58index}) images. The current image (size = #{tlen}) has been appended to the end of this file. This might cause an error when it is loaded in the T.o.S. game, so please make sure you have backed up your file."
    else
      e = rlen - tlen
      if e < 0
        if noSizeLim
          puts "WARNING: The #{p58index}-th image is the last image in #{tmpFName}. The current image has a larger compressed data length than the original one (#{tlen} vs #{rlen}). This might cause an error when it is loaded in the T.o.S. game, so please make sure you have backed up your file."
        else
          puts "ERROR: The current image has a larger compressed data length than the original #{p58index}-th image in #{tmpFName} (#{tlen} vs #{rlen}). The next one or few image(s) in the P58 file have been corrupted! Please make sure you have backed up your file, and then restore it from the backup."
        end
      else
        puts "The current image (size = #{tlen}) has replaced the #{p58index}-th image (size = #{rlen}) in #{tmpFName}."
        f3.write("\0"*e)
      end
    end
  else
    puts "The current image (size = #{tlen}) has been written to #{tmpFName}."
  end
  f3.close
  f.close
end

if BMPfName.nil?
  puts "Usage: packP58 [-y] [-d <depth>] [-q] <BMP file> [-o <P58 file>] [-n <index>]\n-y     \tOptional: Suppress confirming prompts on warning messages.\n-d <n> \tOptional: Specify the maximum length of repeating patterns to search for during the Mode-2 compression of the P58 data; 1 means no Mode-2 compression; 0 means no compression at all (i.e., supressing all other modes of compression as well). Default is 16.\n\tYou can try setting a large number to maximize the compression ratio, but note that\n\t1) the number should be less than 20,\n\t2) it will take slightly longer time, and\n\t3) given that this is a greedy algorithm, a larger search depth does not necessarily lead to improvement (sometimes can be even worse, especially in the quick mode)!\n-q     \t Optional: Quick mode; no optimization in the Mode-2 compression, which is strongly discouraged when the depth <n> is greater than 2.\n\n<input>\tThe BMP file to be converted into P58. This must be an uncompressed, 4-bit indexed 16-color or 24-bit RGB-color BMP file. For an indexed 16-color BMP, its palette must be the same with that from the game; for an RGB-color BMP, it will be first converted to an indexed 16-color BMP, but the color fidelity cannot be guaranteed.\n\n-o <o> \tYou can specify the output filename here. If the file already exists, the original file will be overwritten! Default is <input>.P58.\n-n <i> \tIf the output file does not exist, this argument will be ignored, and a new P58 file with only 1 image will be created; otherwise, the <i>-th image of the existent P58 file will be replaced by the current image. Note that\n\t1) this number is 1-based (not 0-based),\n\t2) if <i> is greater than the total number of images in the original P58 file, the current image will be appended to the end of the P58 file, and \n\t3) the compressed data length of the current image must be less than or equal to that of the <i>-th image in the original P58 file (When the new data length is smaller, `\0` will be padded at the end to match the original data length); otherwise, the subsequent one or few images of the P58 file will be corrupted! This can be difficult to tell beforehand, so please do backup your original P58 file."
else
  begin; main()
  rescue; printErr
  end
end
pauseExit
