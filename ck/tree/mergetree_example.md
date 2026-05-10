# ClickHouse MergeTree 表引擎示例（集群版）

> **重要**：在集群环境中，DDL 和 DML 操作需要使用 `ON CLUSTER` 子句才能在所有节点执行。

---

## 1. 创建数据库

```sql
CREATE DATABASE IF NOT EXISTS mm_db ON CLUSTER clicks_cluster_human
ENGINE = Atomic;
```

### 参数说明

| 参数 | 说明 |
|------|------|
| `ON CLUSTER clicks_cluster_human` | 在集群所有节点上创建数据库 |
| `IF NOT EXISTS` | 如果数据库已存在则不报错 |
| `ENGINE = Atomic` | 数据库引擎，Atomic 支持事务（推荐） |

---

## 2. 建表语句

### 2.1 创建本地表（ReplicatedMergeTree）

```sql
CREATE TABLE mm_db.user_access_log ON CLUSTER clicks_cluster_human
(
    id              UInt64,
    user_id         UInt64,
    event_type      String,
    event_time      DateTime,
    page_url        String,
    ip_address      String,
    user_agent      String,
    referer         String,
    duration        UInt32,
    created_at      DateTime DEFAULT now()
)
ENGINE = ReplicatedMergeTree('/clickhouse/tables/{cluster}/{shard}/user_access_log', '{replica}')
PARTITION BY toYYYYMM(event_time)
ORDER BY (user_id, event_time)
PRIMARY KEY (user_id, event_time)
SETTINGS index_granularity = 8192;
```

#### 引擎参数详解

```sql
ENGINE = ReplicatedMergeTree(zookeeper_path, replica_name)
```

| 参数 | 值 | 说明 |
|------|-----|------|
| `zookeeper_path` | `/clickhouse/tables/{cluster}/{shard}/user_access_log` | ZooKeeper 中的表元数据路径，**同一 shard 的副本必须相同** |
| `replica_name` | `'{replica}'` | 副本名称，**同一 shard 内每个副本必须唯一** |

**ZooKeeper 路径替换规则**（根据 macros.xml 配置自动替换）：

| 节点 | `{cluster}` | `{shard}` | `{replica}` | 最终 ZooKeeper 路径 | 副本名 |
|------|-------------|-----------|-------------|---------------------|--------|
| ck1 | clicks_cluster_human | 1 | 1 | `/clickhouse/tables/clicks_cluster_human/1/user_access_log` | `1` |
| ck2 | clicks_cluster_human | 1 | 2 | `/clickhouse/tables/clicks_cluster_human/1/user_access_log` | `2` |
| ck3 | clicks_cluster_human | 2 | 1 | `/clickhouse/tables/clicks_cluster_human/2/user_access_log` | `1` |

**关键点**：
- ck1 和 ck2 的 ZooKeeper 路径**相同**（都是 shard 1），所以它们互为副本，数据自动同步
- ck3 的 ZooKeeper 路径**不同**（shard 2），所以它是独立的分片

#### 其他参数详解

| 参数 | 值 | 说明 |
|------|-----|------|
| `PARTITION BY` | `toYYYYMM(event_time)` | 按月份分区，如 `202505`、`202506`，便于按时间删除旧数据 |
| `ORDER BY` | `(user_id, event_time)` | 排序键，数据在磁盘上按此顺序存储，影响查询性能 |
| `PRIMARY KEY` | `(user_id, event_time)` | 主键，用于构建稀疏索引，ClickHouse 主键**不要求唯一** |
| `index_granularity` | `8192` | 索引粒度，每 8192 行数据生成一个索引标记 |

**ORDER BY vs PRIMARY KEY 详解**：

#### 核心规则

**PRIMARY KEY 必须是 ORDER BY 的前缀**，这是 ClickHouse 的强制要求。

```sql
-- ✅ 正确：PRIMARY KEY 是 ORDER BY 的前缀
ORDER BY (user_id, event_time)
PRIMARY KEY (user_id)

-- ✅ 正确：PRIMARY KEY 与 ORDER BY 完全相同
ORDER BY (user_id, event_time)
PRIMARY KEY (user_id, event_time)

-- ❌ 错误：PRIMARY KEY 不是 ORDER BY 的前缀
ORDER BY (user_id, event_time)
PRIMARY KEY (event_time)  -- 报错！

-- ❌ 错误：PRIMARY KEY 包含 ORDER BY 中没有的字段
ORDER BY (user_id, event_time)
PRIMARY KEY (user_id, ip_address)  -- 报错！
```

#### 两者的作用

| 对比项 | ORDER BY | PRIMARY KEY |
|--------|----------|-------------|
| **作用** | 决定数据在磁盘上的**物理存储顺序** | 决定**稀疏索引**的构建字段 |
| **影响** | 影响数据压缩率、查询性能 | 影响索引查找效率 |
| **必须唯一** | 否 | 否 |
| **可省略** | 否 | 可省略（默认与 ORDER BY 相同） |

#### 数据存储原理

```
数据文件按 ORDER BY 排序存储：

磁盘数据（按 user_id, event_time 排序）：
┌─────────────────────────────────────────────────────────┐
│ user_id=1, event_time=10:00  │ user_id=1, event_time=10:05  │ ... │
└─────────────────────────────────────────────────────────┘
          ↑                              ↑
    索引标记1                        索引标记2
    (每 8192 行一个标记)

稀疏索引（按 PRIMARY KEY 构建）：
┌───────────────┬─────────────────────┐
│ PRIMARY KEY   │ 数据文件偏移量       │
├───────────────┼─────────────────────┤
│ (user_id=1)   │ offset=0            │
│ (user_id=1)   │ offset=8192         │
│ (user_id=2)   │ offset=16384        │
└───────────────┴─────────────────────┘
```

#### 为什么要分开？

当 PRIMARY KEY 与 ORDER BY 不同时，可以优化特定查询场景：

```sql
-- 场景：经常按 user_id 查询，但数据按 (user_id, event_time) 排序
ORDER BY (user_id, event_time)
PRIMARY KEY (user_id)

-- 查询 1：只按 user_id 过滤（命中 PRIMARY KEY 索引，快速）
SELECT * FROM user_access_log WHERE user_id = 1001;

-- 查询 2：按 user_id + event_time 过滤（命中 ORDER BY 排序，更快速）
SELECT * FROM user_access_log WHERE user_id = 1001 AND event_time > '2025-05-01';

-- 查询 3：只按 event_time 过滤（无法利用索引，全表扫描）
SELECT * FROM user_access_log WHERE event_time > '2025-05-01';  -- 慢！
```

#### 最佳实践

| 场景 | 推荐配置 | 说明 |
|------|----------|------|
| 通用场景 | `ORDER BY` 和 `PRIMARY KEY` 相同 | 简单易懂，大多数情况够用 |
| 高频按前缀字段查询 | `PRIMARY KEY` 设为 `ORDER BY` 的前缀 | 减少索引大小，加速前缀查询 |
| 时间序列数据 | `ORDER BY (id, time)`，`PRIMARY KEY (id)` | 按 id 快速定位，再按时间范围扫描 |

#### 示例对比

```sql
-- 方案 1：PRIMARY KEY 与 ORDER BY 相同（推荐新手使用）
ENGINE = MergeTree()
ORDER BY (user_id, event_time)
PRIMARY KEY (user_id, event_time)  -- 可省略，默认相同

-- 方案 2：PRIMARY KEY 是 ORDER BY 的前缀（优化索引大小）
ENGINE = MergeTree()
ORDER BY (user_id, event_time)
PRIMARY KEY (user_id)  -- 索引更小，按 user_id 查询更快
```

#### PARTITION BY 分区详解

分区是 ClickHouse 数据管理的核心概念，**分区是数据在磁盘上的物理划分**。

##### 分区的作用

| 作用 | 说明 |
|------|------|
| **数据生命周期管理** | 按分区删除旧数据（`ALTER TABLE DROP PARTITION`），比 DELETE 更高效 |
| **查询优化** | 查询时只扫描相关分区，跳过无关分区（分区裁剪） |
| **数据导入导出** | 可以按分区导入导出数据 |
| **并行处理** | 不同分区可以并行查询和处理 |

##### 分区 vs 排序键

| 对比项 | PARTITION BY | ORDER BY |
|--------|--------------|----------|
| **粒度** | 粗粒度，按分区键划分数据目录 | 细粒度，数据在分区内部排序 |
| **数量** | 分区不宜过多（建议 < 1000） | 排序键字段可以多个 |
| **查询影响** | 分区裁剪，跳过整个分区 | 索引查找，定位具体数据范围 |
| **删除方式** | `ALTER TABLE DROP PARTITION` | `DELETE` 或 `ALTER TABLE DELETE` |

##### 分区存储结构

```
/var/lib/clickhouse/data/mm_db/user_access_log/
├── 202505_1_1_0/          # 2025年5月分区
│   ├── user_id.bin        # 数据列文件
│   ├── event_time.bin
│   ├── primary.idx        # 主键索引
│   └── ...
├── 202506_1_1_0/          # 2025年6月分区
│   └── ...
└── 202507_1_1_0/          # 2025年7月分区
    └── ...
```

##### 常用分区策略

```sql
-- 按月分区（推荐，适合时间序列数据）
PARTITION BY toYYYYMM(event_time)

-- 按日分区（数据量大、需要按日删除）
PARTITION BY toYYYYMMDD(event_time)

-- 按小时分区（数据量极大、实时性要求高）
PARTITION BY toYYYYMMDDHHmmss(event_time)

-- 按字段值分区（适合离散值少的字段）
PARTITION BY event_type

-- 多字段分区（复合分区）
PARTITION BY (toYYYYMM(event_time), event_type)
```

##### 分区管理示例

```sql
-- 查看分区列表
SELECT partition, name, rows, bytes_on_disk 
FROM system.parts 
WHERE table = 'user_access_log' AND active = 1;

-- 删除指定分区（高效，直接删除目录）
ALTER TABLE user_access_log DROP PARTITION '202505';

-- 分区冻结（用于备份）
ALTER TABLE user_access_log FREEZE PARTITION '202505';

-- 分区移动到其他表
ALTER TABLE user_access_log MOVE PARTITION '202505' TO TABLE archive_table;

-- 分区 detached（暂时移除，可恢复）
ALTER TABLE user_access_log DETACH PARTITION '202505';
ALTER TABLE user_access_log ATTACH PARTITION '202505';
```

##### 分区注意事项

1. **分区不宜过多**：每个分区都会产生文件目录，分区过多会导致文件系统压力
2. **分区键选择**：选择查询中常用的过滤字段，或时间字段
3. **分区大小**：单个分区建议 1GB - 100GB，太小浪费资源，太大影响查询效率
4. **避免按高基数字段分区**：如 user_id（百万用户会产生百万分区）

---

#### Parts 数据片段详解

**Parts（数据片段）是 ClickHouse MergeTree 引擎数据存储的基本单位。**

##### 什么是 Parts？

每次 `INSERT` 操作都会产生一个独立的 **part**，它是一个包含实际数据的目录。

```
一次 INSERT = 一个新的 part

INSERT 1000 行 → part_1
INSERT 1500 行 → part_2
INSERT 2000 行 → part_3
```

##### Parts 与分区的关系

```
分区是逻辑划分，Parts 是物理存储：

/var/lib/clickhouse/data/mm_db/user_access_log/
├── 202505/                      # 分区：2025年5月
│   ├── 202505_1_1_0/            # part 1（第一批插入）
│   ├── 202505_2_2_0/            # part 2（第二批插入）
│   └── 202505_3_3_0/            # part 3（第三批插入）
│
└── 202506/                      # 分区：2025年6月
    ├── 202506_1_1_0/            # part 1
    └── 202506_2_2_0/            # part 2
```

**一个分区下可以有多个 parts**。

##### Part 目录结构

每个 part 目录包含：

```
202505_1_1_0/
├── user_id.bin          # 列数据文件
├── user_id.mrk          # 列标记文件
├── event_time.bin
├── event_time.mrk
├── primary.idx          # 主键索引
├── checksums.txt        # 校验文件
├── columns.txt          # 列定义
├── count.txt            # 行数
└── minmax_user_id.idx   # 最小最大值索引
```

##### Part Name 命名规则

Part 目录名遵循固定格式：`partition_id_min_block_max_block_level`

```
示例：202505_1_1_0

┌─────────────────────────────────────────────────────┐
│  202505    │    1    │    1    │    0    │
│  分区ID    │ min_block│ max_block│  level  │
└─────────────────────────────────────────────────────┘
```

| 字段 | 说明 | 示例值 |
|------|------|--------|
| `partition_id` | 分区标识，由 PARTITION BY 生成 | `202505`（按月分区） |
| `min_block` | 该 part 的最小块号 | `1` |
| `max_block` | 该 part 的最大块号 | `1` |
| `level` | 合并层级，每次合并后 +1 | `0`（未合并） |

**命名规则详解**：

```
1. 新插入的 part：
   202505_1_1_0    # min_block=1, max_block=1, level=0
   202505_2_2_0    # min_block=2, max_block=2, level=0
   202505_3_3_0    # min_block=3, max_block=3, level=0

2. 合并后的 part：
   202505_1_3_1    # 合并了 block 1-3，level=1
   （min_block 取最小值，max_block 取最大值）

3. 再次合并：
   202505_1_10_2   # 合并了 block 1-10，level=2
```

**level 的含义**：

| level | 说明 |
|-------|------|
| `0` | 新插入的原始 part |
| `1` | 经过 1 次合并 |
| `2` | 经过 2 次合并 |
| ... | 合并次数越多，level 越大，part 通常越大 |

**特殊命名**：

```sql
-- 分区名为 'all'（未指定 PARTITION BY）
all_1_1_0

-- 自定义分区名
my_partition_1_1_0
```

##### 为什么需要 Parts？

| 原因 | 说明 |
|------|------|
| **写入高效** | 每次 INSERT 直接写入新 part，不需要修改已有数据 |
| **并发写入** | 多个 INSERT 可以并行，互不阻塞 |
| **增量合并** | 后台异步合并，不影响写入性能 |

##### Parts 的生命周期

```
1. INSERT → 产生新 part（active 状态）

2. 后台合并 → 多个小 parts 合成大 part
   ┌─────────┐  ┌─────────┐  ┌─────────┐
   │ part_1  │  │ part_2  │  │ part_3  │  → 合并
   └─────────┘  └─────────┘  └─────────┘
                    ↓
            ┌─────────────────┐
            │   merged_part   │
            └─────────────────┘

3. 合并完成 → 旧 parts 标记为 inactive，等待删除
```

##### Parts 对查询的影响

| Parts 数量 | 查询性能 |
|------------|----------|
| 少（< 10） | 快，读取文件少 |
| 多（> 100） | 慢，需要打开大量文件 |

这就是为什么需要 `OPTIMIZE TABLE` —— 减少 parts 数量，优化查询性能。

##### 查看 Parts

```sql
SELECT 
    partition,
    name as part_name,
    rows,
    bytes_on_disk,
    active
FROM system.parts 
WHERE table = 'user_access_log'
ORDER BY partition, name;
```

---

#### OPTIMIZE TABLE 详解

MergeTree 系列引擎的数据是**异步合并**的，`OPTIMIZE TABLE` 用于强制触发合并。

##### 合并原理

```
插入数据后产生多个数据片段（parts）：

初始状态（插入3批数据）：
┌─────────┐  ┌─────────┐  ┌─────────┐
│ part_1  │  │ part_2  │  │ part_3  │
│ 1000行  │  │ 1500行  │  │ 2000行  │
└─────────┘  └─────────┘  └─────────┘

后台合并后：
┌───────────────────────────┐
│       merged_part         │
│       4500行              │
└───────────────────────────┘
```

##### OPTIMIZE TABLE 作用

| 作用 | 说明 |
|------|------|
| **减少 parts 数量** | 合并多个小 parts 为大 parts，减少文件数量 |
| **优化查询性能** | parts 少，查询时需要读取的文件少 |
| **释放磁盘空间** | 合并后删除旧 parts，释放重复数据占用的空间 |
| **触发 TTL 清理** | 合并时会执行 TTL 规则，删除过期数据 |
| **去重** | 对于 ReplacingMergeTree，合并时会去重 |

##### 使用方式

```sql
-- 触发一次合并（不保证合并完成）
OPTIMIZE TABLE user_access_log;

-- 强制合并到只剩一个 part（FINAL，资源消耗大）
OPTIMIZE TABLE user_access_log FINAL;

-- 合并指定分区
OPTIMIZE TABLE user_access_log PARTITION '202505';

-- 集群上执行
OPTIMIZE TABLE user_access_log ON CLUSTER clicks_cluster_human FINAL;
```

##### FINAL 的风险

```sql
-- ⚠️ 谨慎使用 FINAL
OPTIMIZE TABLE user_access_log FINAL;
```

| 风险 | 说明 |
|------|------|
| **资源消耗大** | 强制合并所有 parts，消耗大量 CPU 和内存 |
| **阻塞写入** | 合并期间可能影响写入性能 |
| **时间长** | 大表合并可能需要数小时 |

##### 最佳实践

| 场景 | 建议 |
|------|------|
| **日常运维** | 不需要手动执行，后台会自动合并 |
| **数据导入后** | 执行一次 `OPTIMIZE TABLE`（不加 FINAL） |
| **查询性能优化** | 在低峰期执行 `OPTIMIZE TABLE FINAL` |
| **TTL 清理** | 执行 `OPTIMIZE TABLE` 触发 TTL |

##### 查看合并状态

```sql
-- 查看 parts 数量
SELECT 
    partition,
    count() as parts_count,
    sum(rows) as total_rows,
    sum(bytes_on_disk) as total_bytes
FROM system.parts
WHERE table = 'user_access_log' AND active = 1
GROUP BY partition;

-- 查看正在进行的合并
SELECT * FROM system.merges;

-- 查看合并历史
SELECT * FROM system.part_log WHERE event_type = 'Merge';
```

---

### 2.2 创建分布式表（Distributed）

```sql
CREATE TABLE mm_db.user_access_log_dist ON CLUSTER clicks_cluster_human
(
    id              UInt64,
    user_id         UInt64,
    event_type      String,
    event_time      DateTime,
    page_url        String,
    ip_address      String,
    user_agent      String,
    referer         String,
    duration        UInt32,
    created_at      DateTime
)
ENGINE = Distributed(clicks_cluster_human, mm_db, user_access_log, rand());
```

### 参数说明

| 参数 | 说明 |
|------|------|
| `ON CLUSTER clicks_cluster_human` | 在集群所有节点上执行 |
| `ReplicatedMergeTree` | 支持副本同步的表引擎 |
| `/clickhouse/tables/{cluster}/{shard}/user_access_log` | ZooKeeper 中的表路径，`{cluster}` 和 `{shard}` 会自动替换 |
| `'{replica}'` | 副本名称，`{replica}` 会自动替换为 macros 中定义的值 |
| `Distributed` | 分布式表引擎，聚合所有 shard 的数据 |
| `rand()` | 分片键，随机写入各 shard |

### 表架构说明

```
┌─────────────────────────────────────────────────────────────┐
│                    user_access_log_dist                      │
│                    (Distributed 表)                          │
│                      读写入口                                │
└─────────────────────────────────────────────────────────────┘
                              │
              ┌───────────────┴───────────────┐
              ▼                               ▼
    ┌─────────────────┐             ┌─────────────────┐
    │     Shard 1     │             │     Shard 2     │
    │ user_access_log │             │ user_access_log │
    │ (Replicated)    │             │ (Replicated)    │
    └────────┬────────┘             └────────┬────────┘
             │                               │
        ┌────┴────┐                          │
        ▼         ▼                          ▼
      ck1        ck2                        ck3
    (replica1) (replica2)                  (replica1)
```

---

## 3. 插入数据示例

### 3.1 单条插入（通过分布式表）

```sql
INSERT INTO mm_db.user_access_log_dist 
(id, user_id, event_type, event_time, page_url, ip_address, user_agent, referer, duration)
VALUES
(1, 1001, 'page_view', '2025-05-01 10:30:00', '/home', '192.168.1.1', 'Mozilla/5.0', '', 120),
(2, 1002, 'click', '2025-05-01 10:31:00', '/product/123', '192.168.1.2', 'Chrome/91.0', '/home', 45),
(3, 1003, 'page_view', '2025-05-01 10:32:00', '/about', '192.168.1.3', 'Safari/14.0', '', 200);
```

### 3.2 批量插入（推荐）

```sql
INSERT INTO mm_db.user_access_log_dist 
(id, user_id, event_type, event_time, page_url, ip_address, user_agent, referer, duration)
SELECT
    number,
    rand() % 10000,
    arrayElement(['page_view', 'click', 'scroll', 'submit'], rand() % 4 + 1),
    now() - INTERVAL rand() % 86400 SECOND,
    arrayElement(['/home', '/product/' || toString(rand() % 100), '/about', '/contact'], rand() % 4 + 1),
    '192.168.' || toString(rand() % 255) || '.' || toString(rand() % 255),
    'Mozilla/5.0',
    '',
    rand() % 600
FROM numbers(10000);
```

### 3.3 直接插入本地表（指定 shard）

```sql
-- 直接插入 Shard 1 的本地表（ck1 和 ck2 会自动同步）
INSERT INTO mm_db.user_access_log 
(id, user_id, event_type, event_time, page_url, ip_address, user_agent, referer, duration)
VALUES (100, 2001, 'page_view', now(), '/test', '10.0.0.1', 'Mozilla/5.0', '', 100);
```

> **注意**：直接插入本地表时，数据只会写入该 shard。推荐使用分布式表插入，数据会自动分发。

---

## 4. 常用查询示例

### 4.1 查询分布式表（聚合所有 shard）

```sql
-- 查询最近 1 小时的数据
SELECT *
FROM mm_db.user_access_log_dist
WHERE event_time >= now() - INTERVAL 1 HOUR
LIMIT 100;

-- 按用户统计访问次数
SELECT user_id, COUNT(*) as visit_count
FROM mm_db.user_access_log_dist
WHERE event_time >= today()
GROUP BY user_id
ORDER BY visit_count DESC
LIMIT 10;
```

### 4.2 聚合查询

```sql
-- 按事件类型统计
SELECT event_type, COUNT(*) as count, AVG(duration) as avg_duration
FROM mm_db.user_access_log_dist
WHERE event_time >= '2025-05-01 00:00:00'
  AND event_time < '2025-05-02 00:00:00'
GROUP BY event_type;

-- 按小时统计访问趋势
SELECT toHour(event_time) as hour, COUNT(*) as visits
FROM mm_db.user_access_log_dist
WHERE event_time >= today()
GROUP BY hour
ORDER BY hour;
```

### 4.3 查询单个 shard 的本地表

```sql
-- 只查询 ck1 上的数据
SELECT COUNT(*) FROM mm_db.user_access_log;

-- 查看各 shard 数据分布
SELECT 
    hostName() as host,
    COUNT(*) as rows
FROM mm_db.user_access_log_dist
GROUP BY host;
```

---

## 5. 表管理命令

### 5.1 查看表结构

```sql
DESCRIBE mm_db.user_access_log;
```

### 5.2 查看分区信息

```sql
SELECT 
    partition,
    name,
    rows,
    bytes_on_disk
FROM system.parts 
WHERE table = 'user_access_log' 
  AND database = 'mm_db'
  AND active = 1
ORDER BY partition, name;
```

### 5.3 手动合并分区

```sql
OPTIMIZE TABLE mm_db.user_access_log ON CLUSTER clicks_cluster_human FINAL;
```

### 5.4 删除旧数据（按分区）

```sql
ALTER TABLE mm_db.user_access_log ON CLUSTER clicks_cluster_human 
DROP PARTITION '202504';
```

### 5.5 查看集群状态

```sql
-- 查看集群节点
SELECT cluster, shard_num, replica_num, host_name, port
FROM system.clusters
WHERE cluster = 'clicks_cluster_human';

-- 查看副本状态
SELECT 
    database,
    table,
    engine,
    replica_name,
    replica_path,
    total_replicas,
    active_replicas
FROM system.replicas
WHERE database = 'mm_db';
```

### 5.6 删除表

```sql
-- 删除分布式表
DROP TABLE IF EXISTS mm_db.user_access_log_dist ON CLUSTER clicks_cluster_human;

-- 删除本地表
DROP TABLE IF EXISTS mm_db.user_access_log ON CLUSTER clicks_cluster_human;
```

---

## 6. 注意事项

1. **ON CLUSTER 必须加**：DDL 操作（CREATE/DROP/ALTER）必须加 `ON CLUSTER` 才能在所有节点执行
2. **数据写入**：推荐通过分布式表写入，数据会自动分发到各 shard
3. **数据查询**：推荐查询分布式表，会自动聚合所有 shard 的数据
4. **副本同步**：同一 shard 内的副本会自动同步（如 ck1 和 ck2）
5. **批量插入**：建议每次插入 1000-10000 行，避免频繁小批量插入
6. **分区设计**：分区键不宜过多，通常按时间分区即可