PRO image_process_demo
  COMPILE_OPT IDL2 ; 推荐使用，强制使用标准语法

  ; ==========================================
  ; 1. 选择图像文件，打开加载显示 (对应图中第1步)
  ; ==========================================

  ; 弹出对话框选择文件
  fileImgPath = DIALOG_PICKFILE(TITLE='请选择图像文件')
  IF (fileImgPath EQ '') THEN RETURN ; 如果用户取消，则退出
  PRINT, 'Selected File: ', fileImgPath

  ; 读取图像数据
  imgP = READ_IMAGE(fileImgPath)

  ; 获取图像尺寸 [波段数, 列数, 行数]
  sz = SIZE(imgP, /DIMENSIONS)

  ; 获取ENVI系统变量（确保ENVI处于运行状态）
  ENVI, /RESTORE_BASE_SAVE_FILES
  ENVI_BATCH_INIT, LOG_FILE='batch.txt'

  ; 显示图像 (这里使用IDL自带的image函数)
  ; 如果是ENVI Classic模式，通常使用 tv 或 envi_display
  gCI = IMAGE(imgP, DIMENSIONS=[sz[0], sz[1]], TITLE='Original Image - '+FILE_BASENAME(fileImgPath))

  ; ==========================================
  ; 2. 图像灰度变换处理 (对应图中第2步)
  ; ==========================================

  ; 注意：图片中的 color_convert 通常需要 3通道(RGB) 图像。
  ; 如果读取的是单波段灰度图，直接进行 RGB_HLS 转换会报错。
  ; 这里我们假设读取的是 RGB 图像 (sz[0] eq 3)

  IF (sz[0] EQ 3) THEN BEGIN
    ; 将 RGB 转换为 HLS (色相、亮度、饱和度)
    COLOR_CONVERT, imgP, preImgDataRGB_HIS, /RGB_HLS

    ; 显示处理后的结果
    ; 注意：layout=[4,2,5] 意味着 4列2行，第5个位置
    ; 这里的 preImgDataRGB_HIS 通常包含3个波段
    preImg_HIS = IMAGE(preImgDataRGB_HIS, LAYOUT=[4,2,5], TITLE='HLS Transform', /CURRENT)
  ENDIF ELSE BEGIN
    PRINT, '警告: 图像不是RGB格式，跳过HLS转换。'
  ENDELSE

  ; ==========================================
  ; 3. 图像区域块处理 (对应图中第3步)
  ; ==========================================

  ; 复制一份数据用于处理，避免修改原始数据
  imgDataB_NEW = imgP

  ; 图片中代码片段：对特定区域进行阈值处理
  ; 注意：imgDataB 在图中未定义，这里假设它是单波段数据 (sz[0] eq 1 的情况)
  ; 为了演示，我们取第一波段 (如果有多波段)
  imgDataB = REFORM(imgP[0, *, *])

  ; 图片中的循环范围：xc=50 到 szImg[2]-50, yR=0 到 150
  ; 注意：IDL中数组索引是 [列, 行] 还是 [x, y]，这里的 szImg[2] 通常指列数
  xSize = sz[0] ; 假设第一维是列数
  ySize = sz[1] ; 假设第二维是行数

  ; 遍历区域 (参考图中逻辑)
  ; 注意：IDL循环通常尽量避免在大图像中使用双重for循环，此处仅为还原图中逻辑
  FOR xc = 50, (xSize - 50) - 1 DO BEGIN
    FOR yR = 0, 150 DO BEGIN
      ; 获取像素值
      pixelValue = imgDataB[xc, yR]

      ; 如果像素值大于 88，则设为 255 (白色)
      IF (pixelValue GT 88) THEN BEGIN
        ; 注意：如果处理的是多波段图像，需要同步修改所有波段
        imgDataB_NEW[0, xc, yR] = 255
      ENDIF
    ENDFOR
  ENDFOR

  ; 显示处理后的图像
  imgResult = IMAGE(imgDataB_NEW, LAYOUT=[4,2,6], TITLE='Region Processed', /CURRENT)

  ; ==========================================
  ; 4. 图像保存
  ; ==========================================

  ; 使用 WRITE_IMAGE 保存处理后的结果
  outPath = DIALOG_PICKFILE(/WRITE, TITLE='保存处理后的图像', DEFAULT_EXTENSION='tif')
  IF (outPath NE '') THEN BEGIN
    ; 如果是保存为TIF，建议先转换为byte类型
    WRITE_IMAGE, outPath, BYTE(imgDataB_NEW), /TIFF
    PRINT, '图像已保存至: ', outPath
  ENDIF

  ; ==========================================
  ; 5. 图像布局显示补充
  ; ==========================================
  ; 图片第4步提到“利用Image结合layout等完成”，上面的代码中已经使用了 LAYOUT 关键字
  ; 如果需要更复杂的布局，可以使用 WIDGET 或 ENVI 的界面组件

END