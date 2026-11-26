;+
;===========================================================================
; File    : RS_CONV_DENOISE.pro
; Purpose : IDL Widget GUI tool for remote sensing image convolution denoising.
;           Open grayscale/single-band image -> show original -> 3x3
;           convolution/median filtering -> show result -> save TIFF.
; Env     : IDL 8.x or later (READ_IMAGE / CONVOL / WRITE_TIFF built in).
;
; NOTE    : This source is pure ASCII on purpose. No Chinese characters are
;           used in comments, labels or messages, so there is no encoding
;           problem on any IDL installation.
;
; MODULES
;   1) RS_CD_HAS_ROUTINE    : test whether a built-in routine is available
;   2) RS_CD_GET_KERNEL     : build the 3x3 kernel chosen from the drop list
;   3) RS_CD_KERNEL_TEXT    : format kernel coefficients for the text widget
;   4) RS_CD_PARSE_KERNEL   : parse 9 user numbers into a 3x3 kernel
;   5) RS_CD_SHOW_KERNEL    : refresh the kernel display for the selected filter
;   6) RS_CD_DROP_INDEX     : normalize WIDGET_DROPLIST GET_VALUE result
;   7) RS_CD_READ_IMAGE     : read an image and convert it to 2-D gray data
;   8) RS_CD_SCALE_BYTE     : map float result to BYTE 0..255
;   9) RS_CD_CONVOLVE       : custom 2-D convolution (FOR loops, edge copy)
;  10) RS_CD_MEDIAN3        : custom 3x3 median filter
;  11) RS_CD_DRAW           : draw a 2-D gray image inside WIDGET_DRAW
;  12) RS_CD_CLEAR_DRAW     : clear one draw area
;  13) RS_CONV_DENOISE_EVENT: event handler (buttons, list, expose, close)
;  14) RS_CONV_DENOISE      : main procedure, builds GUI, calls XMANAGER
;
; USAGE
;   IDL> CD, 'D:\Github\IDL'
;   IDL> RS_CONV_DENOISE
;
; NOTES
;   - Image arrays are stored through POINTERS in the widget state. IDL
;     structure fields have fixed dimensions, so pointers are required.
;   - Uncheck "Use built-in CONVOL" to run the teaching implementation
;     (nested FOR loops). Check it on large images for better speed.
;   - Display and saving share the same gray-level range of the original
;     image, so the two draw areas can be compared directly.
;===========================================================================
;-

;------------------------------------------------------------------
; FUNCTION: RS_CD_HAS_ROUTINE
; Return 1 if the named routine exists, otherwise 0.
;------------------------------------------------------------------
FUNCTION RS_CD_HAS_ROUTINE, name
  result = 0
  err = 0
  CATCH, err
  IF err EQ 0 THEN info = ROUTINE_INFO(name)
  IF (err EQ 0) AND (SIZE(info, /TNAME) EQ 'STRUCT') THEN result = 1
  CATCH, /CANCEL
  RETURN, result
END

;------------------------------------------------------------------
; FUNCTION: RS_CD_GET_KERNEL
; Build a 3x3 kernel from the drop-list index.
;   0 = mean, 1 = Gaussian, 2 = sharpen, 3 = median (dummy), 4 = custom (dummy)
; Elements are assigned one by one on purpose: nested [] array
; constructors can have different orientations in different IDL versions.
;------------------------------------------------------------------
FUNCTION RS_CD_GET_KERNEL, idx, name
  CASE idx OF
    0: BEGIN
      ; Box mean filter: every element equals 1/9
      k = FLTARR(3, 3) + (1.0 / 9.0)
      name = 'Mean filter (3x3)'
    END
    1: BEGIN
      ; Gaussian smoothing: centre weight is largest, sum = 16
      k = FLTARR(3, 3)
      k[0, 0] = 1.0 & k[1, 0] = 2.0 & k[2, 0] = 1.0
      k[0, 1] = 2.0 & k[1, 1] = 4.0 & k[2, 1] = 2.0
      k[0, 2] = 1.0 & k[1, 2] = 2.0 & k[2, 2] = 1.0
      k = k / 16.0
      name = 'Gaussian smoothing (3x3)'
    END
    2: BEGIN
      ; Laplacian sharpening kernel, sum = 1
      k = FLTARR(3, 3)
      k[0, 0] = -1.0 & k[1, 0] = -1.0 & k[2, 0] = -1.0
      k[0, 1] = -1.0 & k[1, 1] =  9.0 & k[2, 1] = -1.0
      k[0, 2] = -1.0 & k[1, 2] = -1.0 & k[2, 2] = -1.0
      name = 'Sharpening (3x3 Laplacian)'
    END
    3: BEGIN
      ; Median filter does not use a kernel; return a dummy one
      k = FLTARR(3, 3)
      name = 'Median filter (3x3)'
    END
    4: BEGIN
      ; The real custom kernel is parsed from the text widget.
      k = FLTARR(3, 3)
      name = 'Custom kernel (3x3)'
    END
    ELSE: BEGIN
      k = FLTARR(3, 3) + (1.0 / 9.0)
      name = 'Mean filter (3x3)'
    END
  ENDCASE
  RETURN, k
END

;------------------------------------------------------------------
; FUNCTION: RS_CD_KERNEL_TEXT
; Convert a kernel to a string array for WIDGET_TEXT display.
;------------------------------------------------------------------
FUNCTION RS_CD_KERNEL_TEXT, k
  dims = SIZE(k, /DIMENSIONS)
  nx = dims[0] & ny = dims[1]
  txt = STRARR(ny)
  FOR j = 0, ny - 1 DO BEGIN
    line = ''
    FOR i = 0, nx - 1 DO BEGIN
      line = line + STRING(k[i, j], FORMAT = '(F7.4)') + '  '
    ENDFOR
    txt[j] = line
  ENDFOR
  RETURN, txt
END

;------------------------------------------------------------------
; FUNCTION: RS_CD_IS_NUMBER
; Return 1 if the string looks like a number (digits, sign, dot, e/E).
;------------------------------------------------------------------
FUNCTION RS_CD_IS_NUMBER, s
  s = STRTRIM(s, 2)
  IF (s EQ '') THEN RETURN, 0
  valid = '0123456789+-.eE'
  FOR c = 0, STRLEN(s) - 1 DO BEGIN
    IF (STRPOS(valid, STRMID(s, c, 1)) LT 0) THEN RETURN, 0
  ENDFOR
  RETURN, 1
END

;------------------------------------------------------------------
; FUNCTION: RS_CD_PARSE_KERNEL
; Parse the custom kernel text: 3 lines, 3 numbers per line.
;   txt       - input string array from WIDGET_TEXT
;   normalize - input, if set divide every element by the kernel sum
;   kernel    - output 3x3 float kernel
;   msg       - output error description
; Return: 1 = success, 0 = failure.
;------------------------------------------------------------------
FUNCTION RS_CD_PARSE_KERNEL, txt, normalize, kernel, msg
  kernel = FLTARR(3, 3)
  msg = ''

  IF (N_ELEMENTS(txt) LT 3) THEN BEGIN
    msg = 'Need 3 lines with 3 numbers each.'
    RETURN, 0
  ENDIF

  ; Collect the numbers from all three lines. Commas or spaces are
  ; accepted as separators.
  ; IDL does not allow a zero-length array, so use a fixed 9-element
  ; buffer plus a counter instead of growing an empty array.
  tokens = STRARR(9)
  ntokens = 0L
  FOR r = 0, 2 DO BEGIN
    parts = STRSPLIT(STRTRIM(txt[r], 2), '[ ,]+', /EXTRACT, /REGEX, COUNT = n)
    IF n GT 0 THEN BEGIN
      FOR p = 0, n - 1 DO BEGIN
        IF ntokens LT 9 THEN tokens[ntokens] = parts[p]
        ntokens = ntokens + 1
      ENDFOR
    ENDIF
  ENDFOR

  IF (ntokens NE 9) THEN BEGIN
    msg = 'Need exactly 9 numbers, 3 per line.'
    RETURN, 0
  ENDIF

  FOR k = 0, 8 DO BEGIN
    IF (~RS_CD_IS_NUMBER(tokens[k])) THEN BEGIN
      msg = 'Not a number: ' + STRTRIM(tokens[k], 2)
      RETURN, 0
    ENDIF
    err = 0
    CATCH, err
    IF err EQ 0 THEN v = FLOAT(tokens[k])
    IF err NE 0 THEN BEGIN
      CATCH, /CANCEL
      msg = 'Cannot convert: ' + STRTRIM(tokens[k], 2)
      RETURN, 0
    ENDIF
    CATCH, /CANCEL
    col = k MOD 3
    row = k / 3
    kernel[col, row] = v
  ENDFOR

  IF normalize THEN BEGIN
    s = TOTAL(kernel)
    IF (s NE 0.0) THEN kernel = kernel / s
  ENDIF
  RETURN, 1
END

;------------------------------------------------------------------
; PROCEDURE: RS_CD_SHOW_KERNEL
; Refresh the read-only kernel display according to the selected filter.
;   idx = 0..2 predefined kernel, 3 median, 4 custom.
;------------------------------------------------------------------
PRO RS_CD_SHOW_KERNEL, pState, idx
  CASE idx OF
    3: BEGIN
      ktxt = ['Median filter: middle value of the 3x3 neighbourhood', $
              'No kernel; implemented with FOR loops.']
    END
    4: BEGIN
      WIDGET_CONTROL, (*pState).wCustom, GET_VALUE = ctxt
      ok = RS_CD_PARSE_KERNEL(ctxt, 0B, k, msg)
      IF ok THEN BEGIN
        ktxt = RS_CD_KERNEL_TEXT(k)
      ENDIF ELSE BEGIN
        ktxt = ['Invalid custom kernel:', msg]
      ENDELSE
    END
    ELSE: BEGIN
      k = RS_CD_GET_KERNEL(idx, kname)
      ktxt = RS_CD_KERNEL_TEXT(k)
    END
  ENDCASE
  WIDGET_CONTROL, (*pState).wKernel, SET_VALUE = ktxt
END

;------------------------------------------------------------------
; FUNCTION: RS_CD_DROP_INDEX
; In different IDL versions WIDGET_DROPLIST GET_VALUE returns either a
; scalar index or a byte status array. Normalize both to a scalar index.
;------------------------------------------------------------------
FUNCTION RS_CD_DROP_INDEX, v
  IF (N_ELEMENTS(v) GT 1) THEN BEGIN
    pos = WHERE(v NE 0, cnt)
    IF cnt GT 0 THEN RETURN, LONG(pos[0]) ELSE RETURN, 0L
  ENDIF
  RETURN, LONG(v[0])
END

;------------------------------------------------------------------
; FUNCTION: RS_CD_READ_IMAGE
; Read TIF/PNG/JPG/BMP etc. and convert to a 2-D gray array.
;   inFile - input file name
;   data   - output [cols, rows] float gray image
;   info   - output description string
; Return: 1 = success, 0 = failure.
;------------------------------------------------------------------
FUNCTION RS_CD_READ_IMAGE, inFile, data, info
  data = 0
  info = ''

  IF (STRTRIM(inFile, 2) EQ '') THEN RETURN, 0
  IF (~FILE_TEST(inFile, /READ)) THEN BEGIN
    void = DIALOG_MESSAGE('File not found or not readable: ' + inFile, /ERROR)
    RETURN, 0
  ENDIF

  ; READ_IMAGE recognizes most common image formats
  err = 0
  CATCH, err
  IF err EQ 0 THEN raw = READ_IMAGE(inFile)
  IF err NE 0 THEN BEGIN
    msg = !ERROR_STATE.MSG
    CATCH, /CANCEL
    void = DIALOG_MESSAGE('Failed to read image: ' + msg, /ERROR)
    RETURN, 0
  ENDIF
  CATCH, /CANCEL

  sz = SIZE(raw, /DIMENSIONS)
  nd = N_ELEMENTS(sz)
  sRaw = SIZE(raw, /STRUCTURE)

  CASE nd OF
    2: BEGIN
      ; Already a single-band 2-D image
      gray = FLOAT(raw)
      bands = 1L
    END
    3: BEGIN
      ; For 3-D data, treat the shortest dimension as the band axis and
      ; reorder to [cols, rows, bands].
      dummy = MIN(sz, bandDim)
      CASE bandDim OF
        0: BEGIN
          ; input [bands, cols, rows]
          cube = TRANSPOSE(raw, [1, 2, 0])
          cols = sz[1] & rows = sz[2] & bands = sz[0]
        END
        1: BEGIN
          ; input [cols, bands, rows]
          cube = TRANSPOSE(raw, [0, 2, 1])
          cols = sz[0] & rows = sz[2] & bands = sz[1]
        END
        2: BEGIN
          ; input [cols, rows, bands]
          cube = raw
          cols = sz[0] & rows = sz[1] & bands = sz[2]
        END
      ENDCASE
      IF bands EQ 1 THEN BEGIN
        gray = FLOAT(REFORM(cube[*, *, 0]))
      ENDIF ELSE BEGIN
        r = FLOAT(REFORM(cube[*, *, 0]))
        g = FLOAT(REFORM(cube[*, *, 1]))
        IF bands GE 3 THEN BEGIN
          b = FLOAT(REFORM(cube[*, *, 2]))
          gray = 0.299 * r + 0.587 * g + 0.114 * b
        ENDIF ELSE BEGIN
          gray = 0.5 * (r + g)
        ENDELSE
      ENDELSE
    END
    ELSE: BEGIN
      void = DIALOG_MESSAGE('Unsupported image dimensions (2-D or 3-D needed).', /ERROR)
      RETURN, 0
    END
  ENDCASE

  data = gray
  szg = SIZE(gray, /DIMENSIONS)
  info = 'Bands: ' + STRTRIM(STRING(bands), 2) + $
         '    Source type: ' + sRaw.TYPENAME + $
         '    Gray size: ' + STRTRIM(STRING(szg[0]), 2) + ' x ' + $
         STRTRIM(STRING(szg[1]), 2)
  RETURN, 1
END

;------------------------------------------------------------------
; FUNCTION: RS_CD_SCALE_BYTE
; Use the gray range of the original image to map a float result to BYTE.
; Both draw areas use the same mapping and can be compared directly.
;------------------------------------------------------------------
FUNCTION RS_CD_SCALE_BYTE, img, mn, mx
  dims = SIZE(img, /DIMENSIONS)
  out = BYTARR(dims[0], dims[1]) + 128B
  d = FLOAT(img)

  good = WHERE(FINITE(d), cnt)
  IF cnt EQ 0 THEN RETURN, out

  IF (mx EQ mn) THEN BEGIN
    out[good] = 128B
  ENDIF ELSE BEGIN
    v = (d - mn) * 255.0 / (mx - mn)
    v = v > 0.0 < 255.0
    out[good] = BYTE(v[good])
  ENDELSE

  bad = WHERE(FINITE(d) EQ 0, bc)
  IF bc GT 0 THEN out[bad] = 0B
  RETURN, out
END

;------------------------------------------------------------------
; FUNCTION: RS_CD_CONVOLVE
; Custom 2-D convolution with nested FOR loops.
; Boundary handling: replicate edge pixels (no dark border).
;   img    - input 2-D gray array
;   kernel - convolution kernel (3x3)
; Return: float array with the same size as img.
;------------------------------------------------------------------
FUNCTION RS_CD_CONVOLVE, img, kernel
  dims = SIZE(img, /DIMENSIONS)
  nx = dims[0] & ny = dims[1]
  kd = SIZE(kernel, /DIMENSIONS)
  kx = kd[0] & ky = kd[1]
  hx = kx / 2 & hy = ky / 2
  out = FLTARR(nx, ny)

  FOR j = 0L, ny - 1L DO BEGIN
    FOR i = 0L, nx - 1L DO BEGIN
      acc = 0.0
      FOR b = 0, ky - 1 DO BEGIN
        FOR a = 0, kx - 1 DO BEGIN
          ; In IDL, > means maximum and < means minimum.
          ; Together they clamp the index to the valid range.
          ii = ((i + a - hx) > 0) < (nx - 1)
          jj = ((j + b - hy) > 0) < (ny - 1)
          acc = acc + img[ii, jj] * kernel[a, b]
        ENDFOR
      ENDFOR
      out[i, j] = acc
    ENDFOR
  ENDFOR
  RETURN, out
END

;------------------------------------------------------------------
; FUNCTION: RS_CD_MEDIAN3
; 3x3 median filter. The middle value of 9 neighbours is taken.
; It suppresses salt-and-pepper noise without blurring edges too much.
;------------------------------------------------------------------
FUNCTION RS_CD_MEDIAN3, img
  dims = SIZE(img, /DIMENSIONS)
  nx = dims[0] & ny = dims[1]
  out = FLTARR(nx, ny)

  FOR j = 0L, ny - 1L DO BEGIN
    FOR i = 0L, nx - 1L DO BEGIN
      win = FLTARR(9)
      k = 0
      FOR b = -1, 1 DO BEGIN
        FOR a = -1, 1 DO BEGIN
          ii = ((i + a) > 0) < (nx - 1)
          jj = ((j + b) > 0) < (ny - 1)
          win[k] = img[ii, jj]
          k = k + 1
        ENDFOR
      ENDFOR
      ; MEDIAN returns the 5th value when 9 numbers are given
      out[i, j] = MEDIAN(win)
    ENDFOR
  ENDFOR
  RETURN, out
END

;------------------------------------------------------------------
; PROCEDURE: RS_CD_DRAW
; Scale and centre a 2-D gray image in one WIDGET_DRAW.
;   pState - pointer to the state structure
;   which  - 0 = original draw area, 1 = result draw area
;   img    - 2-D gray image to display
;------------------------------------------------------------------
PRO RS_CD_DRAW, pState, which, img
  IF PTR_VALID(pState) EQ 0 THEN RETURN
  dims = SIZE(img, /DIMENSIONS)
  IF (N_ELEMENTS(dims) LT 2) THEN RETURN
  cols = dims[0] & rows = dims[1]
  IF (cols LT 1) OR (rows LT 1) THEN RETURN

  IF which EQ 0 THEN w = (*pState).wDrawOrig ELSE w = (*pState).wDrawProc
  WIDGET_CONTROL, w, GET_VALUE = winID
  WSET, winID
  DEVICE, DECOMPOSED = 1          ; true colour, no palette dependency

  bw = (*pState).dispW & bh = (*pState).dispH
  bg = BYTARR(3, bw, bh) + 245B   ; light grey background
  TV, bg, TRUE = 1, ORDER = 1

  ; Keep aspect ratio. Only the displayed copy is resized; the full
  ; resolution data is kept for processing and saving.
  sc = MIN([FLOAT(bw) / FLOAT(cols), FLOAT(bh) / FLOAT(rows)])
  dx = (FIX(cols * sc) > 1)
  dy = (FIX(rows * sc) > 1)
  bx = (bw - dx) / 2
  by = (bh - dy) / 2

  g = RS_CD_SCALE_BYTE(img, (*pState).minVal, (*pState).maxVal)
  IF (dx NE cols) OR (dy NE rows) THEN g = CONGRID(g, dx, dy)
  rgb = BYTARR(3, dx, dy)
  rgb[0, *, *] = g & rgb[1, *, *] = g & rgb[2, *, *] = g
  TV, rgb, bx, by, TRUE = 1, ORDER = 1
END

;------------------------------------------------------------------
; PROCEDURE: RS_CD_CLEAR_DRAW
; Clear one draw area, for example when a new image is opened.
;------------------------------------------------------------------
PRO RS_CD_CLEAR_DRAW, pState, which
  IF PTR_VALID(pState) EQ 0 THEN RETURN
  IF which EQ 0 THEN w = (*pState).wDrawOrig ELSE w = (*pState).wDrawProc
  WIDGET_CONTROL, w, GET_VALUE = winID
  WSET, winID
  DEVICE, DECOMPOSED = 1
  bg = BYTARR(3, (*pState).dispW, (*pState).dispH) + 245B
  TV, bg, TRUE = 1, ORDER = 1
END

;------------------------------------------------------------------
; PROCEDURE: RS_CONV_DENOISE_EVENT
; Handle buttons, drop list, toggle button, expose events and kill events.
;------------------------------------------------------------------
PRO RS_CONV_DENOISE_EVENT, ev
  WIDGET_CONTROL, ev.top, GET_UVALUE = pState
  IF (N_ELEMENTS(pState) EQ 0) THEN RETURN
  IF (PTR_VALID(pState) EQ 0) THEN RETURN

  ; ---------- DRAW expose (type=1) / kill (type=2) ----------
  tnames = TAG_NAMES(ev)
  pos = WHERE(tnames EQ 'TYPE', cnt)
  IF cnt GT 0 THEN BEGIN
    IF ev.type EQ 1 THEN BEGIN
      IF (*pState).hasImg THEN RS_CD_DRAW, pState, 0, *((*pState).pOrig)
      IF (*pState).hasResult THEN RS_CD_DRAW, pState, 1, *((*pState).pProc)
    ENDIF
    IF ev.type EQ 2 THEN BEGIN
      IF PTR_VALID((*pState).pOrig) THEN PTR_FREE, (*pState).pOrig
      IF PTR_VALID((*pState).pProc) THEN PTR_FREE, (*pState).pProc
      PTR_FREE, pState
    ENDIF
    RETURN
  ENDIF

  ; ---------- Buttons / drop list / toggle button ----------
  WIDGET_CONTROL, ev.id, GET_UVALUE = uval
  IF (N_ELEMENTS(uval) EQ 0) THEN RETURN

  CASE uval OF

    ; ---------------- Open image ----------------
    'OPEN': BEGIN
      f = DIALOG_PICKFILE(/READ, $
            FILTER = ['*.tif', '*.tiff', '*.png', '*.jpg', '*.jpeg', '*.bmp', '*.*'], $
            TITLE = 'Select a grayscale image or single-band remote sensing image')
      IF (f EQ '') THEN RETURN

      IF RS_CD_READ_IMAGE(f, gray, sInfo) THEN BEGIN
        IF PTR_VALID((*pState).pOrig) THEN PTR_FREE, (*pState).pOrig
        IF PTR_VALID((*pState).pProc) THEN PTR_FREE, (*pState).pProc
        szg = SIZE(gray, /DIMENSIONS)
        (*pState).pOrig     = PTR_NEW(gray)
        (*pState).pProc     = PTR_NEW()
        (*pState).filePath  = f
        (*pState).cols      = szg[0]
        (*pState).rows      = szg[1]
        (*pState).hasImg    = 1B
        (*pState).hasResult = 0B

        ; Store the gray range: display and saving use the same mapping
        good = WHERE(FINITE(gray), cnt)
        IF cnt GT 0 THEN BEGIN
          mn = MIN(gray[good], MAX = mx)
        ENDIF ELSE BEGIN
          mn = 0.0 & mx = 1.0
        ENDELSE
        (*pState).minVal = mn
        (*pState).maxVal = mx

        RS_CD_DRAW, pState, 0, gray
        RS_CD_CLEAR_DRAW, pState, 1

        info = ['File: ' + f, $
                'Size: ' + STRTRIM(STRING((*pState).cols), 2) + ' x ' + $
                          STRTRIM(STRING((*pState).rows), 2) + $
                '    Gray range: ' + STRTRIM(STRING(mn), 2) + ' ~ ' + $
                                    STRTRIM(STRING(mx), 2), $
                sInfo]
        WIDGET_CONTROL, (*pState).wInfo, SET_VALUE = info
        WIDGET_CONTROL, (*pState).wStatus, $
          SET_VALUE = 'Image opened. Select a filter and click [Process].'
      ENDIF
    END

    ; ---------------- Convolution / filter ----------------
    'PROC': BEGIN
      IF (*pState).hasImg EQ 0 THEN BEGIN
        void = DIALOG_MESSAGE('Please open an image first.', /INFO)
        RETURN
      ENDIF

      ; Use the index saved by the KERNEL event. WIDGET_DROPLIST
      ; GET_VALUE may return the text instead of the index.
      idx = (*pState).filterIdx
      k = RS_CD_GET_KERNEL(idx, kname)

      IF idx EQ 4 THEN BEGIN
        WIDGET_CONTROL, (*pState).wCustom, GET_VALUE = ctxt
        WIDGET_CONTROL, (*pState).wChkNorm, GET_VALUE = nv
        normalize = ((N_ELEMENTS(nv) GT 0) AND (nv[0] NE 0))
        IF (~RS_CD_PARSE_KERNEL(ctxt, normalize, kern, msg)) THEN BEGIN
          void = DIALOG_MESSAGE('Custom kernel error: ' + msg, /ERROR)
          RETURN
        ENDIF
      ENDIF ELSE BEGIN
        kern = k
      ENDELSE

      WIDGET_CONTROL, (*pState).wChkFast, GET_VALUE = fv
      fast = ((N_ELEMENTS(fv) GT 0) AND (fv[0] NE 0)) ? 1B : 0B

      img = *((*pState).pOrig)

      IF idx EQ 3 THEN BEGIN
        ; Median filter: no convolution kernel, custom FOR loops
        res = RS_CD_MEDIAN3(img)
      ENDIF ELSE BEGIN
        IF (fast EQ 1B) AND RS_CD_HAS_ROUTINE('CONVOL') THEN BEGIN
          ; Fast path: built-in CONVOL with edge replication
          res = CONVOL(FLOAT(img), kern, /EDGE_TRUNCATE)
        ENDIF ELSE BEGIN
          ; Teaching path: custom four-level FOR-loop convolution
          res = RS_CD_CONVOLVE(img, kern)
        ENDELSE
      ENDELSE

      IF PTR_VALID((*pState).pProc) THEN PTR_FREE, (*pState).pProc
      (*pState).pProc     = PTR_NEW(res)
      (*pState).hasResult = 1B
      RS_CD_DRAW, pState, 1, res

      mode = (idx EQ 3) ? 'FOR-loop median filter' : $
             (((fast EQ 1B) AND RS_CD_HAS_ROUTINE('CONVOL')) ? $
              'built-in CONVOL' : 'custom FOR-loop convolution')
      WIDGET_CONTROL, (*pState).wStatus, $
        SET_VALUE = 'Done: ' + kname + ' (' + mode + '). Click [Save] to export TIFF.'
    END

    ; ---------------- Save result ----------------
    'SAVE': BEGIN
      IF (*pState).hasResult EQ 0 THEN BEGIN
        void = DIALOG_MESSAGE('Please run [Process] before saving.', /INFO)
        RETURN
      ENDIF

      outImg = RS_CD_SCALE_BYTE(*((*pState).pProc), $
                                (*pState).minVal, (*pState).maxVal)
      outFile = DIALOG_PICKFILE(/WRITE, FILE = 'denoised_result.tif', $
                                FILTER = '*.tif', TITLE = 'Save denoised result (TIFF)')
      IF (outFile EQ '') THEN RETURN
      IF (STRLEN(outFile) LT 4) THEN BEGIN
        outFile = outFile + '.tif'
      ENDIF ELSE BEGIN
        IF (STRMID(outFile, STRLEN(outFile) - 4, 4) NE '.tif') THEN $
          outFile = outFile + '.tif'
      ENDELSE

      err = 0
      CATCH, err
      IF err EQ 0 THEN WRITE_TIFF, outFile, outImg, 1
      IF err NE 0 THEN BEGIN
        msg = !ERROR_STATE.MSG
        CATCH, /CANCEL
        void = DIALOG_MESSAGE('Save failed: ' + msg, /ERROR)
        RETURN
      ENDIF
      CATCH, /CANCEL

      void = DIALOG_MESSAGE('Saved: ' + outFile, /INFORMATION)
      WIDGET_CONTROL, (*pState).wStatus, SET_VALUE = 'Saved: ' + outFile
    END

    ; ---------------- Filter selection changed ----------------
    'KERNEL': BEGIN
      ; The WIDGET_DROPLIST event structure has an INDEX field. Use it
      ; directly; GET_VALUE can return the display string instead.
      idx = LONG(ev.index)
      (*pState).filterIdx = idx
      IF idx EQ 4 THEN BEGIN
        WIDGET_CONTROL, (*pState).wCustom, SENSITIVE = 1
      ENDIF ELSE BEGIN
        WIDGET_CONTROL, (*pState).wCustom, SENSITIVE = 0
      ENDELSE
      RS_CD_SHOW_KERNEL, pState, idx
      k = RS_CD_GET_KERNEL(idx, kname)
      WIDGET_CONTROL, (*pState).wStatus, SET_VALUE = 'Filter: ' + kname
    END

    ; ---------------- Custom kernel text edited ----------------
    'CUSTOM': BEGIN
      IF (*pState).filterIdx EQ 4 THEN BEGIN
        RS_CD_SHOW_KERNEL, pState, 4
        WIDGET_CONTROL, (*pState).wStatus, $
          SET_VALUE = 'Custom kernel updated. Click [Process] to apply.'
      ENDIF
    END

    ; ---------------- Normalize custom kernel toggle ----------------
    'NORM': BEGIN
      WIDGET_CONTROL, ev.id, GET_VALUE = nv2
      IF (N_ELEMENTS(nv2) GT 0) AND (nv2[0] NE 0) THEN BEGIN
        WIDGET_CONTROL, (*pState).wStatus, $
          SET_VALUE = 'Custom kernel will be divided by its sum.'
      ENDIF ELSE BEGIN
        WIDGET_CONTROL, (*pState).wStatus, $
          SET_VALUE = 'Custom kernel will be used as entered.'
      ENDELSE
    END

    ; ---------------- Built-in CONVOL toggle ----------------
    'FAST': BEGIN
      WIDGET_CONTROL, ev.id, GET_VALUE = fv2
      IF (N_ELEMENTS(fv2) GT 0) AND (fv2[0] NE 0) THEN BEGIN
        WIDGET_CONTROL, (*pState).wStatus, $
          SET_VALUE = 'Built-in CONVOL enabled (faster on large images).'
      ENDIF ELSE BEGIN
        WIDGET_CONTROL, (*pState).wStatus, $
          SET_VALUE = 'Using custom FOR-loop convolution.'
      ENDELSE
    END

    ; ---------------- Exit ----------------
    'EXIT': BEGIN
      IF PTR_VALID((*pState).pOrig) THEN PTR_FREE, (*pState).pOrig
      IF PTR_VALID((*pState).pProc) THEN PTR_FREE, (*pState).pProc
      PTR_FREE, pState
      WIDGET_CONTROL, ev.top, /DESTROY
    END

    ELSE:
  ENDCASE
END

;------------------------------------------------------------------
; MAIN PROCEDURE: RS_CONV_DENOISE
; Build the widget interface and register it with XMANAGER.
;------------------------------------------------------------------
PRO RS_CONV_DENOISE

  wBase = WIDGET_BASE(TITLE = 'Remote Sensing Image Denoising Tool', $
                      /COLUMN, XSIZE = 1030, YSIZE = 720)

  wTitle = WIDGET_LABEL(wBase, /ALIGN_CENTER, $
    VALUE = 'Remote Sensing Image Denoising - 3x3 Convolution / Median Filter')

  ; ---------- Button row ----------
  wBtnRow = WIDGET_BASE(wBase, /ROW)
  wOpen   = WIDGET_BUTTON(wBtnRow, VALUE = 'Open Image',  UVALUE = 'OPEN')
  wProc   = WIDGET_BUTTON(wBtnRow, VALUE = 'Process',     UVALUE = 'PROC')
  wSave   = WIDGET_BUTTON(wBtnRow, VALUE = 'Save Result', UVALUE = 'SAVE')
  wExit   = WIDGET_BUTTON(wBtnRow, VALUE = 'Exit',        UVALUE = 'EXIT')

  ; ---------- Parameter row ----------
  wParam = WIDGET_BASE(wBase, /ROW, FRAME = 1)
  dummy  = WIDGET_LABEL(wParam, VALUE = 'Filter:')
  wCombo = WIDGET_DROPLIST(wParam, UVALUE = 'KERNEL', $
             VALUE = ['Mean filter (3x3)', 'Gaussian smoothing (3x3)', $
                      'Sharpening (3x3)', 'Median filter (3x3)', $
                      'Custom kernel (3x3)'])
  ; In IDL a checkbox is a button inside a /NONEXCLUSIVE base.
  ; WIDGET_BUTTON has no /CHECKBOX keyword.
  wFastBase = WIDGET_BASE(wParam, /ROW, /NONEXCLUSIVE)
  wFast  = WIDGET_BUTTON(wFastBase, VALUE = 'Use built-in CONVOL', $
                         UVALUE = 'FAST')
  dummy  = WIDGET_LABEL(wParam, VALUE = '(unchecked = custom FOR loops)')

  ; ---------- Kernel coefficient display ----------
  dummy = WIDGET_LABEL(wBase, VALUE = 'Current kernel coefficients (by row):')
  dummyK = RS_CD_GET_KERNEL(0, k0Name)
  wKernel = WIDGET_TEXT(wBase, VALUE = RS_CD_KERNEL_TEXT(dummyK), $
                        XSIZE = 42, YSIZE = 3, EDITABLE = 0)

  ; ---------- Custom kernel input (enabled only for filter index 4) ----------
  wCustomRow = WIDGET_BASE(wBase, /ROW, FRAME = 1)
  dummy = WIDGET_LABEL(wCustomRow, $
    VALUE = 'Custom 3x3 kernel (9 numbers, row by row):')
  wCustom = WIDGET_TEXT(wCustomRow, $
    VALUE = ['1 1 1', '1 1 1', '1 1 1'], $
    XSIZE = 20, YSIZE = 3, EDITABLE = 1, SENSITIVE = 0, UVALUE = 'CUSTOM')
  wNormBase = WIDGET_BASE(wCustomRow, /ROW, /NONEXCLUSIVE)
  wNorm = WIDGET_BUTTON(wNormBase, VALUE = 'Normalize by sum', UVALUE = 'NORM')
  dummy = WIDGET_LABEL(wCustomRow, $
    VALUE = 'Example: -1 -1 -1 / -1 9 -1 / -1 -1 -1')

  ; ---------- Two draw areas ----------
  wDisp = WIDGET_BASE(wBase, /ROW, FRAME = 1)

  wLeft = WIDGET_BASE(wDisp, /COLUMN)
  dummy = WIDGET_LABEL(wLeft, VALUE = 'Original image')
  wDrawOrig = WIDGET_DRAW(wLeft, XSIZE = 480, YSIZE = 400, /EXPOSE_EVENTS)

  wRight = WIDGET_BASE(wDisp, /COLUMN)
  dummy = WIDGET_LABEL(wRight, VALUE = 'Processed result')
  wDrawProc = WIDGET_DRAW(wRight, XSIZE = 480, YSIZE = 400, /EXPOSE_EVENTS)

  ; ---------- Info / status ----------
  wInfo = WIDGET_TEXT(wBase, VALUE = 'No image loaded.', $
                      XSIZE = 118, YSIZE = 3, EDITABLE = 0)
  wStatus = WIDGET_LABEL(wBase, $
    VALUE = 'Ready. Click [Open Image] to load a grayscale image.')

  ; ---------- State structure: arrays are held by pointers ----------
  state = { $
    wDrawOrig:wDrawOrig,  wDrawProc:wDrawProc, $
    wCombo:wCombo,        wChkFast:wFast,      wKernel:wKernel, $
    wCustom:wCustom,      wChkNorm:wNorm, $
    wInfo:wInfo,          wStatus:wStatus, $
    pOrig:PTR_NEW(),      pProc:PTR_NEW(), $
    filePath:'',          cols:0L,             rows:0L, $
    filterIdx:0L, $
    minVal:0.0,           maxVal:1.0, $
    hasImg:0B,            hasResult:0B, $
    dispW:480L,           dispH:400L }

  pState = PTR_NEW(state)
  WIDGET_CONTROL, wBase, SET_UVALUE = pState

  WIDGET_CONTROL, wBase, /REALIZE
  XMANAGER, 'RS_CONV_DENOISE', wBase, /NO_BLOCK

  PRINT, 'RS_CONV_DENOISE started.'
END
