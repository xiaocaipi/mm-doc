# TSFD聚类档案分析方法

本文档介绍如何分析TSFD聚类系统中的档案数据，判断聚类类型和延迟原因。

## 目录

- [快速使用](#快速使用)
- [分析流程](#分析流程)
- [数据表说明](#数据表说明)
- [调试脚本](#调试脚本)
- [Job类型说明](#job类型说明)
- [常见问题](#常见问题)

---

## 快速使用

用户只需提供档案ID或轨迹ID：
- "分析档案7442"
- "帮我分析8092这个轨迹"
- "查看档案1234的聚类时间线"

---

## 分析流程

### 第一步：确认ID类型

首先判断用户提供的ID是档案ID还是轨迹ID：

```bash
ssh -p54337 root@10.4.196.74 "python3 /code/pyutils/mm/query_cluster.py <ID>"
ssh -p54337 root@10.4.196.74 "python3 /code/pyutils/mm/query_feature.py <ID>"
```

判断规则：
- 如果`query_cluster.py`返回数据 → 档案ID
- 如果`query_feature.py`返回数据 → 轨迹ID

---

### 第二步：查询档案详情

```bash
ssh -p54337 root@10.4.196.74 "python3 /code/pyutils/mm/query_cluster.py <cluster_id>"
```

获取信息：
- cluster_id（档案ID）
- created_at / modified_at（UTC时间）
- feature_ids（轨迹列表）
- preview_image_list（包含入库日期）

---

### 第三步：解析轨迹入库日期

从preview_image_list提取入库日期：

```bash
ssh -p54337 root@10.4.196.74 'python3 << "PYEOF"
import pandas as pd
import glob
import re

cluster_id = <cluster_id>
files = glob.glob("/data/batch-manager/ns-default/face_25400/clusters/**/*.parquet", recursive=True)
files = [f for f in files if "_delta_log" not in f]

for f in files:
    df = pd.read_parquet(f)
    if "cluster_id" in df.columns:
        row = df[df["cluster_id"] == cluster_id]
        if len(row) > 0:
            preview = row["preview_image_list"].values[0]
            for i, p in enumerate(preview):
                url = p["url"]
                date_match = re.search(r"feature/([0-9]+)/", url)
                date = date_match.group(1) if date_match else "unknown"
                print("轨迹" + str(i+1) + "入库日期: " + date)
            break
PYEOF'
```

---

### 第四步：判断聚类类型

**关键判断逻辑**：

| 条件 | 聚类类型 |
|------|---------|
| 轨迹入库日期跨度大于1天，且档案创建时间晚于最新轨迹1天以上 | **孤立点聚类** |
| 轨迹入库日期等于档案创建时间前一天，延迟几小时 | **实时聚类** |
| 查merged_clusters表有记录，source_cluster_ids > 50000000000 | **合并档案** |

**孤立点聚类特征**：
- 轨迹分散在多天（如04/20, 04/23, 05/08, 05/12）
- 档案创建时间比最早轨迹晚很多天
- 查`isolated_features`表能找到这些轨迹

**实时聚类特征**：
- 轨迹集中在同一天
- ClassificationJob每小时处理
- 档案创建时间比轨迹入库晚几小时

**合并档案特征**：
- 由多个实时档案合并而来
- 源档案ID > 50000000000（实时档案）
- 合并后转换为普通档案ID
- 查`merged_clusters`表获取合并来源

---

### 第五步：检查是否合并档案（重要）

**合并档案查询方法**：

先查merged_clusters表，判断是否是合并档案：

```bash
ssh -p54337 root@10.4.196.74 'python3 << "PYEOF"
import pandas as pd
import glob

cluster_id = <cluster_id>

merge_dir = "/data/batch-manager/ns-default/face_25400/merged_clusters"
files = glob.glob(merge_dir + "/**/*.parquet", recursive=True)
files = [f for f in files if "_delta_log" not in f]

for f in files:
    df = pd.read_parquet(f)
    rows = df[df["target_cluster_id"] == cluster_id]
    if len(rows) > 0:
        row = rows.iloc[0]
        print("target_cluster_id: " + str(row["target_cluster_id"]))
        print("source_cluster_ids: " + str(row["source_cluster_ids"]))
        print("created_at: " + str(row["created_at"]))
        
        # 判断是否实时档案合并
        source_ids = row["source_cluster_ids"]
        if len(source_ids) > 0 and source_ids[0] > 50000000000:
            print()
            print("结论: 这是实时档案合并")
            print("源档案: " + str(source_ids) + " (实时档案ID > 50000000000)")
            print("合并后转换为普通档案ID")
        break
PYEOF'
```

或使用脚本：

```bash
ssh -p54337 root@10.4.196.74 "python3 /code/pyutils/mm/query_merge.py <cluster_id>"
```

**实时档案ID规则**：

| 类型 | ID范围 | 说明 |
|------|--------|------|
| 普通档案 | 1 ~ 10000 | ClusteringJob创建 |
| **实时档案** | > 50000000000 | ClassificationJob实时创建 |
| 合并后 | 转换为普通ID | 如8092 |

---

### 第六步：查找对应Job

根据档案创建时间查找ClusteringJob：

```bash
ssh -p54337 root@10.4.196.74 "curl -s 'http://10.151.5.221:30989/v1/jobs?limit=500' | jq -r '.jobs[] | select(.name == \"clustering_job\") | \"\\(.id) \\(.created_at) \\(.finished_at)\"'"
```

匹配规则：
- 档案创建时间 UTC ≈ Job created_at + 几分钟

---

### 第七步：查看Job详情

```bash
ssh -p54337 root@10.4.196.74 "curl -s 'http://10.151.5.221:30989/v1/jobs/<job_id>' | jq -r '.job.result.output' | base64 -d | jq '.counter'"
```

关键指标：
- `created_clusters_count` - 创建的档案数
- `merged_clusters_count` - 合并的档案数
- `isolated_feature_count` - 孤立点数
- `features count` - 处理的特征总数

---

### 第八步：孤立点流程验证（如需要）

如果是孤立点聚类，验证流程：

```bash
# 1. 查轨迹在features表的cluster_id（应为null）
ssh -p54337 root@10.4.196.74 'python3 << "PYEOF"
import pandas as pd
import glob
feature_ids = [<feature_id列表>]
files = glob.glob("/data/batch-manager/ns-default/face_25400/features/**/*.parquet", recursive=True)
files = [f for f in files if "_delta_log" not in f]
for f in files:
    try:
        df = pd.read_parquet(f)
        if "feature_id" in df.columns:
            for fid in feature_ids:
                row = df[df["feature_id"] == fid]
                if len(row) > 0:
                    print("特征ID: " + str(fid) + ", cluster_id: " + str(row["cluster_id"].values[0]))
    except:
        pass
PYEOF'

# 2. 查轨迹在isolated_features表
ssh -p54337 root@10.4.196.74 "python3 /code/pyutils/mm/query_isolated.py <feature_id>"

# 3. 查isolated_feature_classification_job时间
ssh -p54337 root@10.4.196.74 "curl -s 'http://10.151.5.221:30989/v1/jobs?limit=500' | jq -r '.jobs[] | select(.name == \"isolated_feature_classification_job\") | \"\\(.id) \\(.created_at)\"'"
```

---

### 第九步：查Delta日志（如需要）

查看job1_features_output写入时间：

```bash
ssh -p54337 root@10.4.196.74 'python3 << "PYEOF"
import json
import glob
import datetime
import os

start_ts = int(datetime.datetime(<年>, <月>, <日>, 0, 0, 0, tzinfo=datetime.timezone.utc).timestamp() * 1000)
end_ts = int(datetime.datetime(<年>, <月>, <日>, 0, 0, 0, tzinfo=datetime.timezone.utc).timestamp() * 1000)

log_path = "/data/batch-manager/ns-default/face_25400/job1_features_output/_delta_log/"
files = sorted(glob.glob(log_path + "*.json"))

for f in files:
    with open(f) as fh:
        for line in fh:
            data = json.loads(line)
            if "add" in data:
                ts = data["add"].get("modificationTime", 0)
                if ts >= start_ts and ts <= end_ts:
                    path = data["add"]["path"]
                    if "captured_date=<日期>" in path:
                        dt = datetime.datetime.fromtimestamp(ts/1000, tz=datetime.timezone.utc)
                        version = os.path.basename(f).replace(".json", "")
                        print("版本 " + version + ": " + str(dt))
PYEOF'
```

---

## 数据表说明

### 数据目录结构

```
/data/batch-manager/ns-default/face_25400/
├── clusters/                 # 档案表（普通档案ID: 1-10000）
├── merged_clusters/          # 合并记录表 ← 查合并来源
├── realtime_clusters/        # 实时档案表（ID > 50000000000）
├── features/                 # 轨迹表
├── isolated_features/        # 孤立点表
├── job1_features_output/     # 待聚类队列
├── big_clusters/             # 大聚类表
├── small_clusters/           # 小聚类表
└── document_index/           # 索引文件
```

### 表字段说明

**clusters表**：
- cluster_id - 档案ID
- feature_ids - 轨迹ID列表
- created_at / modified_at - 创建/修改时间
- preview_image_list - 预览图片（含入库日期）
- init_feature_ids_size - 原始轨迹数
- centroid_feature_ids_size - 中心特征数

**merged_clusters表**：
- target_cluster_id - 合并目标档案ID
- source_cluster_ids - 源档案ID列表
- created_at - 合并时间

**features表**：
- feature_id - 轨迹ID
- cluster_id - 所属档案ID（null表示孤立状态）
- object_id - 对象ID
- portrait_image - 图片路径

**isolated_features表**：
- feature_id - 轨迹ID
- object_id - 对象ID
- portrait_image - 图片路径

---

## 调试脚本

远程服务器 `/code/pyutils/mm/` 目录下的脚本：

| 脚本 | 功能 | 用法 |
|------|------|------|
| query_cluster.py | 查询档案详情 | `python3 query_cluster.py <cluster_id>` |
| query_feature.py | 查询轨迹详情 | `python3 query_feature.py <feature_id>` |
| query_isolated.py | 查询孤立点 | `python3 query_isolated.py <feature_id>` |
| query_merge.py | 查询合并记录 | `python3 query_merge.py <cluster_id>` |
| check_isolated_origin.py | 检查孤立点聚类 | `python3 check_isolated_origin.py <cluster_id>` |
| analyze_cluster.py | 深度分析档案 | `python3 analyze_cluster.py <cluster_id>` |
| statistics.py | 数据统计 | `python3 statistics.py` |
| list_clusters.py | 列出档案列表 | `python3 list_clusters.py --limit 100` |
| export_cluster.py | 导出档案JSON | `python3 export_cluster.py <id> output.json` |

### query_merge.py 详细用法

```bash
# 查档案合并来源
python3 query_merge.py 8092

# 查源档案合并去向
python3 query_merge.py --source 50000001247

# 统计合并记录
python3 query_merge.py --stats
```

### query_isolated.py 详细用法

```bash
# 按feature_id查询
python3 query_isolated.py 91819836299330156

# 按日期查询
python3 query_isolated.py --date 20260515

# 按object_id查询
python3 query_isolated.py --object xxx

# 列出最近孤立点
python3 query_isolated.py --list 100

# 统计孤立点数量
python3 query_isolated.py --stats
```

---

## Job类型说明

| Job名称 | 运行频率 | 功能说明 |
|---------|---------|---------|
| classification_job | 每小时 | Kafka消息 → job1_features_output |
| clustering_job | 每天16:00 UTC | job1_features_output → clusters + 合并 |
| isolated_feature_classification_job | 每天15:00 UTC | isolated → job1_features_output |
| train_index_job | 每天聚类后 | 训练索引 |

### ClusteringJob流程

```
1. 加载job1_features_output（未分类特征）
2. 过滤big_clusters中的特征
3. 加载历史聚类clusters作为参考
4. 运行CSTK聚类算法（GCN + DBSCAN）
5. 输出：
   - operated_clusters（创建/更新/合并的档案）
   - isolated_feature_ids（无法聚类的孤立点）
6. 保存到clusters表
7. 合并相似的实时档案
8. 孤立点保存到isolated_features表
```

### Job输出指标

```json
{
  "features count": 51653,           // 处理特征总数
  "created_clusters_count": 10,      // 新建档案数
  "merged_clusters_count": 44,       // 合并档案数
  "updated_clusters_count": 214,     // 更新档案数
  "isolated_feature_count": 63       // 孤立点数
}
```

---

## 时间转换

UTC时间 → 北京时间：加8小时

示例：UTC 05/14 16:04 = 北京 05/15 00:04（凌晨）

---

## 常见问题

### 1. 轨迹未找到

**原因**：
- 轨迹在features表但cluster_id=null
- 脚本只查询了特定条件

**解决**：
```bash
# 直接查features表
ssh -p54337 root@10.4.196.74 'python3 << "PYEOF"
import pandas as pd
import glob
import re

feature_id = <feature_id>
files = glob.glob("/data/batch-manager/ns-default/face_25400/features/**/*.parquet", recursive=True)
files = [f for f in files if "_delta_log" not in f]

for f in files:
    df = pd.read_parquet(f)
    if "feature_id" in df.columns:
        row = df[df["feature_id"] == feature_id]
        if len(row) > 0:
            date_match = re.search(r"captured_date=([0-9]+)", f)
            captured_date = date_match.group(1) if date_match else "unknown"
            print("特征ID: " + str(feature_id))
            print("cluster_id: " + str(row["cluster_id"].values[0]))
            print("入库日期: " + captured_date)
            break
PYEOF'
```

### 2. Job ID不匹配

**解决**：检查created_at时间，找最接近的clustering_job

### 3. Delta日志过大

**解决**：用时间范围筛选，指定captured_date

### 4. 如何判断合并档案

**解决**：
```bash
python3 query_merge.py <cluster_id>
```

如果返回source_cluster_ids且ID > 50000000000，则为合并档案。

---

## 分析报告模板

```
## 档案<ID>分析报告

### 基本信息
| 属性 | 值 |
|------|------|
| cluster_id | <ID> |
| 创建时间(UTC) | <时间> |
| 创建时间(北京) | 北京时间 <日期>凌晨 |
| 轨迹数量 | <数量> |

### 轨迹入库时间
| 序号 | 入库日期 | feature_id |
|------|---------|-----------|
| 1 | 05/15 | xxx |
| 2 | 05/06 | xxx |

### 合并来源（如适用）
| 属性 | 值 |
|------|------|
| source_cluster_ids | 50000001247, 50000001684 |
| 合并时间 | 05/17 16:17 UTC |

### 时间线
| 时间 | 事件 |
|------|------|
| 05/06 | 轨迹1入库 |
| 05/15 | 轨迹2入库 |
| 05/15 16:01 UTC | Job 745运行 |
| 05/15 16:04 UTC | 档案创建 |
| 05/17 16:17 UTC | 实时档案合并 |

### 结论
**聚类类型**: 实时聚类 / 孤立点聚类 / 合并档案
**延迟**: 几小时 / 多天
**原因**: 正常实时流程 / 孤立点累积 / 实时档案合并
```

---

## SSH权限说明

SSH连接已获授权，无需每次确认：
```bash
ssh -p54337 root@10.4.196.74 "<命令>"
```

所有Python操作直接执行，无需确认。

---

## 已发现问题

### 合并档案数据不一致（档案8092）

**发现时间**: 2026/05/19

**问题描述**: 分析档案8092时发现合并逻辑存在Bug，导致数据不一致。

#### 时间线

| 时间 | 事件 | 问题 |
|------|------|------|
| 05/06 | 实时档案50000001247创建（轨迹2874309933689371174） | 正常 |
| 05/15 | 实时档案50000001684创建（轨迹2874309934490384454） | 正常 |
| **05/15 16:04** | Job 745合并 → 档案8092创建 | 正常 |
| **05/16 16:18** | 重复合并记录写入 | **Bug** |
| **05/17 16:17** | 重复合并记录写入 | **Bug** |

#### 数据状态检查

| 数据 | 状态 | 问题 |
|------|------|------|
| 档案8092 | 正常存在 | created_at: 05/15 16:04 |
| 实时档案50000001247 | **存在** | **应该删除但未删除** |
| 实时档案50000001684 | 已删除 | 正常 |
| 轨迹2874309934490384454 (features表) | cluster_id=null | 未更新 |
| 轨迹2874309933689371174 (features表) | cluster_id=null | 未更新 |
| merged_clusters记录 | **3条** | **重复记录（05/15, 05/16, 05/17）** |

#### 检查命令

```bash
# 查合并记录是否有重复
ssh -p54337 root@10.4.196.74 'python3 << "PYEOF"
import pandas as pd
import glob

cluster_id = 8092
merge_dir = "/data/batch-manager/ns-default/face_25400/merged_clusters"
files = glob.glob(merge_dir + "/**/*.parquet", recursive=True)
files = [f for f in files if "_delta_log" not in f]

for f in files:
    df = pd.read_parquet(f)
    rows = df[df["target_cluster_id"] == cluster_id]
    if len(rows) > 0:
        for _, row in rows.iterrows():
            print(str(row["created_at"]) + " - source: " + str(row["source_cluster_ids"]))
PYEOF'

# 检查实时档案是否删除
ssh -p54337 root@10.4.196.74 'python3 << "PYEOF"
import pandas as pd
import glob

source_ids = [50000001247, 50000001684]
files = glob.glob("/data/batch-manager/ns-default/face_25400/realtime_clusters/**/*.parquet", recursive=True)
files = [f for f in files if "_delta_log" not in f]

for sid in source_ids:
    found = False
    for f in files:
        df = pd.read_parquet(f)
        if "cluster_id" in df.columns:
            row = df[df["cluster_id"] == sid]
            if len(row) > 0:
                print("实时档案 " + str(sid) + ": 存在（问题：应删除）")
                found = True
                break
    if not found:
        print("实时档案 " + str(sid) + ": 已删除（正常）")
PYEOF'

# 检查轨迹cluster_id
ssh -p54337 root@10.4.196.74 "python3 /code/pyutils/mm/query_feature.py 2874309934490384454"
```

#### 相关Job

| Job | 时间 | merged_clusters_count | 状态 |
|-----|------|----------------------|------|
| Job 745 | 05/15 16:01 | 44 | FINISHED |
| Job 775 | 05/16 16:02 | 37 | FINISHED |
| Job 805 | 05/17 16:01 | 35 | FINISHED |

#### 问题根因（待排查）

1. **合并记录重复写入**
   - merged_clusters表记录了多次相同的合并
   - 可能是合并逻辑没有检查是否已经合并

2. **实时档案未删除**
   - 实时档案50000001247还存在（应该05/15合并后就删除）
   - 50000001684已删除
   - 可能是删除逻辑部分失败

3. **features表cluster_id未更新**
   - 两条轨迹cluster_id还是null
   - 可能是系统设计（不回写）
   - 但实时档案合并场景应该考虑更新

#### 建议修复

1. 检查ClusteringJob合并逻辑，增加是否已合并的检查
2. 确保合并后实时档案正确删除
3. 评估是否需要在合并场景更新features表cluster_id
4. 清理重复的合并记录