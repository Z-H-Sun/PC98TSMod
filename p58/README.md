# P58 encoder and decoder / 编/解码P58图像

## Synopsis / 概要

## Usage / 用法

## Components / 组件

## How does the decoder work? / 解码器工作原理
### General remarks
All pictures of the game are saved as .P58 files, a home-made format by N.W., the developer of the game. Sometimes, there are multiple images in one P58 file, e.g., `MONSTER.P58`, and each image must be a 4-bit image (i.e., the image can only display $2^4=16$ colors) and consist of:
* Header field; 2 bytes; `\x58\x58` ("XX")
* Width and height; 4 bytes; each is an unsigned 16-bit integer. Note that the "width" here is the actual width of the image divided by 8 (see discussions in [the section below](#graphics-system))
* Compressed image data; variant length

The dimension of these images can vary, but it should be no larger than 640\*400 (the screen size), and the width must be an integer multiple of 8. If the image data is not compressed, a 4-bit 640\*400 image requires `640*400*4/256/1024 = 125 KB` space, which is a lot in the floppy disk era. Therefore, compression is desired.

### Compression
The image data is equally divided into 4 color planes, namely blue (B), red (R), green (G), and luminance (E), corresponding to the $2^4=16$ choices of color. We will discuss more details in [the following section](#graphics-system), but for now, let's focus on the compression algorithm.

The decoding rule of this home-made compression algorithm can be found in `sub_1f7df` (offset `seg005:01ef`; see [README of patchTS](/patch#preparation) for more details on the naming convention of addresses; same below). We will describe below how to retrieve the flat raw data from the compressed data:

If the current byte is not `\x58` ("X"), write the byte as is; if a `\x58` is met, check if the following byte $i$ is
* `\x63`, then write `\x58`, i.e., `\x58\x63` is an escape sequence of `\x58` itself.
* `\x40` to `\x62`, then write this byte `\x[i]`, i.e., `\x58\x[i]` is an escape sequence of `\x[i]`, where 0x40≤ $i$ ≤0x62.
* `\x00` or `\x01`, then read the next 1 or 2 bytes, respectively, as an unsigned integer $j$, and write `\x00` for $j$ times.
* `\x02` or `\x03`, then read the next 1 or 2 bytes, respectively, as an unsigned integer $j$, and write `\xff` for $j$ times.
* `\x04` to `\x27`, then read the next 1 or 2 bytes if $i$ is even or odd, respectively, as an unsigned integer $j$, then read the following $\lfloor i/2 \rfloor$ bytes, and then write these $\lfloor i/2 \rfloor$ bytes for $j$ times on a rotational basis.
  * For example, `\x58\x06\x07\x01\x02\x03` means to write the 6//2=3 bytes `\x01\x02\x03` for 7 times, i.e., `\x01\x02\x03\x01\x02\x03\x01`.
* `\x32` or `\x33`, then read the next 1 or 2 bytes, respectively, as an unsigned integer $j$, and copy the $j$ bytes from the `B` color plane (at the same location; same below).
* `\x34` or `\x35`, then read the next 1 or 2 bytes, respectively, as an unsigned integer $j$, and copy the invert of the $j$ bytes from the `B` color plane (i.e., perform the `NOT` bitwise operation).
* `\x36` to `\x39`, similar to `\x32` to `\x35` but copy from the `R` instead of `B` color plane.
* `\x3a` to `\x3d`, similar to `\x32` to `\x35` but copy from the `G` instead of `B` color plane.

Now we get the flat image data, but it is still very different from a modern image format, e.g., BMP file. We then have to explain the graphics system of PC98, elaborated below.

### Graphics system
In the early days, the 4 color planes are just like the color channels in modern graphics formats. For example, if the `R` and `G` bits are set `1` while the `B` and `E` bits are set `0`, then the pixel shows yellow color. A complete list of the 16 combinations of `B`, `R`, `G`, and `E` bits and their corresponding colors are shown below (click the triangle icon to expand).
<details><summary>The original 16-color BRGE system</summary>
<p align="center"><img src="http://radioc.web.fc2.com/column/pc98bas/img/pc98disphw_1_en.png"></p>
</details>

Later on, the technology of color display got improved, so PC98 could display up to 4096 colors; however, the video card RAM was still the bottleneck, which could only store 16 colors for each pixel of the 640\*400 screen, i.e., there can be only 16 out of 4096 colors on the screen at a time. Nevertheless, by changing the palette register, the image could then display new colors other than the 16 colors of the default palette shown in the picture above. In doing so, the names `B`, `R`, `G`, and `E` lost their physical meaning: For example, one could set `B=1; R=0; G=0; E=0` (which should have been blue) as a red color in the palette. Anyways, one combination of `BRGE` bits defines one of the 16 colors predefined by the palette specified by the program. In TowerOfTheSorcerer game, most images uses the following palette, but there are a few exceptions, e.g., MTOWER1.P58.

![](/p58/colormap.png)

For more information, refer to [this webpage](http://radioc.web.fc2.com/column/pc98bas/pc98disphw2.htm) (It has [an English version](http://radioc.web.fc2.com/column/pc98bas/pc98disphw_en.htm), but the English version provides less details).

In summary, each color plane stores 1 of the 4 bits of 16 colors for all pixels in the image. This is in direct contrast to the BMP format, which stores all the color information together for each pixel. In fact, bit-wise speaking, these two formats can be converted to each other by transposing. However, computers store data in bytes, not bits. So the former data format will have to "group" every 8 bits for 8 adjacent pixels together into a byte. That is the reason why the images stored as P58 format must have a width divisible by 8, and it is 1/8 of the width, not the actual width, that is stored in the header.

Given the way how the low-level hardware deals with the graphics, it is understandable that N.W. did not choose the BMP format (based on pixels) but rather the other way (based on color planes). Once the image data for each color plane is decompressed, they can be directly copied to the video card RAM without further transform. These operations can be found in `sub_1f77d` (offset `seg005:018d`):

```asm
... ; load 1/8 width; check if > 80; load height; check if > 400
mov  ax, cs:[word_1f676] ; 0A800h, B plane
call sub_1f7df           ; decompress and copy to video RAM
call sub_1f7cf           ; rearrange the segment:offset pair to avoid offset overflow
mov  ax, cs:[word_1f678] ; 0B000h, R plane
call sub_1f7df
call sub_1f7cf
mov  ax, cs:[word_1f67a] ; 0B800h, G plane
call sub_1f7df
call sub_1f7cf
mov  ax, cs:[word_1f67c] ; 0E000h, E plane
call sub_1f7df
retn
```

## What's in each P58 file? / 各个P58图像文件里的内容
### GROUND.P58
In sequential order, there are floor, wall, door, blue door, red door, gate, prison bars, stairs up, stairs down, lava, battle effect, transition animation (Weaponer and Intellion), box frame, and starlight (14 images in total).

### ITEM.P58
In sequential order, there are key, red key, blue key, red potion, blue potion, red crystal, blue crystal, and the 15 items (OrbOfHero, ..., LuckyGold; 22 images in total).

### LCG.P58
There are 7 images in total, which in sequential order are:
* The backgound image of the game, including the status bar, the item bar, the equipment bar, and so on;
* The dialog window frame;
* The animation of opening a door;
* The animation of opening a blue door;
* The animation of opening a red door;
* The animation of opening a gate;
* The animation of the fusion of 8 Big Bats (into the Vampire);

### MONSTER.P58
* There are 102 images in total.
* Except Giant Octopus and Dragon, each of which has 9*2=18 images, each of the remaining 31 monsters has 2 frames.
* In addition, there are 4 additional images corresponding to (for some unknown reason) discarded draft designs of Zeno (ゼノ; 芝诺) and Archsorcerer (大魔導師; Great Magic Master).

### MTENDMJ.P58 (MT=Matō=魔塔=MagicTower; END=Ending; MJ=Moji=文字=words)
The epilogue narration, which writes:
> The long battle has come to an end, and the tower of vanity crumbled away.
>
> The gods returned to the heaven, and the warrior returned to the earth.
>
> The present transforms into the past, and this journey has also become an echo of yesterday.
>
> You will look back just for a moment and then embark on a new journey...

Japanese:
> 長い戦いは終わいを告げ、虚栄の塔は崩れ去る。
>
> 神々は天へと帰り、戦士は大地へと戻った。
>
> 現在は過去へと移り変わり、この旅も過去の物に成ろうとしている。
>
> あなたは、少しだけ振り返り、新たな旅へと歩き出すのであった。

### MTFIN.P58
Ending screen, which will show after the epilogue narration.

### MTMOJI.P58 (MT=Matō=魔塔; Moji=文字=words)
Start screen, which will show after the prologue narration.

### MTOPSTR.E58 (MT=Matō=魔塔; OP=opening; STR=??? (string?))
The prologue narration, which writes:
> The time has come...
>
> With my omniscient power, I shall shatter the Sacred Sword
>
> and gain great wisdom...

Japanese:
> 時は来たれり…
>
> 我、全能の力を用いて、神剣を砕き、
>
> 偉大なる知恵を手に入れん…

### MTOWER1.P58 and MTOWER2.P58
The animation of the tower falling down. MTOWER1 draws the tower, and MTOWER2 draws the background.

### MTWAKU.P58 (MT=Matō=魔塔; Waku=枠=frame)
It has the same content as the first image of LCG.P58, but for some unknown reason, this picture is not used.

### OBJECT.P58
There are 14 images in total. In sequential order,
* The first 4 are the altar (祭壇);
* The next 2 are the merchant (商人);
* The next 2 are the thief (盜賊);
* The next 2 are the fairy (妖精);
* The next 2 are the oldman (老人);
* The final 2 are the princess (姫).

### PICTURE.P58
There are 5 images in total. In sequential order,
* The first 3 are the icons that stand for yellow, blue, and red keys in the key column;
* The other 2 are the animated selection icons in the menu.

### PLAYER1.P58 and PLAYER2.P58
The 2 frames of the player (勇者; braveman).

### WEAPON.P58
The first 5 are swords (long/長, silver/銀, knight/騎士, holy/聖, and sacred/神), and the last 5 are shields (iron/鉄, silver/銀, knight/騎士, holy/聖, and sacred/神).