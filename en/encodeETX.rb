#!/usr/bin/env ruby
# encoding: binary

# monkey patching to ensure backward compatibility with Ruby < 1.9
unless String.instance_methods.include?(:ord)
  class String
    def getbyte(i); return self[i]; end
  end
end
TXTfName = $*[0]
unless TXTfName then puts("Usage: encodeETX <TXT filename>\n<path>.TXT\tThe TXT plain text file to be encoded. The encoded ETX file will be saved as <path>.ETX. Unlike `encodeGTX`, do not add a semicolon at each line end, and there is no restriction on the line break (EOL) sign you use. Again, `|` is used as a paragraph end sign."); exit end
ETXfName = "#{TXTfName.sub(/(.*)\..*$/, '\1')}.ETX"
o = open(ETXfName, 'wb')
open(TXTfName).each do |line|
  if line[0] == '|'
    o.write "\0"
    next
  end
  d = line.chomp
  l, r = d.length.divmod 2
  l += 1 unless r.zero?
  for i in 0...l
    case (b=d.getbyte(2*i))
    when 32 # space
      b += 3
    when 44, 46 # , and .
      b -= 8
    when 117..122 # u to z
      b -= 26
    end
    o.write(b.chr)
    o.write(d[2*i+1, 1])
  end
  o.write ' ' unless r.zero? # the length of a line must be an even number
  o.write "\1"
end
o.close
puts "Encoded into `#{ETXfName}`."
