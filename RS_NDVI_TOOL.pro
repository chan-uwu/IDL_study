;+
;===========================================================================
; File    : RS_NDVI_TOOL.pro
; Purpose : IDL Widget GUI tool for multispectral TIF imagery:
;           band display, false-color composite and NDVI calculation.
; Env     : IDL 8.x or later (READ_TIFF / WRITE_TIFF built in).
;
; USAGE
;   The file name matches the main procedure name, so IDL finds it
;   automatically. At the IDL prompt:
;     IDL> CD, 'D:\Github\IDL'
;     IDL> RS_NDVI_TOOL
;
;   Steps:
;     (1) [Open Image]   - select a multi-band TIF file.
;     (2) [Show Band]    - enter a band number, view stretched gray image.
;     (3) [False Color]  - enter R/G/B band numbers, view 24-bit composite.
;     (4) [Compute NDVI] - enter NIR and Red bands, view pseudo-color NDVI.
;     (5) [Save Result]  - pick TIFF or ENVI format, choose output path.
;
; NOTES
;   - This source is pure ASCII on purpose: no encoding issues in IDL.
;   - Arrays are held by POINTERS in the widget state, because IDL
;     structure fields have fixed dimensions at creation time.
;   - NDVI pixels with zero/invalid denominator are set to NaN and shown
;     in black; only finite values take part in display stretching.
;===========================================================================
;-

;------------------------------------------------------------------
; FUNCTION: RS_READ_TIF
; Read a multi-band TIF and normalize it to [cols, rows, bands].
; Arguments:
;   inFile  - input,  image file path (string)
;   data    - output, normalized image data [cols, rows, bands]
;   cols    - output, number of columns
;   rows    - output, number of rows
;   nbands  - output, number of bands
;   dtype   - output, type name (BYTE / UINT / FLOAT ...)
; Returns: 1 = success, 0 = failure (message box shown).
;------------------------------------------------------------------
FUNCTION RS_READ_TIF, inFile, data, cols, rows, nbands, dtype
  data = 0
  cols = 0L & rows = 0L & nbands = 0L & dtype = ''

  IF (STRTRIM(inFile, 2) EQ '') THEN RETURN, 0
  IF (~FILE_TEST(inFile, /READ)) THEN BEGIN
    void = DIALOG_MESSAGE('File not found or not readable: ' + inFile, /ERROR)
    RETURN, 0
  ENDIF

  err = 0
  CATCH, err
  IF err EQ 0 THEN raw = READ_TIFF(inFile)
  IF err NE 0 THEN BEGIN
    msg = !ERROR_STATE.MSG
    CATCH, /CANCEL
    void = DIALOG_MESSAGE('Failed to read TIF: ' + msg, /ERROR)
    RETURN, 0
  ENDIF
  CATCH, /CANCEL

  sz = SIZE(raw, /DIMENSIONS)
  nd = N_ELEMENTS(sz)

  CASE nd OF
    2: BEGIN
      ; Single band: already [cols, rows]
      cols = sz[0] & rows = sz[1] & nbands = 1L
      data = raw
    END
    3: BEGIN
      ; Multi-band: the shortest dimension is taken as the band axis,
      ; then the array is reordered to [cols, rows, bands].
      junk = MIN(sz, bandDim)
      CASE bandDim OF
        0: BEGIN
          data = TRANSPOSE(raw, [1, 2, 0])   ; was [bands, cols, rows]
          cols = sz[1] & rows = sz[2] & nbands = sz[0]
        END
        1: BEGIN
          data = TRANSPOSE(raw, [0, 2, 1])   ; was [cols, bands, rows]
          cols = sz[0] & rows = sz[2] & nbands = sz[1]
        END
        2: BEGIN
          data = raw                         ; was [cols, rows, bands]
          cols = sz[0] & rows = sz[1] & nbands = sz[2]
        END
      ENDCASE
    END
    ELSE: BEGIN
      void = DIALOG_MESSAGE('Unsupported image dimensions (need 2D or 3D).', /ERROR)
      RETURN, 0
    END
  ENDCASE

  sInfo = SIZE(data, /STRUCTURE)
  dtype = sInfo.TYPENAME

  RETURN, 1
END

;------------------------------------------------------------------
; FUNCTION: RS_GET_BAND
; Extract one band as a 2-D array from [cols, rows, bands] data.
;   data   - input, image data
;   bandNo - input, band number (1-based)
;------------------------------------------------------------------
FUNCTION RS_GET_BAND, data, bandNo
  sz = SIZE(data, /DIMENSIONS)
  IF (N_ELEMENTS(sz) EQ 2) THEN RETURN, data
  RETURN, REFORM(data[*, *, bandNo - 1])
END

;------------------------------------------------------------------
; FUNCTION: RS_STRETCH_BYTE
; Linear stretch of any numeric band to BYTE 0..255.
;   out = (d - MIN) * 255 / (MAX - MIN), clipped to [0,255]
;   constant image -> 128 ; NaN/Inf pixels -> 0
;------------------------------------------------------------------
FUNCTION RS_STRETCH_BYTE, inData
  dims = SIZE(inData, /DIMENSIONS)
  d = FLOAT(inData)
  out = BYTARR(dims)

  good = WHERE(FINITE(d), cnt)
  IF cnt EQ 0 THEN RETURN, out

  mn = MIN(d[good], MAX = mx)
  IF (mx EQ mn) THEN BEGIN
    out[good] = 128
    RETURN, out
  ENDIF

  res = (d - mn) * 255.0 / (mx - mn)
  res = res > 0.0 < 255.0
  out = BYTE(res)

  bad = WHERE(FINITE(d) EQ 0, bc)
  IF bc GT 0 THEN out[bad] = 0

  RETURN, out
END

;------------------------------------------------------------------
; FUNCTION: RS_HAS_IMAGE
; Check that an image has been loaded successfully.
;------------------------------------------------------------------
FUNCTION RS_HAS_IMAGE, pState
  IF (PTR_VALID(pState) EQ 0) THEN RETURN, 0
  IF ((*pState).rows GT 0 AND (*pState).cols GT 0) THEN RETURN, 1
  RETURN, 0
END

;------------------------------------------------------------------
; FUNCTION: RS_GET_INT
; Safely read an integer from a WIDGET_TEXT; return -1 if invalid.
;------------------------------------------------------------------
FUNCTION RS_GET_INT, textWidget
  WIDGET_CONTROL, textWidget, GET_VALUE = txt
  v = -1L
  err = 0
  CATCH, err
  IF err EQ 0 THEN v = FIX(STRTRIM(txt[0], 2))
  IF err NE 0 THEN BEGIN
    CATCH, /CANCEL
    RETURN, -1L
  ENDIF
  CATCH, /CANCEL
  RETURN, v
END

;------------------------------------------------------------------
; FUNCTION: RS_VALID_BAND
; Check band number is within 1..nbands.
;------------------------------------------------------------------
FUNCTION RS_VALID_BAND, pState, bandNo, bandName
  IF (bandNo LT 1) OR (bandNo GT (*pState).nbands) THEN BEGIN
    void = DIALOG_MESSAGE(bandName + ' band number out of range. Valid: 1 ~ ' + $
      STRTRIM(STRING((*pState).nbands), 2) + '.', /ERROR)
    RETURN, 0
  ENDIF
  RETURN, 1
END

;------------------------------------------------------------------
; PROCEDURE: RS_DISPLAY
; Draw a 2-D gray image or a [3,cols,rows] RGB image in WIDGET_DRAW.
;   pState - state pointer
;   inData - BYTE array, 2-D (gray) or [3,cols,rows] (RGB)
;   /RGB   - keyword, input is three-channel color data
; Large images are scaled down to at most 900x650 for display only;
; full-resolution data is kept for saving.
;------------------------------------------------------------------
PRO RS_DISPLAY, pState, inData, RGB = rgb
  IF PTR_VALID(pState) EQ 0 THEN RETURN

  sz = SIZE(inData, /DIMENSIONS)
  IF KEYWORD_SET(rgb) THEN BEGIN
    cols = sz[1] & rows = sz[2]
  ENDIF ELSE BEGIN
    cols = sz[0] & rows = sz[1]
  ENDELSE
  IF (cols LT 1) OR (rows LT 1) THEN RETURN

  maxX = 900 & maxY = 650
  sc = 1.0
  IF (cols GT maxX) OR (rows GT maxY) THEN $
    sc = MIN([FLOAT(maxX) / cols, FLOAT(maxY) / rows])
  dx = ((FIX(cols * sc) > 1) < maxX)
  dy = ((FIX(rows * sc) > 1) < maxY)

  WIDGET_CONTROL, (*pState).wDraw, DRAW_XSIZE = dx, DRAW_YSIZE = dy
  WIDGET_CONTROL, (*pState).wDraw, GET_VALUE = winID
  WSET, winID
  DEVICE, DECOMPOSED = 1

  IF KEYWORD_SET(rgb) THEN BEGIN
    IF (dx EQ cols) AND (dy EQ rows) THEN BEGIN
      disp = inData
    ENDIF ELSE BEGIN
      disp = BYTARR(3, dx, dy)
      FOR c = 0, 2 DO disp[c, *, *] = CONGRID(REFORM(inData[c, *, *]), dx, dy)
    ENDELSE
  ENDIF ELSE BEGIN
    ; Replicate gray to three channels to avoid color-table effects
    g = inData
    IF (dx NE cols) OR (dy NE rows) THEN g = CONGRID(g, dx, dy)
    disp = BYTARR(3, dx, dy)
    disp[0, *, *] = g & disp[1, *, *] = g & disp[2, *, *] = g
  ENDELSE

  ; READ_TIFF rows run top-to-bottom; ORDER=1 keeps correct orientation
  TV, disp, TRUE = 1, ORDER = 1

  ; Cache displayed image for DRAW expose events (stored via pointer)
  IF PTR_VALID((*pState).dispData) THEN PTR_FREE, (*pState).dispData
  (*pState).dispData = PTR_NEW(disp)
END

;------------------------------------------------------------------
; PROCEDURE: RS_UPDATE_INFO
; Refresh the information text area (path, rows, cols, bands, type).
;------------------------------------------------------------------
PRO RS_UPDATE_INFO, pState
  IF ((*pState).filePath EQ '') THEN BEGIN
    txt = ['No image loaded.', $
           'Click [Open Image] to select a multi-band TIF file.']
  ENDIF ELSE BEGIN
    txt = ['File: ' + (*pState).filePath, $
           'Rows: ' + STRTRIM(STRING((*pState).rows), 2) + $
           '    Cols: ' + STRTRIM(STRING((*pState).cols), 2), $
           'Bands: ' + STRTRIM(STRING((*pState).nbands), 2) + $
           '    Data type: ' + (*pState).dtype, $
           'Valid band numbers: 1 ~ ' + STRTRIM(STRING((*pState).nbands), 2)]
  ENDELSE
  WIDGET_CONTROL, (*pState).wInfo, SET_VALUE = txt
END

;------------------------------------------------------------------
; FUNCTION: RS_HAS_ROUTINE
; Test whether a procedure/function exists in the current IDL session.
;------------------------------------------------------------------
FUNCTION RS_HAS_ROUTINE, name
  r = 0
  err = 0
  CATCH, err
  IF err EQ 0 THEN r = ROUTINE_INFO(name)
  ok = (SIZE(r, /TNAME) EQ 'STRUCT')
  IF err NE 0 THEN ok = 0
  CATCH, /CANCEL
  RETURN, ok
END

;------------------------------------------------------------------
; FUNCTION: RS_SAVE_RESULT
; Write current result to disk.
;   pState  - state pointer; result field holds a POINTER to the array
;   fmtIdx  - 0 = TIFF (*.tif), 1 = ENVI (*.dat + *.hdr)
;   outFile - output path
; Returns: 1 = success, 0 = failure (message box shown).
;   WRITE_TIFF writes [3,cols,rows] BYTE as a 24-bit TIFF;
;   second positional argument Order=1 means top-to-bottom rows.
;   ENVI output prefers WRITE_ENVI, otherwise falls back to the
;   standard ENVI_WRITE_ENVI_FILE (BSQ [cols,rows,bands]).
;------------------------------------------------------------------
FUNCTION RS_SAVE_RESULT, pState, fmtIdx, outFile
  res = *((*pState).result)
  dims = SIZE(res, /DIMENSIONS)
  isRGB = (*pState).resultRGB
  cols = dims[0]
  rows = dims[1]

  ; Probe the interface BEFORE the main CATCH (probe uses CATCH itself)
  hasSimpleEnvi = RS_HAS_ROUTINE('WRITE_ENVI')

  err = 0
  CATCH, err
  IF err EQ 0 THEN BEGIN
    IF fmtIdx EQ 0 THEN BEGIN
      ; TIFF: false color = 3-band BYTE, NDVI = single-band FLOAT
      WRITE_TIFF, outFile, res, 1
    ENDIF ELSE BEGIN
      IF isRGB THEN BEGIN
        enviData = TRANSPOSE(res, [1, 2, 0])   ; to BSQ [cols,rows,bands]
        nb = 3
      ENDIF ELSE BEGIN
        enviData = res
        nb = 1
      ENDELSE
      IF hasSimpleEnvi THEN BEGIN
        WRITE_ENVI, outFile, enviData
      ENDIF ELSE BEGIN
        ENVI_WRITE_ENVI_FILE, enviData, OUT_NAME = outFile, $
          NS = cols, NL = rows, NB = nb, INTERLEAVE = 0, /NO_COPY
      ENDELSE
    ENDELSE
  ENDIF
  IF err NE 0 THEN BEGIN
    msg = !ERROR_STATE.MSG
    CATCH, /CANCEL
    void = DIALOG_MESSAGE('Save failed: ' + msg, /ERROR)
    RETURN, 0
  ENDIF
  CATCH, /CANCEL

  RETURN, 1
END

;------------------------------------------------------------------
; PROCEDURE: RS_NDVI_TOOL_EVENT
; Main event handler: buttons, DRAW expose, window close.
;------------------------------------------------------------------
PRO RS_NDVI_TOOL_EVENT, event
  WIDGET_CONTROL, event.top, GET_UVALUE = pState
  IF N_ELEMENTS(pState) EQ 0 THEN RETURN

  ; --- DRAW expose (type=1) / window kill (type=2) ---
  tn = TAG_NAMES(event)
  hit = WHERE(tn EQ 'TYPE', cnt)
  IF cnt GT 0 THEN BEGIN
    IF event.type EQ 1 THEN BEGIN
      IF PTR_VALID(pState) THEN BEGIN
        IF PTR_VALID((*pState).dispData) THEN BEGIN
          WIDGET_CONTROL, (*pState).wDraw, GET_VALUE = w
          WSET, w & DEVICE, DECOMPOSED = 1 & TV, *((*pState).dispData), TRUE = 1, ORDER = 1
        ENDIF
      ENDIF
    ENDIF
    IF event.type EQ 2 THEN BEGIN
      IF PTR_VALID((*pState).img) THEN PTR_FREE, (*pState).img
      IF PTR_VALID((*pState).result) THEN PTR_FREE, (*pState).result
      IF PTR_VALID((*pState).dispData) THEN PTR_FREE, (*pState).dispData
      PTR_FREE, pState
    ENDIF
    RETURN
  ENDIF

  ; --- Buttons / drop list ---
  WIDGET_CONTROL, event.id, GET_UVALUE = uval
  IF N_ELEMENTS(uval) EQ 0 THEN RETURN

  CASE uval OF

    ; ---------------- Open image ----------------
    'OPEN': BEGIN
      f = DIALOG_PICKFILE(/READ, FILTER = ['*.tif', '*.tiff', '*.TIF', '*.TIFF'], $
                          TITLE = 'Select a multi-band TIF image')
      IF f EQ '' THEN RETURN
      IF RS_READ_TIF(f, data, cols, rows, nb, dtype) THEN BEGIN
        (*pState).filePath = f
        IF PTR_VALID((*pState).img) THEN PTR_FREE, (*pState).img
        (*pState).img      = PTR_NEW(data)
        (*pState).cols     = cols
        (*pState).rows     = rows
        (*pState).nbands   = nb
        (*pState).dtype    = dtype
        (*pState).hasResult = 0B

        ; Common default band numbers; user can change them
        WIDGET_CONTROL, (*pState).wBand, SET_VALUE = '1'
        WIDGET_CONTROL, (*pState).wR,    SET_VALUE = (nb GE 3 ? '3' : '1')
        WIDGET_CONTROL, (*pState).wG,    SET_VALUE = (nb GE 2 ? '2' : '1')
        WIDGET_CONTROL, (*pState).wB,    SET_VALUE = '1'
        WIDGET_CONTROL, (*pState).wNIR,  SET_VALUE = (nb GE 4 ? '4' : '1')
        WIDGET_CONTROL, (*pState).wRed,  SET_VALUE = (nb GE 3 ? '3' : '1')

        RS_UPDATE_INFO, pState
        WIDGET_CONTROL, (*pState).wStatus, $
          SET_VALUE = 'Image opened: ' + STRTRIM(STRING(nb), 2) + ' bands ready.'

        ; Display band 1 by default
        band = RS_GET_BAND(data, 1)
        RS_DISPLAY, pState, RS_STRETCH_BYTE(band)
      ENDIF
    END

    ; ---------------- Show single band ----------------
    'BAND': BEGIN
      IF ~RS_HAS_IMAGE(pState) THEN BEGIN
        void = DIALOG_MESSAGE('Please open an image first.', /INFO)
        RETURN
      ENDIF
      b = RS_GET_INT((*pState).wBand)
      IF ~RS_VALID_BAND(pState, b, 'Band') THEN RETURN

      band = RS_GET_BAND(*((*pState).img), b)
      bByte = RS_STRETCH_BYTE(band)
      RS_DISPLAY, pState, bByte
      (*pState).hasResult = 0B
      WIDGET_CONTROL, (*pState).wStatus, $
        SET_VALUE = 'Showing band ' + STRTRIM(STRING(b), 2) + ' (stretched to 0-255).'
    END

    ; ---------------- False color composite ----------------
    'FCC': BEGIN
      IF ~RS_HAS_IMAGE(pState) THEN BEGIN
        void = DIALOG_MESSAGE('Please open an image first.', /INFO)
        RETURN
      ENDIF
      rB = RS_GET_INT((*pState).wR)
      gB = RS_GET_INT((*pState).wG)
      bB = RS_GET_INT((*pState).wB)
      IF ~RS_VALID_BAND(pState, rB, 'R channel') THEN RETURN
      IF ~RS_VALID_BAND(pState, gB, 'G channel') THEN RETURN
      IF ~RS_VALID_BAND(pState, bB, 'B channel') THEN RETURN

      cols = (*pState).cols & rows = (*pState).rows
      rgb = BYTARR(3, cols, rows)
      ; Each channel is stretched independently to 0..255
      rgb[0, *, *] = RS_STRETCH_BYTE(RS_GET_BAND(*((*pState).img), rB))
      rgb[1, *, *] = RS_STRETCH_BYTE(RS_GET_BAND(*((*pState).img), gB))
      rgb[2, *, *] = RS_STRETCH_BYTE(RS_GET_BAND(*((*pState).img), bB))

      RS_DISPLAY, pState, rgb, /RGB
      IF PTR_VALID((*pState).result) THEN PTR_FREE, (*pState).result
      (*pState).result     = PTR_NEW(rgb)
      (*pState).resultRGB  = 1B
      (*pState).resultName = 'false_color'
      (*pState).hasResult  = 1B
      WIDGET_CONTROL, (*pState).wStatus, $
        SET_VALUE = 'False color ready: R=' + STRTRIM(STRING(rB), 2) + $
                    ' G=' + STRTRIM(STRING(gB), 2) + ' B=' + STRTRIM(STRING(bB), 2) + '.'
    END

    ; ---------------- Compute NDVI ----------------
    'NDVI': BEGIN
      IF ~RS_HAS_IMAGE(pState) THEN BEGIN
        void = DIALOG_MESSAGE('Please open an image first.', /INFO)
        RETURN
      ENDIF
      nirB = RS_GET_INT((*pState).wNIR)
      redB = RS_GET_INT((*pState).wRed)
      IF ~RS_VALID_BAND(pState, nirB, 'NIR') THEN RETURN
      IF ~RS_VALID_BAND(pState, redB, 'Red') THEN RETURN

      cols = (*pState).cols & rows = (*pState).rows
      nir = FLOAT(RS_GET_BAND(*((*pState).img), nirB))
      red = FLOAT(RS_GET_BAND(*((*pState).img), redB))

      ; NDVI = (NIR - Red) / (NIR + Red)
      ; Zero or invalid denominator -> NaN, excluded from display stretching
      den = nir + red
      ndvi = FLTARR(cols, rows) + !VALUES.F_NAN
      valid = WHERE(FINITE(den) AND (den NE 0.0), cnt)
      IF cnt GT 0 THEN ndvi[valid] = (nir[valid] - red[valid]) / den[valid]

      IF PTR_VALID((*pState).result) THEN PTR_FREE, (*pState).result
      (*pState).result     = PTR_NEW(ndvi)
      (*pState).resultRGB  = 0B
      (*pState).resultName = 'ndvi'
      (*pState).hasResult  = 1B

      ; Display: map [-1,1] to 0..255, then apply a pseudo-color table
      idx = BYTARR(cols, rows)
      good = WHERE(FINITE(ndvi), gc)
      IF gc GT 0 THEN BEGIN
        v = ndvi[good] > (-1.0)
        v = v < 1.0
        idx[good] = BYTE((v + 1.0) * 0.5 * 255.0)
      ENDIF

      ; Save and restore the system color table
      TVLCT, oldR, oldG, oldB, /GET
      LOADCT, 3, /SILENT          ; pseudo-color: high values tend to red
      TVLCT, ctR, ctG, ctB, /GET
      TVLCT, oldR, oldG, oldB

      dispRGB = BYTARR(3, cols, rows)
      dispRGB[0, *, *] = ctR[idx]
      dispRGB[1, *, *] = ctG[idx]
      dispRGB[2, *, *] = ctB[idx]
      ; NaN pixels shown in black (per channel to avoid 3-D subscript issues)
      bad = WHERE(FINITE(ndvi) EQ 0, bc)
      IF bc GT 0 THEN BEGIN
        FOR c = 0, 2 DO BEGIN
          plane = dispRGB[c, *, *]
          plane[bad] = 0B
          dispRGB[c, *, *] = plane
        ENDFOR
      ENDIF

      RS_DISPLAY, pState, dispRGB, /RGB
      WIDGET_CONTROL, (*pState).wStatus, $
        SET_VALUE = 'NDVI ready: NIR=' + STRTRIM(STRING(nirB), 2) + $
                    ' Red=' + STRTRIM(STRING(redB), 2) + '; invalid pixels in black.'
    END

    ; ---------------- Save result ----------------
    'SAVE': BEGIN
      IF PTR_VALID(pState) EQ 0 THEN RETURN
      IF ((*pState).hasResult EQ 0) THEN BEGIN
        void = DIALOG_MESSAGE('Run [False Color] or [Compute NDVI] before saving.', /INFO)
        RETURN
      ENDIF

      WIDGET_CONTROL, (*pState).wFmt, GET_VALUE = fmtVal
      ; GET_VALUE returns a BYTE status array in some IDL versions and a
      ; scalar index in others; handle both forms.
      fmtIdx = 0L
      IF N_ELEMENTS(fmtVal) GT 1 THEN BEGIN
        hit = WHERE(fmtVal NE 0, hc)
        IF hc GT 0 THEN fmtIdx = hit[0]
      ENDIF ELSE BEGIN
        fmtIdx = LONG(fmtVal[0])
      ENDELSE
      ext = (fmtIdx EQ 0) ? '.tif' : '.dat'
      outFile = DIALOG_PICKFILE(/WRITE, FILE = (*pState).resultName + ext, $
                                FILTER = '*' + ext, TITLE = 'Choose output path')
      IF outFile EQ '' THEN RETURN
      IF STRMID(outFile, STRLEN(outFile) - STRLEN(ext), STRLEN(ext)) NE ext THEN $
        outFile = outFile + ext

      IF ~RS_SAVE_RESULT(pState, fmtIdx, outFile) THEN RETURN

      void = DIALOG_MESSAGE('Saved: ' + outFile, /INFORMATION)
      WIDGET_CONTROL, (*pState).wStatus, SET_VALUE = 'Saved: ' + outFile
    END

    ; ---------------- Format selection feedback ----------------
    'FMT': BEGIN
      WIDGET_CONTROL, (*pState).wFmt, GET_VALUE = fv
      IF N_ELEMENTS(fv) GT 1 THEN BEGIN
        hit = WHERE(fv NE 0, hc) & iv = (hc GT 0) ? hit[0] : 0
      ENDIF ELSE BEGIN
        iv = LONG(fv[0])
      ENDELSE
      st = (iv EQ 0) ? 'TIFF (*.tif)' : 'ENVI (*.dat)'
      WIDGET_CONTROL, (*pState).wStatus, SET_VALUE = 'Output format: ' + st
    END

    ; ---------------- Exit ----------------
    'EXIT': BEGIN
      IF PTR_VALID((*pState).img) THEN PTR_FREE, (*pState).img
      IF PTR_VALID((*pState).result) THEN PTR_FREE, (*pState).result
      IF PTR_VALID((*pState).dispData) THEN PTR_FREE, (*pState).dispData
      PTR_FREE, pState
      WIDGET_CONTROL, event.top, /DESTROY
    END

    ELSE:
  ENDCASE
END

;------------------------------------------------------------------
; MAIN PROCEDURE: RS_NDVI_TOOL
; Build the widget interface and register it with XMANAGER.
;------------------------------------------------------------------
PRO RS_NDVI_TOOL

  wBase = WIDGET_BASE(TITLE = 'Multispectral Image: False Color and NDVI Tool', $
                      /COLUMN, XSIZE = 940, YSIZE = 760)

  wTitle = WIDGET_LABEL(wBase, VALUE = 'Multispectral TIF Tool - False Color / NDVI', $
                        /ALIGN_CENTER)

  ; ---------- Button row ----------
  wBtnRow = WIDGET_BASE(wBase, /ROW)
  wOpen   = WIDGET_BUTTON(wBtnRow, VALUE = 'Open Image',    UVALUE = 'OPEN')
  wBand   = WIDGET_BUTTON(wBtnRow, VALUE = 'Show Band',     UVALUE = 'BAND')
  wFcc    = WIDGET_BUTTON(wBtnRow, VALUE = 'False Color',   UVALUE = 'FCC')
  wNdvi   = WIDGET_BUTTON(wBtnRow, VALUE = 'Compute NDVI',  UVALUE = 'NDVI')
  wSave   = WIDGET_BUTTON(wBtnRow, VALUE = 'Save Result',   UVALUE = 'SAVE')
  wExit   = WIDGET_BUTTON(wBtnRow, VALUE = 'Exit',          UVALUE = 'EXIT')

  ; ---------- Parameter area ----------
  wParam = WIDGET_BASE(wBase, /COLUMN, FRAME = 1)

  wRow1 = WIDGET_BASE(wParam, /ROW)
  dummy = WIDGET_LABEL(wRow1, VALUE = 'Show band:')
  wTxtBand = WIDGET_TEXT(wRow1, VALUE = '1', XSIZE = 8, EDITABLE = 1)
  dummy = WIDGET_LABEL(wRow1, VALUE = '(1 to number of bands)')

  wRow2 = WIDGET_BASE(wParam, /ROW)
  dummy = WIDGET_LABEL(wRow2, VALUE = 'False color channels:  R=')
  wTxtR = WIDGET_TEXT(wRow2, VALUE = '3', XSIZE = 8, EDITABLE = 1)
  dummy = WIDGET_LABEL(wRow2, VALUE = 'G=')
  wTxtG = WIDGET_TEXT(wRow2, VALUE = '2', XSIZE = 8, EDITABLE = 1)
  dummy = WIDGET_LABEL(wRow2, VALUE = 'B=')
  wTxtB = WIDGET_TEXT(wRow2, VALUE = '1', XSIZE = 8, EDITABLE = 1)
  dummy = WIDGET_LABEL(wRow2, VALUE = '(each channel stretched to 0-255)')

  wRow3 = WIDGET_BASE(wParam, /ROW)
  dummy = WIDGET_LABEL(wRow3, VALUE = 'NDVI bands:  NIR=')
  wTxtNIR = WIDGET_TEXT(wRow3, VALUE = '4', XSIZE = 8, EDITABLE = 1)
  dummy = WIDGET_LABEL(wRow3, VALUE = 'Red=')
  wTxtRed = WIDGET_TEXT(wRow3, VALUE = '3', XSIZE = 8, EDITABLE = 1)
  dummy = WIDGET_LABEL(wRow3, VALUE = '  NDVI=(NIR-Red)/(NIR+Red)')

  wRow4 = WIDGET_BASE(wParam, /ROW)
  dummy = WIDGET_LABEL(wRow4, VALUE = 'Save format:')
  wFmt = WIDGET_DROPLIST(wRow4, VALUE = ['TIFF (*.tif)', 'ENVI (*.dat)'], UVALUE = 'FMT')
  dummy = WIDGET_LABEL(wRow4, VALUE = '(file dialog appears before saving)')

  ; ---------- Information area ----------
  dummy = WIDGET_LABEL(wBase, VALUE = 'Image information:')
  wInfo = WIDGET_TEXT(wBase, VALUE = 'No image loaded.', $
                      XSIZE = 100, YSIZE = 4, EDITABLE = 0)

  ; ---------- Display area ----------
  dummy = WIDGET_LABEL(wBase, VALUE = 'Image display:')
  wDraw = WIDGET_DRAW(wBase, XSIZE = 880, YSIZE = 480, /EXPOSE_EVENTS)

  ; ---------- Status bar ----------
  wStatus = WIDGET_LABEL(wBase, VALUE = 'Ready. Please click [Open Image].')

  ; ---------- State structure (arrays held by pointers) ----------
  state = { $
    wDraw:wDraw,      wInfo:wInfo,      wStatus:wStatus, $
    wBand:wTxtBand,   wR:wTxtR,         wG:wTxtG,         wB:wTxtB, $
    wNIR:wTxtNIR,     wRed:wTxtRed,     wFmt:wFmt, $
    filePath:'',      img:PTR_NEW(),    cols:0L,          rows:0L, $
    nbands:0L,        dtype:'',         hasResult:0B, $
    result:PTR_NEW(), resultRGB:0B,     resultName:'result', $
    dispData:PTR_NEW() }

  pState = PTR_NEW(state)
  WIDGET_CONTROL, wBase, SET_UVALUE = pState

  WIDGET_CONTROL, wBase, /REALIZE
  XMANAGER, 'RS_NDVI_TOOL', wBase, /NO_BLOCK
END
