#!/usr/bin/env ruby
# encoding: binary

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

CONSOLE_PALETTE = [ # 256 Xterm console colors
238, # 444444 => 0
 94, # 875f00 => 1
136, # af8700 => 2
137, # af875f => 3
180, # d7af87 => 4
223, # ffd7af => 5
167, # d75f5f => 6
210, # ff8787 => 7
151, # afd7af => 8
194, # d7ffd7 => 9
103, # 8787af => A
146, # afafd7 => B
189, # d7d7ff => C
241, # 626262 => D
252, # d0d0d0 => E
231] # ffffff => F (ref: https://www.ditig.com/256-colors-cheat-sheet)

def plane2color(bgrePlane, width, height)
  cArray = Array.new(height) {Array.new(width, 0)}
  fill_char_art = SHOW_CHAR_ART; $charPaint = '' if SHOW_CHAR_ART
  for y in 0...height
    for x in 0...width
      position = x*height+y
      colorInd_8pack = 0 # 8-nybble long, containing 8* pixels (4-bit, 0-15 from the palette) in the same row
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
        byte ^= byte << 12; byte &= 0x000f000f # 0000 0000 0000 ABCD 0000 0000 0000 EFGH after this step
        byte ^= byte <<  6; byte &= 0x03030303 # 0000 00AB 0000 00CD 0000 00EF 0000 00GH after this step
        byte ^= byte <<  3; byte &= 0x11111111 # 000A 000B 0000 000D 000E 000F 000G 000H after this step
        colorInd_8pack |= byte << i # i-th plane determines the i-th bit of the 4-bit color index
      end
      cArray[y][x] = colorInd_8pack

      paintChar(colorInd_8pack) if fill_char_art # see `unpackP58.rb`
    end
    fill_char_art = paintCharNL() if fill_char_art # see `unpackP58.rb`
  end
  puts 'Bitmap reconstructed successfully.'
  if SHOW_CHAR_ART
    puts $charPaint
    puts 'WARNING: You have chosen to show the ASCII painting; however, this image is too large to be shown in full. Printing was truncated.' unless fill_char_art
    pause unless YES
  end
  return cArray
end

def color2plane(cArray, width, height)
  brgePlane = Array.new(4) {Array.new(width*height, 0)}
  for y in 0...height
    for x in 0...width
      position = x*height+y
      colorInd_8pack = cArray[y][x]
      for i in 0...4 # the reverse Morton code; see `plane2color`
        byte = (colorInd_8pack >> i) & 0x11111111 # 000A 000B 0000 000D 000E 000F 000G 000H after this step
        byte ^= byte >>  3; byte &= 0x03030303 # 0000 00AB 0000 00CD 0000 00EF 0000 00GH after this step
        byte ^= byte >>  6; byte &= 0x000f000f # 0000 0000 0000 ABCD 0000 0000 0000 EFGH after this step
        byte ^= byte >> 12; byte &= 0x000000ff # 0000 0000 0000 0000 0000 0000 ABCD EFGH after this step
        brgePlane[i][position] = byte
      end
    end
  end
  puts 'Uncompressed BRGE color-plane data reconstructed.'
  return brgePlane
end
