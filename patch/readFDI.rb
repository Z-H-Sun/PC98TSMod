#!/usr/bin/env ruby
# encoding: binary
# references:
# http://justsolve.archiveteam.org/wiki/Anex86_PC98_floppy_image
# https://literateprograms.org/fat12_floppy_image__python_.html
# https://www.win.tue.nl/~aeb/linux/fs/fat/fat-1.html
# http://www.c-jump.com/CIS24/Slides/FAT/lecture.html

def getc(file, len, signed=false) # read byte(s) as char/short/long/long long
  raise('Unexpected EOF.') if file.eof?
  bytes = file.read(len)
  case len
  when 1; p = 'C' # char (unsigned, same below)
  when 2; p = 'S' # short (word)
  when 4; p = 'L' # long (dword)
  when 8; p = 'Q' # long long
  else raise('Unsupported byte array unpacking method.')
  end
  p.downcase! if signed
  return bytes.unpack(p)[0]
end

FDI_HEADER_SIZE = 4096
RESERVED_CLUSTER_LEN = 2 # in FAT12/16, the first cluster is Cluster #2

class DiskImage # processes raw disk image (.img)
  attr_reader :sector_size
  attr_reader :cluster_size
  attr_reader :fat_size
  attr_reader :fat_bits
  attr_reader :dir_size
  attr_reader :dir
  attr_reader :file_size
  attr_reader :file_cluster_list
  attr_reader :file_offset_list

  def initialize(file)
    @file = file
    seek_set(11)
    @sector_size = read_int(2) # typically 512
    @cluster_size = read_int(1)*@sector_size # typically 1*512
    seek_cur(2)
    @fat_num = read_int(1) # typically 2
    @dir_len = read_int(2) # typically 224
    @dir_size = @dir_len*32
    rmd = @dir_size % @sector_size
    @dir_size += @sector_size-rmd if rmd > 0 # round up to integer multiple of sector size
    seek_cur(3)
    @fat_len = read_int(2)*@fat_num # typically 9*2
    @fat_size = @fat_len*@sector_size
    seek_cur(30) # offset=4096+54 now
    if @file.read(3).upcase == 'FAT'
      @fat_bits = @file.read(2).to_i
    else
      print('Warning: Unknown file system. It is likely that the floppy disk image is formatted with FAT12 or FAT16 (between which FAT12 is more likely). If you want to give it a try, please type either `12` or `16` to indicate that the file system will be interpreted as FAT12 or FAT16, respectively: ')
      @fat_bits = STDIN.gets.to_i
    end
    if @fat_bits == 12
      @eof = 0xFFF
    elsif @fat_bits == 16
      @eof = 0xFFFF
    else
      raise('Unsupported file system! Must be FAT12/16')
    end
    @dir_entries_offset = @sector_size+@fat_size
    @file_data_offset = @dir_entries_offset+@dir_size # offset of Cluster #2

    seek_set(@dir_entries_offset)
    @dir = {}
    for i in 0...@dir_len
      fName = @file.read(8).rstrip.upcase
      extName = @file.read(3).rstrip.upcase
      fName += '.'+extName unless extName.empty?
      seek_cur(15)
      @dir[fName] = [read_int(2), read_int(4)] # starting cluster, file size
    end
  end
  def seek_cur(offset) # seek from the current pos
    @file.seek(offset, 1)
  end
  def seek_set(offset) # seek from the beginning
    @file.seek(offset)
  end
  def read_int(*argv)
    getc(@file, *argv)
  end
  def autoexec_exe_name
    raise('The file `AUTOEXEC.BAT` cannot be found in this image!') unless (autoexec=@dir['AUTOEXEC.BAT'])
    fLen = autoexec[1]
    raise('The file `AUTOEXEC.BAT` is larger than a sector size, which does not seem right.') if fLen > @sector_size
    # now file pos is at the end of root dir entries
    seek_cur((autoexec[0]-RESERVED_CLUSTER_LEN)*@cluster_size)
    autoexec = @file.read(fLen)
    fName = autoexec = autoexec.split[0].upcase
    autoexec += '.EXE' unless @dir[autoexec]
    raise("The file `#{fName}` or `#{autoexec}` cannot be found in this image!") unless @dir[autoexec]
    return autoexec
  end
  def get_file_offsets(fName)
    fName = fName.upcase
    raise("The file `#{fName}` cannot be found in this image!") unless (fInfo=@dir[fName])
    file_first_cluster = fInfo[0]
    @file_size = fInfo[1]
    @file_cluster_list = []
    @file_offset_list = []
    @file_cluster_len = @file_size.fdiv(@cluster_size).ceil

    curClst = file_first_cluster
    lastPos = 0
    seek_set(@sector_size) # now file pos is at the beginning of FATs
    for i in 0...@file_cluster_len
      raise('Unexpected EOF at length 0x%08X of 0x%08X.' % [(i+1)*@cluster_size, @file_size]) if curClst == @eof
      #break if curClst == @eof
      @file_cluster_list << curClst
      @file_offset_list << @file_data_offset + (curClst-RESERVED_CLUSTER_LEN)*@cluster_size
      if @fat_bits == 12
        curPos, curRmd = (curClst*3).divmod(2) # FAT12: each FAT is 1.5 bytes (3 nybbles)
      else # FAT16
        curPos = curClst*2
      end
      seek_cur(curPos-lastPos)
      curClst = read_int(2) # 2 bytes=4 nybbles (with 1 nybble redundancy for FAT12)
      lastPos = curPos + 2
      if @fat_bits == 12
        if curRmd.zero? # even: AB CD (little endian) ==> DAB
          curClst &= 0xFFF
        else # odd: ... ==> CDA
          curClst >>= 4
        end
      end
    end
    raise('A pointer to Cluster 0x%04X found at a position where FAT should have been EOF.' % curClst) if curClst != @eof
  end

  # note: these functions below allows treatment of a `DiskImage` instance as if it were an IO stream,
  # taking inter-cluster seeking/reading/writing into account
  # however, for this to work, one must specify the initial offset first by `seek(<offset>, 0)`
  def seek(offset, whence=0) # in replacement of IO#seek
    if whence.zero?
      @cluster_ind, @rel_offset = offset.divmod(@cluster_size)
      raise('Unexpected EOF.') if eof?
      offset = @file_offset_list[@cluster_ind] + @rel_offset
      @file.seek(offset)
    else
      @rel_offset += offset
      cluster_ind_r, rel_offset_r = @rel_offset.divmod(@cluster_size)
      @cluster_ind += cluster_ind_r
      @rel_offset = rel_offset_r
      raise('Unexpected EOF.') if eof?
      if cluster_ind_r.zero? # no need to change cluster
        @file.seek(offset, 1)
      else
        offset = @file_offset_list[@cluster_ind] + @rel_offset
        @file.seek(offset)
      end
    end
  end
  def read(len) # in replacement of IO#seek
    result = ''
    while len > 0
      remaining_cluster_len = @cluster_size - @rel_offset
      if len > remaining_cluster_len # move on to the next cluster
        result += @file.read(remaining_cluster_len)
        @cluster_ind += 1; @rel_offset = 0
        raise('Unexpected EOF.') if eof?
        @file.seek(@file_offset_list[@cluster_ind])
      else
        result += @file.read(len)
        @rel_offset += len
        raise('Unexpected EOF.') if eof?
      end
      len -= remaining_cluster_len
    end
    return result
  end
  def write(content) # in replacement of IO#write
    len0 = len = content.length
    while len > 0
      remaining_cluster_len = @cluster_size - @rel_offset
      if len > remaining_cluster_len # move on to the next cluster
        @file.write(content.slice!(0, remaining_cluster_len))
        @cluster_ind += 1; @rel_offset = 0
        raise('Unexpected EOF.') if eof?
        @file.seek(@file_offset_list[@cluster_ind])
      else
        @file.write(content.slice!(0, len))
        raise('Unexpected EOF.') if eof?
        @rel_offset += len
      end
      len -= remaining_cluster_len
    end
    return len0
  end
  def eof?
    raise('Unexpected EOF: The file spans only %d clusters, but the %d-th cluster is requested.' % [@file_cluster_len, @cluster_ind+1]) if @cluster_ind >= @file_cluster_len
    offset = @cluster_ind*@cluster_size + @rel_offset
    return (offset > @file_size)
  end
end

class FDI < DiskImage # .FDI has a 4096-byte header, followed by raw image data
  def initialize(file)
    file.seek(8)
    raise('Not an FDI file!') if getc(file, 4) != FDI_HEADER_SIZE
    super
    @dir_entries_offset += FDI_HEADER_SIZE
    @file_data_offset += FDI_HEADER_SIZE
  end
  def seek_set(offset)
    offset += FDI_HEADER_SIZE
    super
  end
end
