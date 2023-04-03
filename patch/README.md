# TowerOfTheSocerer Patch / 魔塔主程序补丁

## Synopsis / 概要

## Usage / 用法

## Components / 组件
### [patchTS](/patch/patchTS.rb) (main)
This is the main program. It will patch the executable of the TowerOfTheSocerer game. The places to patch are specified in [`patchTS.txt`](/patch/patchTS.txt). / 
这个是主程序，用于给魔塔游戏的可执行文件打补丁。要打哪些补丁由[`patchTS.txt`](/patch/patchTS.txt)指定。

### [patchTS.txt](/patch/patchTS.txt)
Specifies what to patch. It stores a 2D array, where each element is a 1D variable-length array and specifies one place to patch. These 1D arrays must have at least 7 elements each: / 
指定要打哪些补丁。该文件里有一个二维数组，其中每个元素都是一个不定长的一维数组且各自指定一处要打的补丁。这些一维数组中都必须至少有7个元素
* First: Boolean; whether this patch is recommended (i.e., will be performed by default). / 第一个: 布尔值类型，是否为推荐（即默认选中）的补丁。
* Second: String; description of the patch, which will be displayed in the main program. / 第二个：字符串类型，对应补丁的描述，将显示在主程序中。
* Third: String; warning message to display when patching. If not applicable, set it as `nil`. / 第三个：字符串类型，在打该项补丁时显示的警告信息；如果没有则设为`nil`。
* Fourth: String; warning message to display when restoring. If not applicable, set it as `nil`. / 第四个：字符串类型，当取消该处补丁时显示的警告信息；如果没有则设为`nil`。
* Fifth: Integer; the absolute offset of the place to patch. / 第五个：整数类型，补丁的绝对偏移量。
* Sixth & Seventh: String; the original bytes & the bytes after patch. / 第六、七个：字符串类型，原先的和打完补丁后的字节码。
* Optional: (3*n*+8)-th, (3*n*+9)-th, & (3*n*+10)-th (*n*=1,2,3,...): If multiple places needs patching, specify here the relative offset (with respect to the end of the previous bytes) and original/patched bytes. / 第(3*n*+8)、(3*n*+9)、(3*n*+10)个 (*n*=1,2,3,...)：如果有多处需要更改，在此处指定相对（于上一组字节码末尾而言的）偏移量以及原先的/打完补丁后的字节码。

### [readFDI](/patch/readFDI.rb)
Read and write virtual files within an FDI image as if they were on a physical drive. / 给FDI镜像中的虚拟文件提供读写接口。
* This is an experimental function, so it only supports a limited selection of image formats, and I can't guarantee it works perfectly well. So be careful and backup your file. / 这个功能尚处实验阶段，因此只支持部分镜像格式，且并不保证会毫无差错。所以请务必做好备份。
* FDI is a format developed by ANEX86. The first 4096 bytes are headers that specify the properties of the image, followed by the raw floppy disk IMG data, which can be directly loaded by disk image tools like `dd`. / FDI是由ANEX86开发的格式，其中前4096字节为文件头，指定了该映像的一些属性，紧随其后存储的是软盘的原始数据，如果将此数据另存为IMG格式可直接由诸如`dd`等的磁盘映像工具装载。
* The floppy disks usually uses FAT12 or FAT16 filesystems. There are plenty of references on them, so I won't elaborate the details here. If you are interested about how they work, refer to the links shown at the beginning of [`readFDI.rb`](/patch/readFDI.rb). / 软盘常用FAT12或FAT16文件系统来存储数据。关于这些文件系统的格式，网上已有较多的参考资料，故此处不再赘述，详情可参考[`readFDI.rb`](/patch/readFDI.rb)中开头所述的链接。

## How do the patches work? / 补丁工作原理
### Preparation
You can use IDA to statically disassemble `MTE.EXE` or use (a DEBUG-oriented fork of) Neko Project II to dynamically disassemble the TowerOfTheSorcerer game program.
* Note that the recent Free version of IDA has dropped support for 16-bit executables, so you will need either [a Pro version](https://www.hex-rays.com/ida-pro/) or [an earlier Free version](https://www.scummvm.org/news/20180331/).
* Note that the normal NP2 release doesn't have the debug utilities. You must use [this DEBUG edition](https://github.com/nmlgc/np2debug/releases), and then you can access the debug-related functions in the `Tools -> Debug utility` menu.
* Note that the instruction addresses when loaded into RAM (shown in NP2, which may vary from run to run) will be very different from the static offsets shown in IDA. Below, unless otherwise noted, the "addresses" stand for the offsets shown in IDA.

### Set the default speed mode
* The byte `seg008:001f` (offset `222af`) controls the speed mode: 0 for normal mode and 1 for high speed mode. We need to set the high speed mode as default (i.e., `byte_222af = 1`) upon starting the game.
* However, directly changing this value statically in the executable will not work at all. This is because everytime the game restarts, this variable will be reset as 0 in `sub_16536`:
  ```asm
  sub ax, ax ; ah=al=0
  mov es, seg_2788a ; seg008
  mov cx, 100
  push es
  mov di, 1Eh
  rep stosb ; set es:[di]=al; di+=1; loop for cx times
  ```
  The code above will reset `seg008:001e` to `seg008:0082` (offset `222ae` to `22312`) zeros.
* Therefore, we will instead target the `_main` (offset `16692`) function. This function will check if the argv passed to the program contains any of the following: *EP286* (`dseg:10bf`), *FMINT0* (`dseg:10f8`), *FMCUT* (`dseg:10ff`), *FORTEST* (`dseg:1105`), *=NAO/WATANABE=* (`dseg:110d`), *MTREG* (`dseg:111c`), and *REGCUT* (`dseg:1122`). The last two were unused for some unknown reason; as a result, we can add the instructions here in replacement to set the byte `seg008:001f` to be 1.

```asm
seg000:679F      mov     ax, 1122h
seg000:67A2      push    ds
seg000:67A3      push    ax              ; char *
seg000:67A4      mov     es, [bp+var_8]
seg000:67A7      push    word ptr es:[si+2]
seg000:67AB      push    word ptr es:[si] ; char *
seg000:67AE      call    _stricmp
```

The assembly code above compares the current argument with `dseg:1122` (i.e., `REGCUT`). Now that we know this comparison is useless, we will replace it with the following:

```asm
mov es, seg_278B8 ; seg008
mov byte ptr es:[0x1f], 1 ; byte_222af
jmp short [+0x0b] ; loc_167b6
nop
...
```

So now, as long as you pass an argument that is not one among `EP286`, `FMINT0`, `FMCUT`, `FORTEST`, `=NAO/WATANABE=`, and `MTREG`, the speed mode will be the high speed mode at the beginning of the game. For example, if you specify `FORTEST`, it will set `byte_222af` zero and thus normal speed mode as default just like in `sub_16536`; but then, you can add another argument afterwards, say, `MTE [...] FORTEST foo` to re-set the high speed mode as default.

### Fix the Warp Wing (Warp Staff) bug
* When you use the Warp Wing (Warp Staff) at an HP < 800, the HP will become a negative number, which should have caused "game over." However, the TowerOfTheSorcerer game improperly treats this negative number as an unsigned integer, which leads to an underflow and thus HP becoming the upper limit (9990 or 32767 depending on whether you have patched the HP upper limit). In addition, if you use the item at an HP of exactly 800, your HP will become zero, which should also have caused game over. But in the original TowerOfTheSorcerer game, this does not happen either.
* Long story short, we need to add a judgement on HP (`word_22328`; offset `seg008:0098`) right after using the item (`loc_186b6`; offset `seg001:1e06`): If the HP is less than or equal to 0 after the 800 HP deduction, then trigger "game over."
* This judgement and other involved processes, shown below, requires 21 additional bytes, which is quite challenging because we have to save these 21 bytes from other neighboring places without affecting the normal function of the game.
  ```asm
  ...
  mov ax, es:[0x98]; HP
  sub ax, 800
  ja short [+0x03] ; if >0 goto `mov es:[0x98], ax`
  mov ax, 0        ; avoid underflow
  mov es:[0x98], ax
  ... ; some other instructions, which change the value of ax
  ... ; (e.g., update HP and the player position on the map)
  cmp es:[0x98], 0
  ja short [+0x04] ; if >0 goto `...`
  push cs
  call near ptr sub_197ac ; trigger game over
  ...
  ```
  The code above is 28 bytes long, in replacement of the original `sub es:[0x98], 800` (7-byte).
* There are three ways to save the space:
  * Delete one `nop` opcode (1-byte)
  * When calculating 11\*`ax`, the original instructions (offset `seg001:1e4d`) were `mov cx, ax; shl ax, 1; shl ax, 1; add ax, cx; shl ax, 1; add ax, cx` (12-byte), i.e. `ax = (((ax << 1 << 1) + ax) << 1) + ax`. Technically, this is slightly faster than `mov cx, ax; mov ax, 11; mul cl` (7-byte), i.e. `ax *= 11`, but by using the latter instructions, we save 5-byte space.
  * The `es` segment gets constantly re-assigned. However, in some cases, the `es` stays unchanged, so there is no need for such reassignment. For example, at offset `seg001:1e87`, the original instructions read `mov es, seg_278b0; mov es:[0x04], dx; mov es, seg_278ba; sub es:[0x98], 800`; however, both `seg_278b0` and `seg_278ba` point to `seg008`, so there is no need to have the second assignment `mov es, seg_278ba` here. Each occurrence of such redundant assignment takes 4 bytes. So, we cut off 4 such reassignments and can thus save 16-byte space.
  * At the end of the day, we can save 1+5+4\*4 = 22 > 21 bytes.

The entire assembly instructions before and after patching are too lengthy to show. Below is the pseudocode for the instructions after patch:
```python
...
X_POS = word_22292 # seg008:0002
Y_POS = word_22294 # seg008:0004
HP    = word_22328 # seg008:0098
FLOOR = word_2232e # seg008:009e
MAP   = word_23e28 # dseg:1ae8

x_pos = 10-X_POS
y_pos = 10-Y_POS # centrosymmetric pos
sub_19d80(0x1633) # draw text in the bottom right corner
# dseg:1633 = Space warped!
if MAP[124*FLOOR + 11*y_pos + x_pos] == 6: # is floor?
  X_POS = x_pos
  Y_POS = y_pos
  HP   -= 800
  if HP <= 0: HP = 0
  sub_1b96c(1) # refresh HP display
  sub_1b62a()  # clear old player pos
  sub_1a1e4()  # show new player pos
  if HP <= 0: sub_197ac() # game over
else: # obstacles
  sub_19d80(0x1642) # dseg:1642=Warp failed due to obstacles

sub_12f8c()
return
```
It is worth noting that the map info is stored in the WORD array at offset `dseg:1ae8` (i.e., each element is a 2-byte long integer). Each floor has 124 elements, and the first three are: floor number (0 to 51), the position after climbing up the stair, and the position after walking down the stair. The position (0 to 120) is defined as 11\*`Y_POS`+`X_POS`, where the `Y_POS` and `X_POS` range from 0 to 10 and are numbered from the upper left corner to the bottom right corner. The following 121 elements are the IDs of the tile at the given position. The definition of tile IDs is shown below (click the triangle icon to expand); e.g., 6 = normal floor.
<details><summary>Tile IDs</summary>
<p align="center"><img src="https://i0.hdslb.com/bfs/article/watermark/2563e02bb0af70455ea16ef152c256bea61b5207.png"></p>
</details>

### Remove HP/ATK/DEF/GOLD upper limit
* The game stores HP, ATK, DEF, and GOLD as WORDs (2-byte integers) at offset `seg008:0098` (`word_22328`), `seg008:009c` (`word_2232c`), `seg008:0016` (`word_222a6`), and `seg008:00a2` (`word_22332`), and the game displays these properties in the upper left corner of the map. Given that this game is a 16-bit program, it is understandable that 16-bit (2-byte) integers were chosen at the time for the sake of efficiency; this choice, however, intrinsically limits the range of these variables.
* HP and GOLD are regarded as signed integers because they can go negative during a battle or a purchase. Therefore, their intrinsic upper limits are $2^{15}-1 = 32767$. ATK and DEF can theoretically be unsigned, so they can go up to $2^{16}-1=65535$, though it is high unlikely that one can achieve such high properties in this game.
* When these properties need refreshing (e.g., during a battle or a purchase; or after getting a potion or a crystal), `sub_1b96c(int property)` (offset `seg001:50bc`) is called, where the argument `property` specifies which property will be refreshed: 1=HP, 2=ATK, 3=DEF, 4=GOLD, 5=Floor, and 0=all.
* Whatever value of `property` is passed, all four values are checked beforehand: If HP, ATK, DEF, or GOLD exceeds the corresponding upper limit (originally 9990, 990, 990, and 9990, respectively), then set its value as the upper limit. The upper limit can be relieved to 32767, but as outlined in the second bullet, it can't be any larger so as to avoid overflow.

The pseudocode for such overflow checks is quite straightforward:
```python
if HP  > 9990: HP  = 9990
if ATK >  990: ATK =  990
if DEF >  990: DEF =  990
if GOLD> 9990: GOLD= 9990
```

And our patch simply replaces 990s and 9990s with 32767.

Additional note: There are other places where similar "9990-tests" are done. For example, the expected damage shown in OrbOfHero (勇者のオーブ; 勇者灵球) and the amount of gold asked for by an altar (祭壇) are also always ≤ 9990. The corresponding addresses of the tests are `seg001:26b0` in `sub_18c2a` and `seg000:42e6` in `sub_142aa`, respectively. The former is patched here, but the latter is not, because the amount of gold asked for by an altar follows: $G=10t^2-10t+20$, where *t* is the number of visits to the altar, so not until the 33rd visit will *G* exceed 9990, while it is highly unlikely that one can collect enough gold to visit the altar for more than 21 times in this game.

### Increase HP/ATK/DEF/GOLD display digits
* Although we relieved the upper limits in the last section, a new problem arises. If the value is between 10000 and 32767, there is an additional digit—and this fifth digit will not display correctly.
  * First off, it exceeds the left bound of the frame, so we need to adjust its display position.
  * Secondly, the left-most digit never gets refreshed. For example, if your HP goes from 19900 to 20000, there will be a "2" superimposed on top of "1" on the far left; what's worse, if your HP decreases from 10000 to 9800, the leftmost "1" never gets erased, so it now reads "19800," which can be very misleading.
* The relevant function to patch is still `sub_1b96c`. Just below the overflow checks in the previous section, two functions are called for each property to be refreshed:
  * `sub_1fcd9(int pos, int length, int height, byte color)`
  * `sub_1b8d6(int left, int top, int value, int length, byte color)`
* To take HP as an example, the peudocode for the original instructions is: `sub_1fcd9(6406, 4, 16, 0xdd); sub_1b8d6(6, 80, HP, 4, 0xff)`
* The first function fills the rect (*l*=48, *t*=80, *w*=64, *h*=16) with color `0xD`, and the second function draws the HP value in the same rect, right aligned, with color `0xF`. Colors `0xD` and `0xF` are deep gray and white, respectively, according to the default palette of the game (click the triangle icon below to show the colormap).
  <details><summary>Palette</summary>
  <img src="/p58/colormap.png">
  </details>

* The argument `pos` defines the upper left corner of the rect, and `pos`=(`left`+640`top`)/8. Recall that the PC98 graphics hardware system groups every 8 pixels in a row, which explains why `pos` is divided by 8 in the end. For the same reason, the argument `left` in the second function is also 1/8 of the actual *left* coordinate. The argument `length` in both functions is the number of digits and defines the width of the rect, which is equal to 16*`length`, because each full-width character is 16-pixel wide (and also 16-pixel high, which is why `height`=16).
* With the knowledge of how these functions work, our patch is simple: Move the rect to the left and make it wider. Again taking HP as an example, we now write: `sub_1fcd9(6405, 5, 16, 0xdd); sub_1b8d6(5, 80, HP, 5, 0xff)` instead; likewise for other properties.
* There is one little optimization, though, so that we can make less patches. The real `left` position of the right-aligned text is calculated by `left + 2*(length - len(str(value)))` (the coefficent 2 here is because 16=8\*2), so obviously, the effect of `left=5; length=5` is the same as setting `left=7; length=4`. Though less straightforward, the latter assignment reduces one place to change for each property.

### Set font style
* The game program, by default, draws all text in bold. This effect is actually achived by stroke, i.e., simply drawing the same text again but offset by 1 pixel to the right.
* The text drawing function is `sub_20a12` (or `sub_20aba` if you are in the EPSON286 character-display mode by specifying the argument `EP286` in the command line). The relevant instructions are shown below (using pseudocode):

```python
planes = [0xa800, 0xb000, 0xb800, 0xe000] # B G R E color planes
for i in planes:
  sub_20a5a(i) # or sub_20b03(i)
# <--
for i in planes:
  sub_20a7c(i) # or sub_20b31(i)
```

The second calls implement the "stroke" effect. If we do not want to have this effect, i.e. to draw the texts in a regular font weight, we can insert a `return` opcode (`C3`) in the line marked by an arrow to skip the instructions afterwards.

### Set HP/ATK/DEF=8000/5000/1000 after the prologue
* Normally, after the prologue (meeting Zeno on 3F), your HP/ATK/DEF will be set to be 400/10/10. The relevant instructions are in `loc_16ebd` and shown below:
  ```asm
  seg001:0677      mov  es, seg_278BA   ; seg008
  seg001:067B      mov  es:[0x98], 1000 ; HP
  seg001:0682      mov  ax, 10
  seg001:0685      mov  es, seg_278BC   ; seg008
  seg001:0689      mov  es:[0x9c], ax   ; ATK
  seg001:068D      mov  es, seg_278BE   ; seg008
  seg001:0691      mov  es:[0x16], ax   ; DEF
  ```
* We can cheat here (cheating is not good, though!) and change these properties to be the same as Zeno (8000/5000/1000). As mentioned above, the instruction `mov es, [seg_008]` is redundant except its first occurrence. So we can simply write instead:
  ```asm
  mov es, seg_278BA
  mov es:[0x98], 8000
  mov es:[0x9c], 5000
  mov es:[0x16], 1000
  nop
  ...
  ```

### Show menu right before the epilogue
* Once you enter the Gate of the Space and Time, you will directly go to 50F and immediately trigger the epilogue. Therefore, it is impossible to do anything here, such as to view the properties of Zeno or save data or use an item. This patch, however, can show the menu right after you are done talking with Zeno and before the epilogue is triggered, thus making the aforementioned operations possible.
* The relevant function is `sub_1c4d8`, and the epilogue is triggered at offset `1CC72` (`seg001:63c2`), right before which is likely a sleep function, `sub_1f9e2(duration=50)`. This sleep function does not matter much, so we can replace it with calling instead `sub_10a5a()`, i.e. the function to show the menu. The corresponding assembly codes before and after patching are:

```asm
seg001:63B6      mov   ax, 50     ->  nop
seg001:63B9      push  ax         ->  nop
seg001:63BA      call  sub_1F9E2  ->  call  sub_10a5a
```

### Extend display range of supported Kanji (Han) chars
* Do not use this patch. For the Chinese translated version, this place has already been patched. For the Japanese version, patching this place will cause mojibake (文字化け; 乱码).
* More details are discussed [here](/gtx#support-for-more-kanji-chars).
