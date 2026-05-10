# ClickHouse 分区管理与视图

> 本文档介绍 ClickHouse 的分区管理操作（DETACH/ATTACH）以及视图（普通视图和物化视图）的使用。

---

## 目录

| 章节 | 内容 |
|------|------|
| [1. 分区管理](#1-分区管理) | DETACH/ATTACH 分区、对比、示例、注意事项 |
| [2. 视图](#2-视图view) | 普通视图和物化视图详解 |

---

## 1. 分区管理

### 1.1 卸载分区（DETACH PARTITION）

#### 基本语法

```sql
ALTER TABLE [db.]table DETACH PARTITION|PART partition_expr [ON CLUSTER cluster]
```

#### 作用

将分区从表中**卸载**，但**不删除数据**：

- 分区数据从表中"消失"，查询不到
- 数据文件移动到 `detached/` 目录
- 可以通过 `ATTACH PARTITION` 恢复

#### 分区表达式

```sql
-- 按分区名卸载
ALTER TABLE user_access_log DETACH PARTITION '202505';

-- 按分区 ID 卸载
ALTER TABLE user_access_log DETACH PARTITION ID '202505';

-- 卸载指定 part
ALTER TABLE user_access_log DETACH PART '202505_1_1_0';

-- 集群上执行
ALTER TABLE user_access_log DETACH PARTITION '202505' ON CLUSTER clicks_cluster_human;
```

#### 卸载后的目录结构

```
/var/lib/clickhouse/data/mm_db/user_access_log/
├── 202506_1_1_0/              # 正常分区（可查询）
├── 202507_1_1_0/              # 正常分区（可查询）
└── detached/                  # 卸载的分区存放位置
    └── 202505_1_1_0/          # 已卸载分区（不可查询）
```

#### 使用场景

| 场景 | 说明 |
|------|------|
| **临时移除数据** | 某个分区数据有问题，暂时移除排查 |
| **数据归档** | 将旧数据移到 detached 目录，后续可删除或备份 |
| **数据迁移** | 将 detached 目录下的数据复制到其他表或集群 |
| **数据修复** | 卸载有问题的分区，修复后重新装载 |

#### 查看已卸载的分区

```sql
SELECT 
    partition,
    name as part_name,
    rows,
    bytes_on_disk,
    active
FROM system.parts 
WHERE table = 'user_access_log' 
  AND active = 0;
```

---

### 1.2 装载分区（ATTACH PARTITION）

#### 基本语法

```sql
-- 从 detached 目录装载分区
ALTER TABLE [db.]table ATTACH PARTITION|PART partition_expr [ON CLUSTER cluster]

-- 从另一个表装载分区
ALTER TABLE [db.]table ATTACH PARTITION partition_expr FROM [db.]source_table [ON CLUSTER cluster]
```

#### 从 detached 目录装载

```sql
-- 装载指定分区
ALTER TABLE user_access_log ATTACH PARTITION '202505';

-- 装载指定 part
ALTER TABLE user_access_log ATTACH PART '202505_1_1_0';

-- 集群上执行
ALTER TABLE user_access_log ATTACH PARTITION '202505' ON CLUSTER clicks_cluster_human;
```

#### 从其他表装载分区

```sql
-- 从其他表装载分区（源表分区会被删除）
ALTER TABLE user_access_log ATTACH PARTITION '202505' FROM archive_table;

-- 典型场景：从归档表恢复数据
ALTER TABLE user_access_log ATTACH PARTITION '202505' FROM user_access_log_archive;
```

#### 装载过程

```
1. 检查 detached 目录下是否存在目标分区
2. 验证分区数据完整性
3. 将分区元数据注册到系统表
4. 分区变为 active 状态，可被查询
```

#### 使用场景

| 场景 | 说明 |
|------|------|
| **恢复数据** | 将之前卸载的分区重新装载 |
| **数据迁移** | 从其他表导入分区数据 |
| **数据修复** | 修复后重新装载分区 |

---

### 1.3 DETACH vs DROP 对比

| 对比项 | DETACH PARTITION | DROP PARTITION |
|--------|-------------------|----------------|
| **数据是否删除** | 否，移到 detached 目录 | 是，永久删除 |
| **是否可恢复** | 是，通过 ATTACH 恢复 | 否，需要从备份恢复 |
| **磁盘空间** | 不释放 | 释放 |
| **速度** | 快（移动目录） | 快（删除目录） |
| **使用场景** | 临时移除、数据迁移 | 永久删除旧数据 |

---

### 1.4 完整操作示例

#### 场景 1：临时移除问题分区

```sql
-- 1. 查看分区
SELECT partition, name, rows, bytes_on_disk 
FROM system.parts 
WHERE table = 'user_access_log' AND active = 1;

-- 2. 卸载问题分区
ALTER TABLE user_access_log DETACH PARTITION '202505';

-- 3. 验证分区已卸载（查询不到数据）
SELECT count() FROM user_access_log WHERE toYYYYMM(event_time) = 202505;

-- 4. 排查问题...

-- 5. 恢复分区
ALTER TABLE user_access_log ATTACH PARTITION '202505';

-- 6. 验证数据恢复
SELECT count() FROM user_access_log WHERE toYYYYMM(event_time) = 202505;
```

#### 场景 2：数据归档与恢复

```sql
-- 1. 创建归档表（结构相同）
CREATE TABLE user_access_log_archive ON CLUSTER clicks_cluster_human
AS user_access_log
ENGINE = ReplicatedMergeTree('/clickhouse/tables/{cluster}/{shard}/user_access_log_archive', '{replica}')
PARTITION BY toYYYYMM(event_time)
ORDER BY (user_id, event_time);

-- 2. 卸载旧分区
ALTER TABLE user_access_log DETACH PARTITION '202401';

-- 3. 手动复制 detached 目录数据到归档表
-- （在服务器上操作文件系统）
-- cp -r /var/lib/clickhouse/data/mm_db/user_access_log/detached/202401_*
--        /var/lib/clickhouse/data/mm_db/user_access_log_archive/detached/

-- 4. 装载到归档表
ALTER TABLE user_access_log_archive ATTACH PARTITION '202401';

-- 5. 删除原表的 detached 数据（可选）
-- rm -rf /var/lib/clickhouse/data/mm_db/user_access_log/detached/202401_*
```

#### 场景 3：跨表移动分区

```sql
-- 将分区从源表移动到目标表（源表分区会被删除）
ALTER TABLE target_table ATTACH PARTITION '202505' FROM source_table;

-- 等价于：
-- 1. DETACH PARTITION from source_table
-- 2. 手动移动数据文件
-- 3. ATTACH PARTITION to target_table
```

---

### 1.5 注意事项

#### 权限要求

```sql
-- 需要 ALTER 权限
GRANT ALTER ON db.* TO user;
```

#### 副本表注意事项

```sql
-- ReplicatedMergeTree 表的 DETACH/ATTACH 会同步到所有副本
-- 确保所有节点都执行成功

-- 查看副本状态
SELECT 
    database,
    table,
    replica_name,
    replica_path,
    zookeeper_path
FROM system.replicas
WHERE table = 'user_access_log';
```

#### 性能影响

| 操作 | 性能影响 |
|------|----------|
| DETACH | 低，仅移动目录和更新元数据 |
| ATTACH | 低，仅注册元数据 |
| DROP | 低，删除目录 |

#### 常见错误

```sql
-- 错误 1：分区不存在
ALTER TABLE user_access_log DETACH PARTITION '209999';
-- Code: 602. DB::Exception: Partition '209999' not found

-- 错误 2：detached 目录下没有目标分区
ALTER TABLE user_access_log ATTACH PARTITION '202505';
-- Code: 232. DB::Exception: Part '202505' not found in detached directory

-- 错误 3：分区已存在
ALTER TABLE user_access_log ATTACH PARTITION '202505';
-- Code: 230. DB::Exception: Partition '202505' already exists
```

---

### 1.6 相关系统表

```sql
-- 查看所有分区（包括已卸载的）
SELECT 
    partition,
    name,
    rows,
    bytes_on_disk,
    active,
    database,
    table
FROM system.parts 
WHERE table = 'user_access_log'
ORDER BY partition, active DESC;

-- 查看分区操作日志
SELECT 
    event_date,
    event_time,
    database,
    table,
    event_type,
    partition_id,
    part_name
FROM system.part_log
WHERE table = 'user_access_log'
ORDER BY event_time DESC
LIMIT 20;
```

---

### 1.7 最佳实践

| 实践 | 说明 |
|------|------|
| **先查询再操作** | 操作前确认分区名称和范围 |
| **备份重要数据** | DETACH 前建议备份关键数据 |
| **低峰期操作** | 大分区操作建议在低峰期进行 |
| **验证结果** | 操作后验证数据完整性 |
| **监控磁盘** | 关注 detached 目录磁盘占用 |

---

## 2. 视图（View）

ClickHouse 支持两种视图：**普通视图**和**物化视图**。

### 2.1 普通视图（View）

#### 基本概念

普通视图**不存储数据**，只是保存的 SELECT 查询。每次查询视图时，ClickHouse 会将视图的 SELECT 语句替换到查询中执行。

```
查询视图 → 展开视图定义 → 执行实际查询

例如：
SELECT * FROM my_view WHERE user_id = 1
    ↓ 展开视图
SELECT * FROM (SELECT * FROM user_access_log WHERE event_type = 'click') WHERE user_id = 1
```

#### 创建视图

```sql
-- 基本语法
CREATE VIEW [IF NOT EXISTS] [db.]view_name [ON CLUSTER cluster]
AS SELECT ...

-- 示例：创建点击事件视图
CREATE VIEW mm_db.click_events_view ON CLUSTER clicks_cluster_human
AS
SELECT 
    id,
    user_id,
    event_time,
    page_url,
    ip_address
FROM mm_db.user_access_log
WHERE event_type = 'click';

-- 示例：创建聚合视图
CREATE VIEW mm_db.daily_stats_view ON CLUSTER clicks_cluster_human
AS
SELECT
    toDate(event_time) AS date,
    event_type,
    count() AS event_count,
    uniq(user_id) AS unique_users
FROM mm_db.user_access_log
GROUP BY date, event_type;
```

#### 查询视图

```sql
-- 像查询表一样查询视图
SELECT * FROM mm_db.click_events_view LIMIT 10;

-- 带条件查询
SELECT * FROM mm_db.daily_stats_view 
WHERE date = '2025-05-01' 
ORDER BY event_count DESC;
```

#### 查看视图定义

```sql
-- 查看视图的 SQL 定义
SHOW CREATE VIEW mm_db.click_events_view;

-- 从系统表查看
SELECT 
    database,
    name,
    as_select
FROM system.views
WHERE database = 'mm_db';
```

#### 删除视图

```sql
DROP VIEW [IF EXISTS] [db.]view_name [ON CLUSTER cluster];

-- 示例
DROP VIEW mm_db.click_events_view ON CLUSTER clicks_cluster_human;
```

#### 普通视图的特点

| 特点 | 说明 |
|------|------|
| **不存储数据** | 每次查询都重新执行 SELECT |
| **无性能开销** | 创建和删除都是元数据操作 |
| **实时性** | 始终反映底层表的最新数据 |
| **查询优化** | ClickHouse 会优化整个查询，视图定义会被展开 |

#### 使用场景

| 场景 | 说明 |
|------|------|
| **简化查询** | 封装复杂的查询逻辑 |
| **权限控制** | 只暴露部分字段给用户 |
| **数据脱敏** | 隐藏敏感字段 |
| **统一接口** | 为不同用户提供统一的数据视图 |

---

### 2.2 物化视图（Materialized View）

#### 基本概念

物化视图**存储实际数据**，数据来源于 SELECT 查询的结果。当源表数据变化时，物化视图会自动更新。

```
源表 INSERT → 触发物化视图更新 → 物化视图存储聚合结果

特点：
- 预计算并存储结果
- 查询速度快
- 占用存储空间
- 数据更新有延迟
```

#### 创建物化视图

```sql
-- 基本语法
CREATE MATERIALIZED VIEW [IF NOT EXISTS] [db.]mv_name [ON CLUSTER cluster]
[TO [db.]target_table]  -- 可选：指定目标表
[ENGINE = engine]        -- 不指定 TO 时必须指定引擎
[PARTITION BY ...]
[ORDER BY ...]
AS SELECT ...

-- 示例 1：自动创建目标表的物化视图
CREATE MATERIALIZED VIEW mm_db.daily_stats_mv ON CLUSTER clicks_cluster_human
ENGINE = ReplicatedSummingMergeTree('/clickhouse/tables/{cluster}/{shard}/daily_stats_mv', '{replica}')
PARTITION BY toYYYYMM(date)
ORDER BY (date, event_type)
AS
SELECT
    toDate(event_time) AS date,
    event_type,
    count() AS event_count,
    uniqState(user_id) AS unique_users_state
FROM mm_db.user_access_log
GROUP BY date, event_type;

-- 示例 2：指定目标表的物化视图（推荐）
-- 先创建目标表
CREATE TABLE mm_db.daily_stats_target ON CLUSTER clicks_cluster_human
(
    date Date,
    event_type String,
    event_count UInt64,
    unique_users AggregateFunction(uniq, UInt64)
)
ENGINE = ReplicatedAggregatingMergeTree('/clickhouse/tables/{cluster}/{shard}/daily_stats_target', '{replica}')
PARTITION BY toYYYYMM(date)
ORDER BY (date, event_type);

-- 再创建物化视图指向目标表
CREATE MATERIALIZED VIEW mm_db.daily_stats_mv ON CLUSTER clicks_cluster_human
TO mm_db.daily_stats_target
AS
SELECT
    toDate(event_time) AS date,
    event_type,
    count() AS event_count,
    uniqState(user_id) AS unique_users_state
FROM mm_db.user_access_log
GROUP BY date, event_type;
```

#### 物化视图引擎选择

| 引擎 | 适用场景 | 说明 |
|------|----------|------|
| **ReplicatedMergeTree** | 简单聚合 | 存储预计算结果 |
| **ReplicatedSummingMergeTree** | 数值求和 | 自动合并相同 key 的数值列 |
| **ReplicatedAggregatingMergeTree** | 复杂聚合 | 存储 AggregateFunction 类型 |
| **ReplicatedReplacingMergeTree** | 最新状态 | 保留最新版本数据 |

#### 聚合函数状态

物化视图中聚合函数需要使用 `-State` 后缀存储状态：

```sql
-- 普通聚合函数 vs 状态函数
count()           → count()           -- 直接存储数值
uniq(user_id)     → uniqState(user_id) -- 存储聚合状态
sum(amount)       → sumState(amount)   -- 存储聚合状态
avg(price)        → avgState(price)    -- 存储聚合状态

-- 查询时使用 -Merge 后缀合并状态
SELECT 
    date,
    uniqMerge(unique_users_state) AS unique_users
FROM mm_db.daily_stats_target
GROUP BY date;
```

#### 常用聚合状态函数

| 聚合函数 | State 函数 | Merge 函数 | 说明 |
|----------|------------|------------|------|
| `count()` | `countState()` | `countMerge()` | 计数 |
| `sum(x)` | `sumState(x)` | `sumMerge()` | 求和 |
| `uniq(x)` | `uniqState(x)` | `uniqMerge()` | 去重计数 |
| `avg(x)` | `avgState(x)` | `avgMerge()` | 平均值 |
| `max(x)` | `maxState(x)` | `maxMerge()` | 最大值 |
| `min(x)` | `minState(x)` | `minMerge()` | 最小值 |

#### 查询物化视图

```sql
-- 直接查询物化视图
SELECT * FROM mm_db.daily_stats_mv LIMIT 10;

-- 查询目标表（推荐）
SELECT 
    date,
    event_type,
    event_count,
    uniqMerge(unique_users_state) AS unique_users
FROM mm_db.daily_stats_target
GROUP BY date, event_type
ORDER BY date DESC;

-- 使用 -Merge 函数查询
SELECT 
    date,
    sumMerge(event_count_state) AS total_events
FROM mm_db.daily_stats_mv
GROUP BY date;
```

#### 物化视图的触发机制

```
物化视图在源表 INSERT 时触发：

INSERT INTO user_access_log VALUES (...)
    ↓
    触发物化视图 daily_stats_mv
    ↓
    执行 SELECT ... FROM user_access_log GROUP BY ...
    ↓
    结果写入物化视图目标表

注意：
- 只有 INSERT 触发，UPDATE/DELETE 不触发
- 历史数据不会自动处理
- 可以手动填充历史数据
```

#### 填充历史数据

```sql
-- 物化视图只处理创建后的新数据
-- 历史数据需要手动插入

-- 方法 1：直接插入目标表
INSERT INTO mm_db.daily_stats_target
SELECT
    toDate(event_time) AS date,
    event_type,
    count() AS event_count,
    uniqState(user_id) AS unique_users_state
FROM mm_db.user_access_log
WHERE event_time < '2025-05-01'
GROUP BY date, event_type;

-- 方法 2：使用 INSERT SELECT 填充
INSERT INTO mm_db.daily_stats_mv
SELECT ... FROM source_table;
```

#### 管理物化视图

```sql
-- 查看物化视图列表
SELECT 
    database,
    name,
    engine,
    as_select
FROM system.tables
WHERE engine = 'MaterializedView';

-- 查看物化视图详情
SHOW CREATE TABLE mm_db.daily_stats_mv;

-- 查看物化视图依赖的源表
SELECT 
    database,
    name,
    source_database,
    source_table
FROM system.view_dependencies
WHERE dependent_database = 'mm_db' AND dependent_table = 'daily_stats_mv';
```

#### 删除物化视图

```sql
-- 删除物化视图
DROP TABLE [IF EXISTS] [db.]mv_name [ON CLUSTER cluster];

-- 示例
DROP TABLE mm_db.daily_stats_mv ON CLUSTER clicks_cluster_human;

-- 注意：如果使用了 TO 指定目标表，删除物化视图不会删除目标表
-- 需要单独删除目标表
DROP TABLE mm_db.daily_stats_target ON CLUSTER clicks_cluster_human;
```

---

### 2.3 普通视图 vs 物化视图

| 对比项 | 普通视图（View） | 物化视图（Materialized View） |
|--------|------------------|-------------------------------|
| **存储数据** | 否 | 是 |
| **查询性能** | 与原查询相同 | 快（预计算） |
| **更新机制** | 实时查询 | INSERT 时自动更新 |
| **存储开销** | 无 | 有 |
| **适用场景** | 简化查询、权限控制 | 预聚合、加速查询 |
| **引擎** | 无 | 需要指定引擎 |
| **集群支持** | 支持 | 支持 |

---

### 2.4 物化视图最佳实践

#### 使用 TO 目标表（推荐）

```sql
-- 推荐：使用 TO 指定目标表
CREATE MATERIALIZED VIEW mv_name TO target_table AS SELECT ...

-- 优点：
-- 1. 目标表结构清晰可控
-- 2. 可以单独管理目标表
-- 3. 删除物化视图不影响数据
-- 4. 可以手动填充历史数据
```

#### 选择合适的引擎

```sql
-- 简单计数/求和 → SummingMergeTree
ENGINE = ReplicatedSummingMergeTree(...)

-- 复杂聚合（uniq、avg等） → AggregatingMergeTree
ENGINE = ReplicatedAggregatingMergeTree(...)

-- 最新状态 → ReplacingMergeTree
ENGINE = ReplicatedReplacingMergeTree(...)
```

#### 分区策略

```sql
-- 物化视图目标表的分区应与查询模式匹配
PARTITION BY toYYYYMM(date)
ORDER BY (date, event_type)
```

#### 监控物化视图

```sql
-- 查看物化视图的数据量
SELECT 
    database,
    table,
    sum(rows) AS rows,
    sum(bytes_on_disk) AS bytes
FROM system.parts
WHERE table = 'daily_stats_mv' AND active = 1
GROUP BY database, table;

-- 查看物化视图的写入延迟
SELECT 
    database,
    table,
    total_rows,
    total_bytes
FROM system.tables
WHERE engine = 'MaterializedView';
```

---

### 2.5 常见问题

#### 物化视图数据不一致

```sql
-- 原因：物化视图只处理 INSERT，不处理 DELETE/UPDATE
-- 解决：重新创建物化视图并填充历史数据

-- 1. 删除旧物化视图
DROP TABLE mm_db.daily_stats_mv;

-- 2. 清空目标表
TRUNCATE TABLE mm_db.daily_stats_target;

-- 3. 重新创建物化视图
CREATE MATERIALIZED VIEW mm_db.daily_stats_mv
TO mm_db.daily_stats_target
AS SELECT ...;

-- 4. 填充历史数据
INSERT INTO mm_db.daily_stats_target
SELECT ... FROM mm_db.user_access_log GROUP BY ...;
```

#### 物化视图查询慢

```sql
-- 原因：目标表未优化（分区、排序键不合理）
-- 解决：优化目标表结构

-- 检查目标表
SHOW CREATE TABLE mm_db.daily_stats_target;

-- 优化：调整分区和排序键
-- 需要重建表
```

#### 物化视图占用空间大

```sql
-- 原因：聚合粒度太细或数据冗余
-- 解决：调整聚合粒度

-- 查看空间占用
SELECT 
    partition,
    sum(bytes_on_disk) AS bytes,
    sum(rows) AS rows
FROM system.parts
WHERE table = 'daily_stats_mv' AND active = 1
GROUP BY partition
ORDER BY partition;

-- 优化：增加聚合维度
-- 例如：从按小时聚合改为按天聚合
```