#!/usr/bin/env python3
# encoding: utf-8
# usage SJIS2GBKchars.py [< ...] [2> ...]
# If you want to redirect STDIN and STDERR, it is recommended to `set PYTHONIOENCODING=utf8` in order to read/write using the UTF-8 encoding.
# [< ...] specifies the input file in replacement of STDIN. You should `set PYTHONIOENCODING=utf8` to read an UTF-8-encoded file; otherwise, the file should be encoded in ANSI (system locale). In addition, its first line should be 0 or 1, indicating the mode being SJIS2GBK or GBK2SJIS.
# [2> ...] redirects conversion output from STDERR to a specified file.

# Note: When converting GBK to SJIS, it's possible to have multiple choices, e.g. '读' => '読' or '讀'; in such cases, the output will show all possibilities within brackets, e.g. '[読讀]', and you may want to replace such ambiguous conversions with your explicit preferred form. In addition, it's also possible that there is no corresponding counterpart in SJIS for a given GBK char, such as '呢', in which cases a placeholder '𖸿' (U+16e3f) will be given.

import sys
with open('CHARS.txt', encoding='UTF-8') as f:
  exec(f.read(), globals())
enc = ('SJIS', 'GBK')
mode = int(input("SJIS2GBK (0) or GBK2SJIS(1): "))
print()
dictable = {}
for i in range(len(SJIS_CHARS)):
  if mode == 0:
    dictable[SJIS_CHARS[i]] = GBK_CHARS[i]
  elif mode == 1:
    c = GBK_CHARS[i]
    if c not in dictable: dictable[c] = SJIS_CHARS[i]
    else: dictable[c] += SJIS_CHARS[i] # multiple choices
  else: exit()
while True:
  try:
    chars = input("%s chars:\n" % enc[mode])
  except (EOFError, KeyboardInterrupt):
    print('Finished.')
    break
  print("%s chars:" % enc[1-mode])
  for i in range(len(chars)):
    char = chars[i]
    if len(char.encode('utf-8')) == 1 or 0xFF00 < ord(char) < 0xFF66 or 0x3000 <= ord(char) < 0x3003: # ascii, full-width numbers, alphabets, and punctuations
      print(char, end='', file=sys.stderr); continue
    try:
      new_char = dictable[char]
      print(("[%s]" % new_char) if len(new_char) > 1 else new_char, end='', file=sys.stderr) # take into consideration multiple choices
    except: # undefined
      print("\U00016e3f", end='', file=sys.stderr)
  print(file=sys.stderr)
  print()
