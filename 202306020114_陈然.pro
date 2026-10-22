PRO Task_ReadWrite_Plot
  COMPILE_OPT IDL2 ; 推荐使用的IDL编译选项

  ; ==========================================
  ; 1. 文件读取：使用 Dialog_pickfile() 获取文件路径
  ; ==========================================
  file_path = DIALOG_PICKFILE(TITLE='请选择 Dgx.dat 文件', FILTER='*.dat')
  
  ; 如果用户点击了取消，则退出程序
  IF (file_path EQ '') THEN BEGIN
    PRINT, '用户取消了文件选择。'
    RETURN
  ENDIF

  PRINT, '正在读取文件: ', file_path

  ; 打开文件获取逻辑单元号(LUN)
  OPENR, lun, file_path, /GET_LUN

  ; ==========================================
  ; 2. 数据存储：数组
  ; ==========================================
  ; 定义动态数组用于存储所有数据 (先初始化为空数组)
  arr_x = [] 
  arr_y = []
  arr_z = []
  
  ; 定义临时变量用于暂存每一行读取的四个数值
  id_val = 0.0
  x_val = 0.0
  y_val = 0.0
  z_val = 0.0

  ; 使用 WHILE 循环和 EOF() 函数判断文件是否读取完毕
  WHILE ~EOF(lun) DO BEGIN
    ; 针对您截图中 "序号,数值,数值,数值" 的格式
    ; 在IDL中，READF 可以自动跳过逗号分隔符
    READF, lun, id_val, x_val, y_val, z_val
    
    ; 将提取出的数据追加到动态数组中 (符合提示中“数组”的要求)
    arr_x = [arr_x, x_val]
    arr_y = [arr_y, y_val]
    arr_z = [arr_z, z_val]
  ENDWHILE

  ; 关闭文件并释放逻辑单元号 (非常重要，否则文件会被锁定)
  FREE_LUN, lun

  ; ==========================================
  ; 3. 数据运算 (根据自己的兴趣选择)
  ; ==========================================
  ; 这里提取读取到的有效数据量，并计算 Z 值的均值作为示例运算
  num_points = N_ELEMENTS(arr_x)
  IF num_points GT 0 THEN BEGIN
    mean_z = MEAN(arr_z)
    PRINT, '----------------------------------------'
    PRINT, '数据读取完成，共计读取: ', num_points, ' 个点。'
    PRINT, 'Z 列数据的平均值为: ', mean_z
    PRINT, '----------------------------------------'
  ENDIF ELSE BEGIN
    PRINT, '未读取到有效数据，请检查文件格式。'
    RETURN
  ENDELSE

  ; ==========================================
  ; 4. 显示绘制：plot 和 scatterplot()
  ; ==========================================
  ; 初始化图形窗口
  WINDOW, 0, TITLE='Scatter Plot - ' + FILE_BASENAME(file_path), XSIZE=600, YSIZE=500

  ; 使用 SCATTERPLOT 绘制散点图 (对应您作业截图右下角的样式)
  ; 假设我们观察 X 和 Y 的关系
  my_plot = SCATTERPLOT(arr_x, arr_y, $
    TITLE='Dgx Data Scatter Plot', $
    XTITLE='X Value', $
    YTITLE='Y Value', $
    SYMBOL='o', $          ; 设置散点符号为圆形
    SYM_SIZE=0.8, $        ; 符号大小
    SYM_COLOR='blue', $    ; 符号颜色为蓝色
    /SYM_FILLED, $         ; 符号内部填充
    AXIS_STYLE=1)          ; 显示完整的方框坐标轴

  ; 如果想用最基础的 PLOT 命令（提示中提到了plot），可以将上面注释掉，使用下面这行：
  ; PLOT, arr_x, arr_y, PSYM=4, TITLE='Dgx Data Plot', XTITLE='X Value', YTITLE='Y Value', COLOR=0

END