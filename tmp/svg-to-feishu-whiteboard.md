---
name: svg-to-feishu-whiteboard
description: "draw.io SVG 导入飞书画板的文字显示问题解决方案"
---

# draw.io SVG 导入飞书画板的文字显示问题

## 问题现象

从 draw.io 导出的 SVG 插入飞书画板后：
- **泳道框架、矩形框等图形**：正常显示（因为用的是 `<rect>`/`<path>` 等标准 SVG 元素）
- **文字内容**：不显示或只显示截断的 fallback 文字

## 根本原因

draw.io 导出的 SVG 使用 `<foreignObject>` + HTML `<div>` 来渲染多行文字：

```xml
<foreignObject pointer-events="none" width="100%" height="100%">
  <div xmlns="http://www.w3.org/1999/xhtml" style="...">
    多行文字内容...
  </div>
</foreignObject>
<text>截断的fallback文字...</text>
```

飞书画板的 SVG 渲染器**不支持 `<foreignObject>`**，只支持标准 SVG 元素：
- `<text>` — 文字
- `<rect>` — 矩形
- `<path>` — 路径/线条
- `<polygon>` — 多边形/箭头

## 解决方案

### 方法一：手动转换 SVG（推荐，适用于简单图）

把 `<foreignObject>` 内容拆成多个 `<text>` 元素：

```xml
<!-- 原始 draw.io 格式（不工作） -->
<foreignObject>
  <div>
    第一行文字<br/>
    第二行文字
  </div>
</foreignObject>

<!-- 转换后的飞书支持格式 -->
<text x="起点X" y="第一行Y">第一行文字</text>
<text x="起点X" y="第二行Y">第二行文字</text>
```

转换要点：
1. 每个 `<text>` 需要明确的 `x` 和 `y` 坐标
2. 多行文字用多个 `<text>`，每行 `y` 递增约 18px（12px 字号 + 行距）
3. 使用 `<style>` 定义字体样式，避免每个 `<text>` 重复写属性

### 方法二：draw.io 导出设置

在 draw.io 导出 SVG 时：
1. File → Export as → SVG
2. 勾选 "Embed Fonts" 或尝试不同导出选项
3. 部分设置可以让文字用 `<text>` 渲染，但复杂多行内容仍可能用 `<foreignObject>`

### 方法三：用飞书画板 DSL/Mermaid 重绘

对于复杂图（泳道图、架构图），推荐用飞书原生工具重绘：
- **Mermaid**：流程图、时序图、类图、饼图等
- **whiteboard-cli DSL**：泳道图、架构图、组织架构图等复杂图表

## 飞书文档插入 SVG 画板

### 插入方式

```xml
<whiteboard type="svg">
  <svg xmlns="http://www.w3.org/2000/svg" viewBox="...">
    <!-- 完整自包含 SVG 内容 -->
  </svg>
</whiteboard>
```

关键点：
1. SVG 必须**完整自包含**：包含 `<svg>` 根节点和 `viewBox`
2. **不能引用外部资源**：无外部图片、脚本、远程 URL
3. 文字用 `<text>`，不用 `<foreignObject>`

### 命令示例

```bash
# 插入新画板
SVG_CONTENT=$(cat flow.svg)
lark-cli docs +update --api-version v2 --doc "文档URL" \
  --command append \
  --content "<whiteboard type=\"svg\">${SVG_CONTENT}</whiteboard>"

# 替换已有画板
lark-cli docs +update --api-version v2 --doc "文档URL" \
  --command block_replace \
  --block-id "画板block_id" \
  --content "<whiteboard type=\"svg\">${SVG_CONTENT}</whiteboard>"
```

## 快速判断 SVG 是否兼容飞书

检查 SVG 是否包含以下不支持元素：

| 元素 | 飞书支持 | 说明 |
|------|---------|------|
| `<foreignObject>` | ❌ 不支持 | HTML 嵌入，draw.io 多行文字用这个 |
| `<iframe>` | ❌ 不支持 | 外部嵌入 |
| `<script>` | ❌ 不支持 | JavaScript |
| `<text>` | ✅ 支持 | 标准文字 |
| `<rect>` | ✅ 支持 | 矩形 |
| `<path>` | ✅ 支持 | 路径 |
| `<line>` | ✅ 支持 | 线条 |
| `<polygon>` | ✅ 支持 | 多边形 |
| `<circle>` | ✅ 支持 | 圆形 |
| `<ellipse>` | ✅ 支持 | 椭圆 |
| `<image>` | ✅ 支持 | 内嵌图片（需 base64） |

检查命令：
```bash
grep -E "<foreignObject|<iframe|<script" flow.svg
```

如果有输出，说明 SVG 不兼容飞书，需要转换。

## 关键转换要点（draw.io 特有结构）

draw.io 的 foreignObject 结构有特殊陷阱：

### 1. 两层 font-size 嵌套
```xml
<div style="font-size: 0px">           <!-- 外层：0px，用于布局 -->
  <div style="display: inline-block; font-size: 12px">  <!-- 内层：实际字号 -->
    文字内容
  </div>
</div>
```
**必须从 `display:inline-block` 的 div 提取 font-size**，否则文字会以 0px 渲染（不显示）。

### 2. 必须移除 `<switch>` 元素
draw.io 用 `<switch>` 包装 foreignObject 作为兼容降级方案：
```xml
<switch>
  <foreignObject>...</foreignObject>
  <text>截断文字...</text>
</switch>
```
飞书不支持 `<switch>`，必须**彻底移除**，只保留转换后的 `<text>`。

### 3. 文字提取有两种格式
draw.io 在 inline-block div 内使用两种文字格式：

**格式 A：`<div>...</div>` 包裹（多行文字）**
```xml
<div style="display: inline-block">
  <div>self.build_env()</div>
  <div>self.get_git_version()</div>
  ...
</div>
```

**格式 B：`<br />` 换行（单块多行）**
```xml
<div style="display: inline-block">
  git describe --tags<br />获取git 信息
</div>
```

转换脚本必须**同时支持这两种格式**：
```python
def extract_lines(inner_content):
    lines = []
    # 方法 1: <div>...</div> 格式
    for div_match in re.finditer(r'<div>(.*?)</div>', inner_content):
        lines.append(div_match.group(1).strip())
    
    # 方法 2: <br /> 换行格式
    if not lines and '<br' in inner_content:
        parts = re.split(r'<br\s*/>', inner_content)
        lines = [p.strip() for p in parts if p.strip()]
    
    return lines
```

### 4. inline-block div 的嵌套结构
由于 inline-block div 内部可能嵌套多层 `<div>...</div>`，简单正则 `(.*?)</div>` 只会匹配第一个结束标签，**必须用栈匹配完整结构**：
```python
def find_complete_div(content, start_idx):
    depth = 1
    i = start_idx
    while i < len(content) and depth > 0:
        if content[i:i+4] == '<div':
            depth += 1
            i = content.find('>', i+4) + 1
        elif content[i:i+5] == '</div':
            depth -= 1
            i = content.find('>', i+5) + 1
        else:
            i += 1
    return i if depth == 0 else -1
```

### 5. 坐标计算：margin-left 不是中心点
draw.io 的 flexbox 布局中：
- `margin-left`：文字区域的**左边界**
- `width`：框的宽度

正确的文字中心 x 坐标应该是：
```python
x_center = margin_left + width / 2
```

如果直接用 `margin-left` 作为 `text-anchor="middle"` 的 x 坐标，文字会偏左，不在框内居中。

### 6. 大文件插入方式
SVG 文件超过 100KB 时，命令行参数会超限（`Argument list too long`）：
```bash
# ❌ 错误：参数太长
lark-cli docs +update ... --content "<whiteboard type=\"svg\">${SVG}</whiteboard>"

# ✅ 正确：使用文件方式（相对路径）
cp svg_content.xml ./
lark-cli docs +update --api-version v2 --doc "URL" \
  --command block_replace \
  --block-id "xxx" \
  --content @svg_content.xml
```

## 转换脚本示例

```python
# 核心转换逻辑
import re, html

def convert_foreign_object(fo_content):
    # 1. 从 inline-block div 提取正确的 font-size
    inline_div = re.search(r'<div[^>]*display:\s*inline-block[^>]*>', fo_content)
    if inline_div:
        font_match = re.search(r'font-size:\s*(\d+)px', inline_div.group(0))
        font_size = int(font_match.group(1)) if font_match else 12
    
    # 2. 提取多行文字
    lines = re.findall(r'<div[^>]*>(.*?)</div>', inner_content)
    
    # 3. 生成 text 元素（每行一个）
    text_elements = []
    for i, line in enumerate(lines):
        y = y_base + i * font_size * 1.2
        text_el = f'<text x="{x}" y="{y}" font-size="{font_size}px">{html.escape(line)}</text>'
        text_elements.append(text_el)
    
    return '\n'.join(text_elements)

# 4. 移除 switch 和 foreignObject
svg = re.sub(r'<switch>', '', svg)
svg = re.sub(r'</switch>', '', svg)
svg = re.sub(r'<foreignObject[^>]*>.*?</foreignObject>', '', svg, flags=re.DOTALL)
```

## 本次案例总结

原始流程图（4450x4518 px，46 个 foreignObject）：
1. **问题**：draw.io 导出的 SVG 文字用 foreignObject + switch，飞书不支持
2. **陷阱**：外层 font-size=0px，导致转换后文字不显示
3. **解决**：
   - 从 `display:inline-block` div 提取正确的 font-size (12px)
   - 彻底移除 `<switch>` 元素
   - 使用相对路径文件方式插入大 SVG
4. **结果**：成功显示完整流程图，所有多行文字正确渲染

转换后的 SVG 结构：
```xml
<svg viewBox="-0.5 -0.5 4450 4518">
  <!-- 泳道框架 -->
  <rect x="367" y="1140" width="4070" height="750"/>
  
  <!-- 泳道标题（原有 text，无需转换） -->
  <text x="356.5" y="1519.5">DetRunner</text>
  
  <!-- 转换后的多行文字 -->
  <text x="528.0" y="1387.2" font-size="12px">self.build_env()</text>
  <text x="528.0" y="1401.6" font-size="12px">self.get_git_version()</text>
  <text x="528.0" y="1416.0" font-size="12px">self.build_dataloaders()</text>
  <!-- ... 更多行 -->
</svg>
```

## 参考文档

- [飞书画板 SVG 支持规范](https://open.feishu.cn/document/ukTMukTMukTM/uUDN04SN0QjL1QDN)
- [lark-whiteboard skill](../.claude/skills/lark-whiteboard/SKILL.md)
- [lark-doc skill](../.claude/skills/lark-doc/SKILL.md)
- 转换脚本：`/data/caidanfeng/tmp/convert_svg_v2.py`