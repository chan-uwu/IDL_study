;--------------------------------------------------------------------
;image_exercise261029.pro   图像综合练习
;
; 运行方法（IDL 命令行）：
;   .compile zh_practice
;   zh_practice
;--------------------------------------------------------------------
FUNCTION getBand, img, bandNo
  ; 获取图像维度
  dim = SIZE(img, /N_DIMENSIONS)

  ; 如果维度是 2 (灰度图)，直接返回原图
  IF dim EQ 2 THEN RETURN, img

  ; 如果维度是 3 (RGB/多波段图)，返回指定波段
  IF dim EQ 3 THEN RETURN, img[bandNo, *, *]

  ; 如果都不是，提示错误并返回空
  PRINT, 'Error: Image dimension must be 2 or 3.'
  RETURN, !NULL
END

pro image_exercise261029

  ;================ 一、多波段遥感图像：读入 -> 查看 -> 显示单波段 -> 另存 ====
  file = DIALOG_PICKFILE(TITLE='Select a multi-band TIFF image')
  img  = READ_TIFF(file)
  HELP, img                              ; 看波段数、行列数、数据类型

  band1 = img[0,*,*]                     ; 第 1 波段（首维为波段）
  ; band1 = img[*,*,0]                   ; 若图像是 [列,行,波段] 排列，改用这一句

  WINDOW, 0, TITLE='Band 1'
  TVSCL, band1                           ; 按数值范围自动拉伸后显示
  WRITE_TIFF, 'D:\Temp\output\band1.tif', band1         ; 单波段另存

  ; ==========================================================
  ; 获取图像波段函数 (根据 PPT 截图编写)
  ; 输入参数：
  ;   img    - 输入的图像数组
  ;   bandNo - 需要提取的波段索引 (如 0, 1, 2)
  ; ==========================================================

  ;================ 二、三个波段合成 RGB 图像 ===============================
  ; 提取三个波段
  R = getBand(img, 0)
  G = getBand(img, 1)
  B = getBand(img, 2)
  ; 拉伸到 0-255
  R = BYTSCL(R)
  G = BYTSCL(G)
  B = BYTSCL(B)

  ; 组成 RGB 图像
  sz     = SIZE(img, /DIMENSIONS)
  width  = sz[1]
  height = sz[2]
  rgb = BYTARR(3, width, height)
  rgb[0,*,*] = R
  rgb[1,*,*] = G
  rgb[2,*,*] = B

  ; 显示
  WINDOW, 1, TITLE='RGB composite'
  TV, rgb, TRUE=1
  ; 保存
  WRITE_TIFF, 'rgb_composite.tif', rgb

  ;================ 三、常规彩色图像：读入 -> 分波段 -> 存 PNG ==============
  file2 = DIALOG_PICKFILE(TITLE='Select a color image (jpg/png/bmp)')
  img2  = READ_IMAGE(file2)
  HELP, img2

  ; 分波段（课件要求：看清 [3,w,h] 的取法）
  R2 = img2[0,*,*]
  G2 = img2[1,*,*]
  B2 = img2[2,*,*]

  ; 保存：WRITE_PNG 只吃 2 个参数（文件名+三波段图像）或 5 个（文件名+二维图像+R+G+B）
  WRITE_PNG, 'D:\Temp\output\rgb_saved.png', img2

  ;================ 四、R 波段反色 ==========================================
  img2[0,*,*] = 255B - img2[0,*,*]
  WRITE_PNG, 'D:\Temp\output\R_inverted.png', img2

end
