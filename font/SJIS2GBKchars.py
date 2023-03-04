#!/usr/bin/env python3
# encoding: utf-8
# usage SJIS2GBKchars.py [< ...] [2> ...]
# If you want to redirect STDIN and STDERR, it is recommended to `set PYTHONIOENCODING=utf8` in order to read/write using the UTF-8 encoding.
# [< ...] if the input file is specified in replacement of STDIN, before you have set `PYTHONIOENCODING`, the file must be encoded as ANSI (system locale). The first line should be 0 or 1, indicating the mode to be SJIS2GBK or GBK2SJIS.
# [2> ...] redirects conversion output from STDERR to a specified file.
import sys
with open('CHARS.txt', encoding='GBK') as f:
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
      print(new_char, end='', file=sys.stderr)
    except: # undefined
      print("\U00016e3f", end='', file=sys.stderr)
  print(file=sys.stderr)
  print()
