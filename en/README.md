# TowerOfTheSorcerer English Ver / 魔塔英译版

## Synopsis / 概要

## Usage / 用法

## Components / 组件

## Patched places / 补丁
### Workaround to show latin alphabet
In the Japanese version of the game, drawing texts involves low-level hardware interactions, so there are many restrictions. For example, JIS encoding is used, which is ASCII-incompatible (see [here](/gtx#jis-encoding) for more details), so
* The SHIFT-JIS-encoded (ASCII-compatible) strings stored in the executable, `MTE.EXE`, must be converted into JIS first (`sub_209d4`; see [here](/gtx#jis-encoding) for more details about the conversion)
* All 1-byte ASCII chars must be converted or processed. For example,
  * Space (half-width) = Move the current drawing position by 8 pixels to the right (each full-width char is 16-pixel wide). New line (`\n`) = Move the current drawing position downwards by 20 pixels (the height of one line) and move to the beginning of the new line. Ignore tabs (`\t`). The corresponding function is `sub_20883` (offset `seg006:00a3`; see [README of patchTS](/patch#preparation) for more details on the naming convention of addresses; same below)
  * Half-width numbers (0–9) and alphabets (A–Z) will be converted into their full-width counterparts (０–９ and Ａ–Ｚ). The corresponding function is `sub_1b7d4` and `sub_1b8d6`.
  * We will elaborate on these cases below.

Therefore, in the original game, only 2-byte wide chars can be displayed, and this is processed in `sub_20a12` (or `sub_20aba` if you are in the EPSON286 mode; see [here](/patch#set-font-style) for more details). Briefly, the following will happen:
* `sub ax, 2000h; push ax`: The high byte of the 2-byte char will be shifted by `0x20`. This is because in the JIS encoding, the high byte starts from `0x20` (which is half-width space in ASCII), before which are assigned control codes.
* `mov al, 0Bh; out 68h, al; pop ax`: Writes `0x0b` (`\v`) (or `0x0a` (`\n`) in the EPSON286 mode) to I/O port `0x68` (likely keyboard-related?), which likely starts a new line of string.
* `out 0A1h, al; xchg ah, al; out 0A3h, al`: Writes both high (shifted by `0x20`) and low bytes to I/O ports `0xa3` and `0xa1`, respectively. This is a low-level hardware interaction.
* After this step, the hardware will directly output a 16\*16 monochromic image of the corresponding char to the memory at address `0xa400`.
* `mov ax, 0A400h; move ds, ax; mov si, 0; move ax, 0A800h; call sub_20a5a; ...`: Then, this monochromic image data will be copied to B, R, G, and E color planes at memory addresses `0xa800`, `0xb000`, `0xb800`, and `0xe000`, which shows the char on the screen (see [here](/p58#graphics-system) for more details on the PC98 graphics system);
* `move ax, 0A800h; call sub_20a5a; ...`: The same image will be copied again but shifted by 1 pixel to the right to show the "stroke" effect (see [here](/patch#set-font-style) for more details).

Apparently, half-width latin alphabets and numbers are 1-byte, not 2-byte wide chars that can be displayed in the above way. And unfortunately, I don't know enough about the hardware of PC98 to intervene here. One workaround is to turn all half-width chars into their 2-byte, full-width counterparts, but
1. it is not aesthetically appealing (like this: "Ｔｈｉｓ　ｉｓ　ｔｏｏ　ｕｇｌｙ！"), and
2. most importantly, there will not be enough space for either display or storage.

Then, how about encoding every 2 half-width chars into one wide char? For example, we will encode "ZS" (`\x5a` for "Z" and `\x53` for "S") into `\x5a\x53`. But then, we need to tell the PC98 emulator not to show it as "旃" (which is `\x5a\x53` in JIS encoding) but rather "ZS". This can be done by loading a specially made "font" (e.g., maps `\x5a\x53` into "ZS") in the emulator. You can compare [this font](/en/font_en_r.bmp) with [the original one](/font/font_ja.bmp) to get an idea on how this works. For more details, refer to [README of fontGenerator](/font) or read the last paragraph in the [this section on showing simplified Chinese chars](/gtx#traditional-or-simplified-chinese).

#### Re-encoding for unsupported range
However, there is still a small problem. In the JIS encoding, there is no chars mapped when the high byte is between `0x28` and `0x2f` or larger than `0x75`, so the hardware cannot correctly treat these "bad" chars. This means: If we have a "pair of 2 ASCII chars" that starts with a comma, a period, or a letter between "u" to "z", these two chars will not display. For example, in the sentence, "This, though trivial, is a serious problem. " (note the space at the end is necessary to make the length of the string an even number, since we encode every 2 ASCII chars into a wide char), the following pairs will be missing: ", " "vi" ", " "us" and ". ". My workaround, though not very elegant, is to re-encode "," "." and "u" to "z" into "$" "&" "\[" to "\`", respectively. So the sentence above will become: "This\$ though tri\\ial\$ is a serio\[us problem& ".

#### Implementation
Now that we take the aforementioned measures and show only ASCII chars, there is no longer any need to convert SHIFT-JIS into JIS or re-encode Japanese texts in `MT.GTX` (this orginally serves to save storage space for katakana and hiragana chars; see [this section](/gtx#gtx-format)). For the former case, the pseudocode for `sub_20883` is shown below, and we will need to skip the `sub_209d4` call if the high byte `char_h` is less than 0x80 (all ASCII codes are smaller than 128). For the latter case, we will nullify the `cmp al, 10h` comparision at `seg006:0196` and remove the `sub al, 0B0h` shift at `seg006:01C0` (similar to [this patch for the Chinese Ver](/gtx#support-for-more-kanji-chars)).

```python
POSITION = word_20881 # = (640*y+x)/8
TOP      = word_20876
LEFT     = word_20874
HEIGHT   = word_2087b # = 20; line height
EPSON286 = byte_20880
STRING   = ctypes.cast(word_20872, POINTER(c_char))

POSITION = TOP*80 + LEFT # 80 = 640/8
index = 0
while True:
  char_h = STRING[index]; index += 1 # high byte
  char_l = STRING[index]; index += 1 # low byte
  if char_h == "\0":
    break
  elif char_h == "\t":
    index -= 1; continue # pass this char
  elif char_h == " ":
    POSITION += 1        # +8 pixels
    index -= 1; continue
  elif char_h == "\n":
    TOP += HEIGHT
    LEFT = TOP*80 + LEFT # new line
    index -= 1; continue
  else:                  # <--- skip this if ord(char_h) < 0x80
    sub_209d4()          # SHIFT-JIS to JIS

  # <--- jump to here if ord(char_h) < 0x80
  sub_20aa6() if EPSON286 else sub_209f8() # draw string
  POSITION += 2          # +16 pixels
  ...
```

### Stroke effect vs bold font
The game uses "stroke effect" for text display, which is OK for Japanese or Chinese texts but can sometimes be ugly for ASCII chars. So, now that the goal is to increase the font weight, why not just use the bold font instead? You can compare the case using [this regular font](/en/font_en_r.bmp) with stroke and [this bold font](/en/font_en_b.bmp) without stroke, and you will find the latter much better. The patch to turn on or off this stroke effect is documented [elsewhere](/patch#set-font-style).

### Half-width vs full-width numbers
To make text display consistent for the English Ver, we do not want to show full-width numbers in the status bars, etc, but rather half-width numbers. The implementation in the assembly codes `sub_1b7d4` and `sub_1b8d6` for the conversion from half-width to full-width numbers is very circuitous, which I will not discuss in details (but you are more than welcome to explore it by yourself!), but the logic is easy to understand, shown as pseudocodes below:

```python
FW_NUM = ["０","１","２","３","４","５","６","７","８","９"]

def sub_1b7d4(number):      # draw left-aligned numbers
  numstr = ctypes.c_char_p(str(number).encode()) # _itoa @ seg002:1cdc
  index = 0; index_u = 0; numstr_u = ctypes.create_string_buffer()
  if numstr[0] != "\0":     # is a number
    while numstr[index] != "\0":
      numchar_u = FW_NUM[ord(numstr[index])-0x30]
      numstr_u[index_u]   = ord(numchar_u[0])
      numstr_u[index_u+1] = ord(numchar_u[1])
      # this is realized by sub_1f4ec (seg003:003c)
      # dseg:[0x522a+arg0*2] => word_2756a[ord(numstr[index])]
      # note that the word array is stored in little-endian order
      # so the high byte and low byte are swapped afterwards
      # e.g. for "０" (\x82\x4f in SJIS), dseg:[0x522a+0x30*2]:=0x4f82
      index_u += 2
      index   += 1
  numstr_u[index*2] = 0     # write "\0" at the end of the string
  return numstr_u

def sub_1b8d6(number,left,length,color): # draw right-aligned numbers
  ... # same as above
  numstr_u[index*2] = 0
  numlen=numstr.index("\0") # this is unnecessary as numlen=index
  left += 2*(length-numlen) # right alignment
  sub_20801(left, color, numstr_u)
```

The patch removes the function calls to `sub_1f4ec`, adds a half-width space at the end (explained below), and recalculates the lengths and left positions, etc.:

```python
def sub_1b7d4(number):
  ... # same as before
    while numstr[index] != "\0":
      numchar_u[index] = numstr[index]
      index_u += 1
      index   += 1
  numstr_u[index] = 20; numstr_u[index+1] = 0 # space, then "\0"
  return numstr_u

def sub_1b8d6(number,left,length,color):
  numstr = ctypes.c_char_p(str(number))
  numlen = numstr.index("\0")
  numstr[numlen] = 20; numstr[numlen+1] = 0 # space, then "\0"
  left += 2*length - numlen
  sub_20801(left, color, numstr_u)
```

If the length of the string is an odd number, then it is necessary to add a "dummy space" at the end, since we encode every 2 ASCII chars into a wide char; if an even number, adding the dummy space is not harmful, because it will be processed and won't be recognized as "part of a 2-byte char" anyway, as shown in the pseudocode for `sub_20883` [here](#implementation).

The logics for the patches above are straightforward, but implementing them using the assembly codes is challenging. I will not elaborate here, but there is one noteworthy thing: When there is a far-`call` (by absolute address), it seems that the oprands (and by extention, the bytes in the executable) will be modified when loading into the memory of the emulator, making it impossible to make predictable changes at these locations. Therefore, I used `jmp` instructions to bypass those locations.

### Other minor patches
The monster names, item names, and some common prompts are fixed-length strings ended with `\0`, stored in the `dseg` segment of the executable, `MTE.EXE`. Sometimes, the English translated version of the string is shorter than the Japanese version, which is good, because the remaining length can be simply filled with `\0`s. But things can get tricky when the opposite happens–What if the altered string is longer than the original, which will then impact all the addresses afterwards? Then we have to find out all relevant pointers in the assembly code and modify them.

In the case of monster names (stored in the area starting from `dseg:00A6`), the fix is relatively simple, because all their pointers are stored together in the area starting from `dseg:0646`. So just modify them accordingly. (By the way, other monster properties–tile ID, HP, ATK, DEF, and GOLD–are also stored here.)

<details><summary>Tile IDs</summary>
<p align="center"><img src="https://i0.hdslb.com/bfs/article/watermark/2563e02bb0af70455ea16ef152c256bea61b5207.png"></p>
</details>

However, the modification of other string pointers is less straightforward. For example, when you use the Elixir, the prompt is "生命力　`\0`" (`dseg:15df`, len=4\*2+1=9, note the full-width space at the end), followed by a number and then "ポイント回復した！`\0`" (`dseg:15e8`, len=9\*2+1=19). The relevant assembly code at `seg001:182f` reads: `mov si, 15DFh; ...; movsw; movsw; movsw; movsw; movsb` (`movsw` loads 2 bytes at a time, whereas `movsb` loads 1 byte), which loads the first 9 chars, and then `mov di, 15E8h; ...; repne scasb; ...; rep movsw`, which loads the second string until `\0` is encountered. The English translated strings are " HP's got  raised by `\0`" (`dseg:15df`, len=21+1=22; the spaces are used to align the words vertically), and "pt!  `\0`" (now at `dseg:15f5`), and thus the relevant assembly codes should be modified to `mov di, 15E8h; ...; mov cx, 0Bh; rep movsw` (`rep movsw` loads `cx*2` bytes) and `mov di, 15F5h; ...`.

In the Japanese version, the monster names are "manually" centered using spaces. For example, "ゾンビナイト" is 12-half-width-char wide, but "バット" is only 6-half-width-char wide. To center the latter, you need to add (12-6)/2 = 3 half-width spaces at the beginning (or equivalently, 1 full-width space plus 1 half-width space). However, in the English translated version, there is no enough space to store the space-padded names. That is, those names will be effectively left-aligned. This will make the monster bar display less aesthetically appealing, especially when the monster name is short (right picture below). Therefore, I switched the positions of the monster picture and the monster name (left picture below). The relevant function is `sub_19626`. At `seg001:2e17`, `mov ax, 48C6h` specifies the coordinates at which to draw the monster picture ($x=560,\ y=232$; recall that [the PC98 graphics hardware system](/p58#graphics-system) groups every 8 pixels in a row, so `0x48c6=(560+232*640)/8`), and at `seg001:2e40`, `mov cx, 272` specifes the *y* coordinate at which to draw the monster name. In the patched version, the monster picture is lowered by 28 pixels (`mov ax, 5186h`), and the monster name is raised by 32 pixels (`mov cx, 240`).

![](https://user-images.githubusercontent.com/48094808/233548559-386b8148-4f8c-4849-a0b2-cf90f3a55987.png)

In addition, since the text lengths in the OrbOfHero (勇者のオーブ) window also change in the English version, it is best if the text "Expct Damage" (right picture below) could be moved by 2 chars to the right (left picture below). The relevant function is `sub_18C2A`, and the desired change can be done by changing `mov [bp-0x22], 28h` (at `seg001:2649`) to `mov [bp-0x22], 2Ah`. This, however, will also move the number on the right. To counteract this effect, `add [bp-0x22], 0Ch` (at `seg001:2688`) should also be changed to `add [bp-0x22], 0Ah`.

![](https://user-images.githubusercontent.com/48094808/233561420-6b63a917-263b-4431-add4-53d1704e3433.png)

Lastly, when refreshing the dialog window (such as when using the OrbOfWisdom, 知恵のオーブ), the chars in the rightmost (37th) column will not be erased and retain persistently (framed in yellow in the picture below). This was not a problem in the Japanese version, as only wide chars could be displayed there, so there wouldn't be an odd-numbered column. The relevant functions are `sub_1958c` and `sub_195d8`. Basically, for each line, the rect framed in pink below will be filled with color `0xD` (dark gray), so the last column will not be refreshed: `mov al, 0DDh; push ax; ...; mov ax, 12h; push ax; ...; add ax, 3D6h`. By changing `12h` and `3D6h` above to `13h` and `3D5h`, respectively, the rect framed in black will be filled instead, including the last column.

![](https://user-images.githubusercontent.com/48094808/233571797-90715bbd-c944-4858-9cc6-b5a8fb0b12f6.png)