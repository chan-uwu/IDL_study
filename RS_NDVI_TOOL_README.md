# RS_NDVI_TOOL 使用说明

## 一、工具简介

基于 IDL Widget 图形界面的多波段遥感影像处理工具，实现：

- 读取多波段 TIF 影像（ENVI/IDL 可读的 TIF 格式）
- 自动获取并显示影像的行数、列数、波段数、数据类型
- 指定单波段提取与灰度显示
- R/G/B 三通道假彩色合成与显示
- NDVI 植被指数计算与伪彩色显示
- 结果保存为 TIFF 或 ENVI 标准格式

源码文件：`D:\Github\IDL\RS_NDVI_TOOL.pro`（纯英文纯 ASCII，入口过程 `RS_NDVI_TOOL`）

## 二、编译与运行

在 IDL 命令行中依次执行：

```
IDL> CD, 'D:\Github\IDL'
IDL> RS_NDVI_TOOL
```

文件名与主过程名一致，IDL 会自动找到并编译，无需手动 `.compile`。
若在 IDL Workbench 中，也可打开文件后点击 Compile，再运行 `RS_NDVI_TOOL`。

注意：每次修改源码后，必须先在 IDL 中重新编译（`.compile` 或 Workbench 的 Compile 按钮），
关掉旧窗口再运行，否则执行的还是内存中的旧版本。

## 三、界面说明

### 按钮

| 按钮 | 功能 |
|---|---|
| Open Image | 打开文件选择对话框，读取多波段 TIF 影像 |
| Show Band | 按输入的波段号提取单波段，线性拉伸为灰度图显示 |
| False Color | 按 R/G/B 三个波段号合成 24 位假彩色影像并显示 |
| Compute NDVI | 按近红外与红波段计算 NDVI，伪彩色显示 |
| Save Result | 将当前结果（假彩色或 NDVI）保存为文件 |
| Exit | 退出程序 |

### 输入项

| 输入 | 含义 | 默认值 |
|---|---|---|
| Show band | 单波段显示的波段号 | 1 |
| R / G / B | 假彩色合成的红、绿、蓝通道波段号 | 3 / 2 / 1 |
| NIR / Red | NDVI 的近红外波段与红波段 | 4 / 3 |
| Save format | 保存格式下拉框：TIFF (*.tif) 或 ENVI (*.dat) | TIFF |

波段号从 1 开始，有效范围为 1 ~ 波段数。打开影像后程序会填入常见默认值，可直接在输入框中修改。

### 信息区与显示区

- Image information：显示文件路径、行数、列数、波段数、数据类型。
- Image display：图像显示区，超过 900×650 的影像会等比缩小显示（保存时仍用原始分辨率）。
- 底部状态栏：显示当前操作结果提示。

## 四、操作步骤

1. 点击 **Open Image**，选择一个多波段 TIF 文件。信息区会显示行列数、波段数、数据类型，
   显示区默认展示第 1 波段。
2. （可选）修改 Show band 的数字，点击 **Show Band** 查看任意单波段。
3. 修改 R / G / B 三个波段号，点击 **False Color** 生成假彩色合成图。
   常用组合：Landsat 8 的 4/3/2（真彩色）或 5/4/3（标准假彩色）。
4. 修改 NIR / Red 两个波段号，点击 **Compute NDVI** 计算并显示植被指数。
5. 在 Save format 中选择 TIFF 或 ENVI，点击 **Save Result**，
   在弹出的文件对话框中选择路径，即可写出结果。

## 五、算法说明

### 假彩色合成

对每个指定波段独立做线性拉伸：

```
out = (d - MIN) * 255 / (MAX - MIN)
```

结果截断到 [0,255] 并转为 BYTE 类型，三个通道组合成 `[3, 列, 行]` 的 24 位真彩色图像。
常量图像（MAX == MIN）统一赋 128；NaN/Inf 像元置 0。

### NDVI

```
NDVI = (NIR - Red) / (NIR + Red)
```

- 分母为 0 或无效（NaN/Inf）的像元，结果设为 NaN，显示时置为黑色，不参与拉伸。
- 有效结果裁剪到 [-1, 1] 后线性映射到 0~255，再经伪彩色色表显示。
- 保存时写出原始浮点 NDVI 值，不是显示用的拉伸结果。

## 六、结果保存

| 格式 | 假彩色结果 | NDVI 结果 |
|---|---|---|
| TIFF (*.tif) | 3 波段 24 位 BYTE TIFF | 单波段 FLOAT TIFF |
| ENVI (*.dat) | 3 波段 BYTE + 同名 .hdr | 单波段 FLOAT + 同名 .hdr |

保存前会弹出文件对话框。若输入的文件名不带扩展名，程序会自动补上 `.tif` 或 `.dat`。

## 七、常见问题

1. **IDL 报 `Expression must be a scalar`：结构字段维度固定，不能存数组。**
   本版本已用指针（PTR_NEW）保存 img / result / dispData，不会再出现。

2. **保存时报 `BYTE Array[2]` 错误：**
   本版本已兼容 `WIDGET_DROPLIST` 的两种 `GET_VALUE` 返回形态（状态数组 / 标量索引）。

3. **界面文字乱码或"锟斤拷"：**
   本版本为纯 ASCII 英文源码，不涉及编码问题。若自行修改源码加入中文，
   请务必保存为 GBK/ANSI 编码，否则 IDL 在中文 Windows 下会按本地代码页误读。

4. **参数框不能输入：**
   本版本所有参数输入框已显式设置 `EDITABLE = 1`。

5. **点击 Save Result 提示先生成结果：**
   需先执行 False Color 或 Compute NDVI，再保存。
