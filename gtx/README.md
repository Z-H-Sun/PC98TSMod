# GTX encoder and decoder / 编/解码GTX文本

## Synopsis / 概要

## Usage / 用法

## Components / 组件
### [decodeGTX](/gtx/decodeGTX.rb)
Decoder of GTX, which converts GTX (or CTX) files into plain text TXT files. / 
解码器，将GTX（或CTX）文件转化为纯文本TXT文件。

### [encodeGTX](/gtx/encodeGTX.rb)
Encoder of GTX, which converts plain text TXT files into GTX (or CTX) files. / 
编码器，将纯文本TXT文件转化为GTX（或CTX）文件。

### NEC-C-6226-visual.txt
Unicode mapping for JIS encoding (Copyright (C) [HarJIT](https://harjit.moe)). In order for `encodeGTX` or `decodeGTX` to work, you need to either: / JIS编码与Unicode之间的映射表（版权所有 (C) [HarJIT](https://harjit.moe/)）。为使`encodeGTX`或`decodeGTX`正常工作，必须：
* Have `curl` and Internet access, so that the program will automatically download this file in the current folder. / 有`curl`且能联网，这样程序就会自动下载此文件到当前目录。
* Or, manually download [this file](https://harjit.moe/jistables/NEC-C-6226-visual.txt) in the current folder. / 或者，将[此文件](https://harjit.moe/jistables/NEC-C-6226-visual.txt)下载至当前目录。

### [PC98_CHAR_MAP.xlsm](/gtx/PC98_CHAR_MAP.xlsm)
This spreadsheet shows the relationship between the bytecodes in `MT.GTX` and their corresponding SHIFT_JIS bytecodes. You must enable "macro" and follow the instructions in this file in order for it to function properly. / 
该电子表格可显示`MT.GTX`文件中的字节码和对应日语文本在SHIFT_JIS编码中的字节码之间的关系。为实现此表格的正常功能，请启用“宏”并参照文件内的说明。

### [MT.CTX.TXT](/gtx/MT.CTX.TXT)
Chinese translation of dialogs of the game. Note that in order for `encodeGTX` to work properly, you must use `UTF-8` encoding and use `;\r\n` to indicate line break and `|\r\n` to indicate end of string (dialog) as does this file. / 
游戏中对话的汉化翻译。注意，为使`encodeGTX`能正常工作，必须像本文件那样使用`UTF-8`编码，使用`;\r\n`表示换行，以及`|\r\n`表示当前字符串（对话）的结束。

## How does the decoder work? / 解码器工作原理
### JIS encoding
The JIS encoding for Japanese characters is no longer commonly seen nowadays, likely because it is not compatible with ASCII, i.e., it cannot display half-width latin alphabet, numbers, punctuations, etc. For this reason, SHIFT_JIS has been developed and widely used later in replacement. You can refer to [Wikipedia](https://en.wikipedia.org/wiki/Shift_JIS) and [this webpage](https://harjit.moe/jischarsets.html) for more historical details.

The TowerOfTheSorcerer game was developed around the time period where this JIS to SHIFT_JIS transition happened. The strings were stored using the SHIFT_JIS encoding in the executable (`MTE.EXE`), but the hardware of the PC98 machine still uses JIS encoding under the hood. Therefore, the developer of the game, N.W., had to implement an encoding coverter himself to solve the character display issue; in addition, you can also find that all numbers and latin letters are shown as full-width characters in the game, likely in order to avoid the aforementioned incompatibility issue with ASCII.

According to [Wikipedia](https://en.wikipedia.org/wiki/Shift_JIS), if given a double-byte JIS sequence $j_1j_2\ (33\leq j_1,\ j_2\leq 126)$, the transformation to the corresponding Shift_JIS bytes $s_1s_2$ is:

$$s_{1}={\begin{cases} \left\lfloor {\frac {j_{1}+1}{2}} \right\rfloor +112&{\mbox{if }} j_{1}\leq 94\\
\left\lfloor {\frac {j_{1}+1}{2}} \right\rfloor +176&{\mbox{if }} j_{1} \geq 95 \end{cases}};\qquad s_{2}={\begin{cases} j_{2}+31+ \left\lfloor {\frac {j_{2}}{96}} \right\rfloor &{\mbox{if }}j_{1}{\mbox{ is odd }}\\
j_{2}+126&{\mbox{if }}j_{1}{\mbox{ is even }}\end{cases}}$$

Therefore, conversely the conversion from SHIFT_JIS $s_1s_2\ (129\leq s_1\leq 239,\ 64\leq s_1\leq 252)$ to JIS $j_1j_2$ can be derived as:

$$j_{1}={\begin{cases} 2(s_1-112)-1+ \left\lfloor {\frac {s_{2}}{158}} \right\rfloor &{\mbox{if }} s_{1} < 160\\
2(s_1-176)-1+ \left\lfloor {\frac {s_{2}}{158}} \right\rfloor&{\mbox{if }} s_{1} \geq 160 \end{cases}};\qquad j_{2}={\begin{cases} s_{2}-31- \left\lfloor {\frac {s_{2}}{128}} \right\rfloor &{\mbox{if }}s_{2}<158\\
s_{2}-126&{\mbox{if }}s_{2}\geq 158\end{cases}}$$

The equations above was implemented by N.W. in `sub_209d4` (offset `seg006:01f4`; see [README of patchTS](/patch#preparation) for more details on the naming convention of addresses; same below) in `MTE.EXE`.

However, it is worth noting that the conversion above is not 100% accurate, because the so-called "[old character variants（舊字體）](https://en.wikipedia.org/wiki/Ky%C5%ABjitai)" are involved. For example, JIS (specifically, the one used by PC98) encodes `366d` as "軀" (`U+8EC0`); however, according to the equations above, the corresponding SHIFT_JIS bytecodes should be `8beb`, but SHIFT_JIS encodes `8beb` as "躯" (`U+8EAF`), different from `U+8EC0`. Therefore, I used [the Unicode mapping table above](#nec-c-6226-visualtxt) to ensure accuracy during the conversion.

### GTX format
In addition to some routine strings stored in the executable `MTE.EXE`, most dialogs in the game are store in `MT.GTX`. The encoding there is neither SHIFT_JIS nor JIS; rather, N.W. used a home-made variant of JIS, where the high byte of two-byte kanji (or, Han; "漢字") characters are shifted by a constant offset, whereas all hiragana (平仮名), katakana (片仮名), and common punctuation characters are encoded as single-bytes, possibly in order to save space.

The relevant decoding function is `sub_20915` at offset `seg006:0135`. The rules can be summarized as follows:
* `\x00`: end of string. `\x01`: new line.
* `\x10` to `\x64`: hiraganas, the corresponding JIS code is `0x2410+i`, where `i` is the encoded byte code (same below). For example, `\x11` is JIS `2421`, "ぁ", and `\x63` is JIS `2473`, "ん".
* `\x65` to `\xbf`: katakanas, the corresponding JIS code is `0x24bb+i`. For example, `\x66` is JIS `2521`, "ァ", and `\xbb` is JIS `2576`, "ヶ".
* `\xc0` to `\xcf`: punctuations, the corresponding JIS code is `0x2060+i`. For example, `\xca` is JIS `212a`, "！".
* Otherwise: if the encoded 2 bytes are `i` and `j`, then the corresponding JIS code will be `CONCAT(i-0xb0, j)`, i.e., the high byte is shifted by `0xb0`, and the low byte retains. For example, "丁香園主人" (JIS codes are `437a 3961 3160 3c67 3f4d`) are encoded as `\xf3\x7a\xe9\x61\xe1\x60\xec\x67\xef\x4d`.

### Support for more kanji chars
The encoding method above means that only the 2-byte characters with JIS codes between `0xd000-0xb000` to `0xffff-0xb000`, i.e. (`0x2000` to `0x4fff`), can be correctly encoded and displayed in the game. This range covers most of the regular-use kanji ("常用漢字") characters, which is enough for the Japanese version of the game; however, the Chinese translation requires way larger amount of Han (kanji) characters than this range. To name a few, "它", "們", "扣", "鑰", and "鎬", etc., all have JIS codes larger than `0x4fff`.

To solve this issue, the simpliest fix is to change the shift constant `0xb0` to a larger value, say, `0xf0`. (In doing so, one can no longer use `\x10` to `\x64` to represent hiraganas; nevertheless, there is by no means any need for displaying hiraganas in a Chinese translated version.) That is how I implemented this workaround in `decodeGTX` and `encodeGTX` when the argument `-p` is set. Or you can set an arbitrary new shift constant by specifying `-o <offset>`. In addition, we will also need to patch `sub_20915` in the following aspects:
* Change the shift constant from `0xb0` to `0xf0` at `seg006:01c0` (`sub al, [x]`: set `[x]` = `0xf0` instead of `0xb0`).
* Tell the program not to decode `\x10`–`\x64` into hiraganas (but rather treat them as the high byte of a Kanji char) at `seg006:0196` (`cmp al, [x]`: set `[x]` = `0x64` instead of `0x10`).

### Traditional or simplified Chinese
Japanese kanji, traditional Chinese, and simplified Chinese chars have large overlap, but there are also a lot of differences. Since SHIFT_JIS kanji chars cover most of common traditional Chinese chars whereas a lot of simplified Chinese chars are not present in SHIFT_JIS kanji chars, I decided to use traditional Chinese chars by default in the Chinese translated version. There are several cases, summarized below:
* The Japanese kanji char is the same as the traditional Chinese variant but different from the simplified Chinese variant, then use the traditional Chinese variant. For example, among 個/個/个, "個" will be used. Although there is "个" in the SHIFT_JIS character table, it is not the commonly used kanji in Japanese.
* The Japanese kanji char is the same as the simplified Chinese variant but different from the traditional Chinese variant, then still use the traditional Chinese variant. For example, among 会/會/会, "會" will be used. Although there is "會" in the SHIFT_JIS character table, it is not the commonly used kanji in Japanese.
* The Japanese kanji char is the same as the simplified Chinese variant, and the traditional Chinese variant is not in the SHIFT_JIS character table, then we have to use the simplified Chinese variant. For example, 档/檔/档, "档" will be used as "檔" is absent in the SHIFT_JIS encoding.
* The Japanese kanji char is not the same as the traditional nor the simplified Chinese variant,
  * but the traditional Chinese variant is in the SHIFT_JIS character table, then use the traditional Chinese variant. For example, among 価/價/价, "價" will be used.
  * and no Chinese variant is in the SHIFT_JIS character table, then we have to use the Japanese kanji variant. For example, among 歩/步/步, "歩" will be used.
* Neither traditional nor simplified Chinese variant is present in the SHIFT_JIS character table, then use a kanji char that looks similar. For example, use "祢" to represent "妳/你", and use "阿" to represent "啊".

Overall, the fallback chain is Traditional Chinese -> Simplified Chinese -> Japanese kanji.

Note that it is intrinsically impossible to display a character that is not present in the SHIFT_JIS character table, but there is a workaround, i.e., to load a specially modified "font," which is essentially a bitmap image of characters, in the PC98 emulator. By doing so, the player can literally have a "simplified Chinese translated version" of the game. For more discussions, refer to [README of fontGenerator](/font).
