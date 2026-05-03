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