;--------------------------------------------------------------------
;image_exercise261029.pro   图像综合练习
;
; 运行方法（IDL 命令行）：
;   .compile zh_practice
;   zh_practice
;--------------------------------------------------------------------
FUNCTION getBand, img, bandNo
  dim = SIZE(img, /N_DIMENSIONS)
  IF dim EQ 2 THEN RETURN, img
  IF dim EQ 3 THEN RETURN, img[bandNo, *, *]
  PRINT, 'Error: Image dimension must be 2 or 3.'
  RETURN, !NULL
END

pro image_exercise261029

  COMPILE_OPT IDL2
  
  COMMON IMG_DATA, current_img
  
  ; 创建基础容器
  base = WIDGET_BASE(TITLE='IDL Image Viewer - Exercise', /COLUMN)
  
  ; 创建按钮区域
  btn_base = WIDGET_BASE(base, /ROW)
  btn_load = WIDGET_BUTTON(btn_base, VALUE='1. Load & Display', UVALUE='ACT_LOAD')
  btn_band = WIDGET_BUTTON(btn_base, VALUE='2. Extract Band & Save', UVALUE='ACT_BAND')
  btn_invert = WIDGET_BUTTON(btn_base, VALUE='3. Invert R-Band', UVALUE='ACT_INVERT')
  btn_rgb = WIDGET_BUTTON(btn_base, VALUE='4. RGB Composite', UVALUE='ACT_RGB')
  
  ; 【关键修复】：给绘图区域加上 UNAME='MY_DRAW'
  draw = WIDGET_DRAW(base, XSIZE=600, YSIZE=500, UNAME='MY_DRAW')
  
  WIDGET_CONTROL, base, /REALIZE
  XMANAGER, 'gui_image_exercise', base, EVENT_HANDLER='gui_event', /NO_BLOCK
END


; ==========================================================
; 3. 事件处理函数
; ==========================================================
PRO gui_event, event
  COMPILE_OPT IDL2
  
  COMMON IMG_DATA, current_img
  
  ; 获取触发事件的控件 UVALUE
  WIDGET_CONTROL, event.id, GET_UVALUE=action_id
  
  ; 如果点击的是没有 UVALUE 的组件（比如窗口本身），直接返回
  IF (N_ELEMENTS(action_id) EQ 0) THEN RETURN
  
  ; 【关键修复】：通过 UNAME 查找画布组件，再获取底层窗口 ID
  drawID = WIDGET_INFO(event.top, FIND_BY_UNAME='MY_DRAW')
  WIDGET_CONTROL, drawID, GET_VALUE=winID
  
  CASE action_id OF
    'ACT_LOAD': BEGIN
      file = DIALOG_PICKFILE(TITLE='Select Image', FILTER='*.tif;*.jpg;*.png')
      IF (file EQ '') THEN RETURN
      
      current_img = READ_IMAGE(file)
      HELP, current_img
      
      WSET, winID
      dims = SIZE(current_img, /N_DIMENSIONS)
      IF dims EQ 3 THEN TVSCL, current_img, TRUE=1 ELSE TVSCL, current_img
    END
    
    'ACT_BAND': BEGIN
      IF (N_ELEMENTS(current_img) EQ 0) THEN RETURN
      band1 = getBand(current_img, 0)
      
      WSET, winID
      TVSCL, band1
      
      out_file = DIALOG_PICKFILE(TITLE='Save Band 1', DEFAULT_EXTENSION='tif', /WRITE)
      IF (out_file NE '') THEN WRITE_TIFF, out_file, BYTE(band1)
    END
    
    'ACT_INVERT': BEGIN
      IF (N_ELEMENTS(current_img) EQ 0) THEN RETURN
      R_band = getBand(current_img, 0)
      R_inv = 255B - BYTE(R_band)
      
      WSET, winID
      TVSCL, R_inv
      
      out_file = DIALOG_PICKFILE(TITLE='Save Inverted Image', DEFAULT_EXTENSION='png', /WRITE)
      IF (out_file NE '') THEN WRITE_IMAGE, out_file, R_inv
    END
    
    'ACT_RGB': BEGIN
      IF (N_ELEMENTS(current_img) EQ 0) THEN RETURN
      dims = SIZE(current_img, /N_DIMENSIONS)
      IF (dims NE 3) THEN RETURN
      
      R = BYTSCL(getBand(current_img, 0))
      G = BYTSCL(getBand(current_img, 1))
      B = BYTSCL(getBand(current_img, 2))
      
      sz = SIZE(current_img, /DIMENSIONS)
      rgb = BYTARR(3, sz[1], sz[2])
      rgb[0, *, *] = R
      rgb[1, *, *] = G
      rgb[2, *, *] = B
      
      WSET, winID
      TV, rgb, TRUE=1
      
      out_file = DIALOG_PICKFILE(TITLE='Save RGB Composite', DEFAULT_EXTENSION='tif', /WRITE)
      IF (out_file NE '') THEN WRITE_TIFF, out_file, rgb
    END
  ENDCASE
END