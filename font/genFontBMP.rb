#!/usr/bin/env ruby
# encoding: binary

# This code works only on Windows OS with Chinese (GBK) locale!

f = __FILE__
f = ExerbExerbRuntime.filepath if $Exerb # __FILE__ will not work properly after packed by EXERB
begin
  open(File.join(File.dirname(f), 'CHARS.txt'), 'rb') {|f| (eval(f.read))}
rescue
  puts '`CHARS.txt` not found or corrupted. Please place a functional `CHARS.txt` in the same folder as this program.'; exit
end

FONTNAME = $*[0]
FONTSIZE = $*[1].to_i
FONTOFFSETX = $*[2].to_i
FONTOFFSETY = $*[3].to_i

if FONTNAME.nil? then puts "Usage: genFontBMP <font_name> [font_size] [font_offset_x] [font_offset_y]\nfont_size\tshould be adjusted to make sure each character fills but is still within a 16*16 cell.\nfont_offset\tshould be adjusted in the x and y directions to center the characters in the aforementioned cells.\n\nExample: genFontBMP YaHei-MONO 19 0 1"; exit end

require 'Win32API'
SelectObj = Win32API.new('gdi32', 'SelectObject', 'll', 'l')
DeleteObj = Win32API.new('gdi32', 'DeleteObject', 'l', 'l')
TxtOut = Win32API.new('gdi32', 'TextOut', 'lllpl', 'l')
CrBMP = Win32API.new('gdi32', 'CreateCompatibleBitmap', 'lll', 'l')
SetBrColor = Win32API.new('gdi32', 'SetDCBrushColor', 'll', 'l')

WIDTH = 68 # 68 columns, 94 rows
HEIGHT = 94

pWidth = WIDTH<<4
pHeight = HEIGHT<<4
pSize = (WIDTH*HEIGHT)<<5

hMemDC = Win32API.new('gdi32', 'CreateCompatibleDC', 'l', 'l').call(0) # a memory DC of the screen
hBrush = Win32API.new('gdi32', 'GetStockObject', 'l', 'l').call(18)
hBitmap = CrBMP.call(hMemDC, 32, 32) # this will create a monochrome bitmap as the DC is a memory DC
SelectObj.call(hMemDC, hBitmap)
hFont = Win32API.new('gdi32', 'CreateFontIndirect', 'p', 'l').call([FONTSIZE,0,0,0,0,0,0,0,0,0,0,0,0,FONTNAME].pack('L5C8A*'))
SelectObj.call(hMemDC, hFont)
#metrics = Array.new(20, 0).pack('L11C9')
#Win32API.new('gdi32', 'GetTextMetrics', 'lp', 'l').call(hMemDC, metrics)
#p metrics.unpack('L11C9')

TxtOut.call(hMemDC, 8-FONTOFFSETX, 8-FONTOFFSETY, "сю", 2)
SetBrColor.call(hMemDC, 0)
Win32API.new('user32', 'FrameRect', 'lpl', 'l').call(hMemDC, [7,7,25,25].pack('L4'), hBrush) # draw the central frame
buffer = "\0"*pSize
Win32API.new('gdi32', 'GetBitmapBits', 'llp', 'l').call(hBitmap, 128, buffer)

f = open('test.bmp', 'wb')
f.write('BM')
f.write([190, 0, 62, 40, 32, -32, 1, 1, 0, 128, 0, 0, 0, 0].pack('L4l2S2L6'))
f.write([0, 0xFFFFFF].pack('L2'))
f.write(buffer)
f.close
fName = File.expand_path('test.bmp').gsub('/', "\\")
puts "The sample BMP file is saved to `#{fName}`."
print 'An image viewer window will show to display this BMP. Please make sure that the character is centered and within the central 16*16 black frame. '
system('pause')
system "rundll32 shimgvw.dll, ImageView_Fullscreen #{fName}"
print 'If you are satisfied, press `Enter` to confirm. Otherwise, type anything and then press `Enter` to exit, and you will need to adjust `FONTSIZE`, `FONTOFFSETX`, and `FONTOFFSETY` parameters in such a case. '
exit unless STDIN.gets.strip.empty?

hBitmap2 = CrBMP.call(hMemDC, pWidth, pHeight)
SelectObj.call(hMemDC, hBitmap2)
DeleteObj.call(hBitmap)
SetBrColor.call(hMemDC, 0xFFFFFF)
Win32API.new('user32', 'FillRect', 'lpl', 'l').call(hMemDC, [0,0,pWidth,pHeight].pack('L4'), hBrush) # white bkground
Win32API.new('gdi32', 'SetBkMode', 'll', 'l').call(hMemDC, 1) # transparent mode
for i in 0...WIDTH
  for j in 0...HEIGHT
    TxtOut.call(hMemDC, 16*i-FONTOFFSETX, 16*j-FONTOFFSETY, GBK_CHARS[(i*HEIGHT+j)*2, 2], 2) # each GBK char has 2 bytes
  end
end
buffer = "\0"*pSize
Win32API.new('gdi32', 'GetBitmapBits', 'llp', 'l').call(hBitmap2, pSize,buffer)

f = open('font.bmp', 'wb')
f.write('BM')
f.write([pSize+62,0,62,40,pWidth,-pHeight,1,1,0,pSize,0,0,0,0].pack('L4l2S2L6'))
f.write([0, 0xFFFFFF].pack('L2'))
f.write(buffer)
f.close
fName = File.expand_path('font.bmp').gsub('/', "\\")
puts "The font BMP file is saved to `#{fName}`."
print 'An image viewer window will show to display this BMP. '
system('pause')
system "rundll32 shimgvw.dll, ImageView_Fullscreen #{fName}"

Win32API.new('gdi32', 'DeleteDC', 'l', 'l').call(hMemDC)
DeleteObj.call(hBitmap2)
DeleteObj.call(hFont)
