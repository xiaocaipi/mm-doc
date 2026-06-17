# ClickHouse `rtc.tracks_local` TTL 未清理排查复盘

## 1. 背景

排查对象：`rtc.tracks_all / rtc.tracks_local`

目标数据：

```text
cluster_id   = 316957614615300406
updated_time = 2026-05-15 08:15:01
object_id    = 1d48263a-4ff3-11f1-fc20-00014a00901e
TTL          = 31 天
```

理论过期时间约为：

```text
2026-06-15 08:15:01
```

排查过程中该数据一开始仍能查到，后续自动消失。最终判断为：**ClickHouse 后台自动 TTL merge 清理了该数据**。

---

## 2. 最终结论

```text
1. 目标数据确实已经满足行级 TTL 条件。
2. 目标数据所在 part 最初只是“部分过期”，不是“整块过期”。
3. ClickHouse TTL 不是实时删除，而是在后台 merge 时异步清理。
4. 排查时未发现 readonly、replication queue、mutation、后台资源占用等阻塞。
5. 后续目标旧 part 从 system.parts 中消失，目标数据也查不到。
6. parts_need_ttl_merge 从 3 降到 2，rows / size 下降，earliest_ttl 推进。
7. 用户确认没有人工执行 MATERIALIZE TTL。
8. 因此判断：这次是 ClickHouse 自动 TTL merge 触发并完成。
9. 由于没有 system.part_log / system.text_log，无法看到这次 merge 的精确历史记录。
```

---

## 3. 目标数据定位

### 查询语句

```sql
SELECT
    updated_time,
    object_id,
    _partition_id,
    _part
FROM rtc.tracks_all
WHERE cluster_id = '316957614615300406';
```

### 初始查询结果

```text
updated_time  = 2026-05-15 08:15:01
object_id     = 1d48263a-4ff3-11f1-fc20-00014a00901e
_partition_id = f6b16beb58ea4cf291c183c1363d0e28
_part         = f6b16beb58ea4cf291c183c1363d0e28_0_221251_3490
```

### 解释

```text
_partition_id 用于定位分区。
_part 用于定位底层 MergeTree part。
```

---

## 4. 通过 `_part` 反查真实 partition

### 查询语句

```sql
SELECT
    hostName(),
    partition,
    partition_id,
    name
FROM clusterAllReplicas('clicks_cluster', system.parts)
WHERE database = 'rtc'
  AND table = 'tracks_local'
  AND active = 1
  AND name = 'f6b16beb58ea4cf291c183c1363d0e28_0_221251_3490'
ORDER BY hostName();
```

### 查询结果

```text
hostName()          = clickhouse-olap-0-0 / clickhouse-olap-3-0
partition           = (20260515, 'OBJECT_FACE')
partition_id        = f6b16beb58ea4cf291c183c1363d0e28
name                = f6b16beb58ea4cf291c183c1363d0e28_0_221251_3490
```

### 说明

执行单分区 TTL 物化时，partition 写法应为：

```sql
PARTITION tuple(20260515, 'OBJECT_FACE')
```

---

## 5. 目标 part 的 TTL 状态

### 查询语句

```sql
SELECT
    hostName(),
    now() AS now_time,
    partition,
    partition_id,
    name,
    active,
    rows,
    formatReadableSize(bytes_on_disk) AS size,
    min_time,
    max_time,
    delete_ttl_info_min,
    delete_ttl_info_max,
    delete_ttl_info_min < now() AS has_expired_rows,
    delete_ttl_info_max < now() AS whole_part_expired,
    modification_time
FROM clusterAllReplicas('clicks_cluster', system.parts)
WHERE database = 'rtc'
  AND table = 'tracks_local'
  AND active = 1
  AND name = 'f6b16beb58ea4cf291c183c1363d0e28_0_221251_3490'
ORDER BY hostName() ASC;
```

### 关键结果

```text
hostName()           = clickhouse-olap-0-0 / clickhouse-olap-3-0
now_time             = 2026-06-15 15:48:38
partition            = (20260515, 'OBJECT_FACE')
partition_id         = f6b16beb58ea4cf291c183c1363d0e28
name                 = f6b16beb58ea4cf291c183c1363d0e28_0_221251_3490
active               = 1
rows                 = 2314404
size                 = 517.18 MiB
min_time             = 2026-05-15 00:00:00
max_time             = 2026-05-15 23:59:59
delete_ttl_info_min  = 2026-06-15 04:00:06
delete_ttl_info_max  = 2026-06-15 23:59:59
has_expired_rows     = 1
whole_part_expired   = 0
modification_time    = 2026-06-15 04:00:14 / 04:00:15
```

### 判断

```text
has_expired_rows = 1
=> 这个 part 里已有部分行过期。

whole_part_expired = 0
=> 整个 part 尚未全部过期。

active = 1
=> 旧 part 当时仍然有效，没有被 TTL merge 重写。
```

该 part 大小约 `517.18 MiB`，行数约 `2314404`。  
如果要删除其中部分过期行，ClickHouse 需要重写整个 part。

---

## 6. TTL 相关配置

### 查询语句

```sql
SELECT
    name,
    value,
    changed
FROM system.merge_tree_settings
WHERE name IN
(
    'ttl_only_drop_parts',
    'merge_with_ttl_timeout',
    'max_number_of_merges_with_ttl_in_pool',
    'max_replicated_merges_with_ttl_in_queue'
)
ORDER BY name;
```

### 查询结果

```text
max_replicated_merges_with_ttl_in_queue = 1
max_number_of_merges_with_ttl_in_pool   = 2
merge_with_ttl_timeout                  = 14400
ttl_only_drop_parts                     = 0
```

### 解释

```text
ttl_only_drop_parts = 0
=> 允许通过 TTL merge 重写 part，删除其中部分过期行。

merge_with_ttl_timeout = 14400
=> TTL merge 调度相关间隔约为 4 小时，但不是严格 SLA。

max_number_of_merges_with_ttl_in_pool = 2
=> TTL merge 并发较保守。

max_replicated_merges_with_ttl_in_queue = 1
=> ReplicatedMergeTree TTL merge 入队数量较保守。
```

---

## 7. 查询是否正在执行 merge

### 全表 merge 查询

```sql
SELECT
    hostName(),
    database,
    table,
    partition_id,
    elapsed,
    progress,
    num_parts,
    merge_type,
    merge_algorithm,
    result_part_name,
    rows_read,
    rows_written,
    formatReadableSize(total_size_bytes_compressed) AS total_size
FROM clusterAllReplicas('clicks_cluster', system.merges)
WHERE database = 'rtc'
  AND table = 'tracks_local'
ORDER BY elapsed DESC;
```

### 查询结果

```text
0 rows
```

### 目标分区 merge 查询

```sql
SELECT
    hostName(),
    database,
    table,
    partition_id,
    elapsed,
    progress,
    num_parts,
    merge_type,
    merge_algorithm,
    result_part_name,
    rows_read,
    rows_written,
    formatReadableSize(total_size_bytes_compressed) AS total_size
FROM clusterAllReplicas('clicks_cluster', system.merges)
WHERE database = 'rtc'
  AND table = 'tracks_local'
  AND partition_id = 'f6b16beb58ea4cf291c183c1363d0e28'
ORDER BY elapsed DESC;
```

### 查询结果

```text
0 rows
```

### 解释

```text
system.merges 只显示正在执行的 merge。
当时 tracks_local 全表没有正在执行的 merge。
目标分区也没有正在执行的 merge / TTL merge。
```

---

## 8. 查询是否有 replication_queue 排队

### 查询语句

```sql
SELECT
    hostName(),
    type,
    count() AS tasks,
    min(create_time) AS oldest_task_time,
    max(dateDiff('minute', create_time, now())) AS oldest_age_min,
    sum(is_currently_executing) AS executing,
    sum(num_tries) AS total_tries,
    sum(num_postponed) AS total_postponed,
    anyIf(postpone_reason, length(postpone_reason) > 0) AS sample_postpone_reason,
    anyIf(last_exception, length(last_exception) > 0) AS sample_last_exception
FROM clusterAllReplicas('clicks_cluster', system.replication_queue)
WHERE database = 'rtc'
  AND table = 'tracks_local'
GROUP BY
    hostName(),
    type
ORDER BY hostName(), tasks DESC;
```

### 查询结果

```text
0 rows
```

### 明细查询

```sql
SELECT
    hostName(),
    type,
    create_time,
    dateDiff('minute', create_time, now()) AS age_min,
    source_replica,
    new_part_name,
    parts_to_merge,
    is_currently_executing,
    num_tries,
    num_postponed,
    last_attempt_time,
    postpone_reason,
    last_exception
FROM clusterAllReplicas('clicks_cluster', system.replication_queue)
WHERE database = 'rtc'
  AND table = 'tracks_local'
ORDER BY create_time ASC
LIMIT 100;
```

### 查询结果

```text
0 rows
```

### 解释

```text
没有 GET_PART。
没有 MERGE_PARTS。
没有 MUTATE_PART。
没有 DROP_RANGE。
```

因此不是“任务已经排队但没执行”。

---

## 9. 查询是否有 MATERIALIZE TTL mutation

### 查询语句

```sql
SELECT
    hostName(),
    database,
    table,
    mutation_id,
    command,
    create_time,
    is_done,
    parts_to_do,
    latest_failed_part,
    latest_fail_time,
    latest_fail_reason
FROM clusterAllReplicas('clicks_cluster', system.mutations)
WHERE database = 'rtc'
  AND table = 'tracks_local'
  AND command ILIKE '%MATERIALIZE TTL%'
ORDER BY create_time DESC;
```

### 查询结果

```text
0 rows
```

### 解释

```text
没有手动 MATERIALIZE TTL mutation。
没有 mutation 正在处理该 TTL。
```

---

## 10. 副本状态查询

### 查询语句

```sql
SELECT
    hostName(),
    table,
    is_readonly,
    is_session_expired,
    queue_size,
    merges_in_queue,
    absolute_delay
FROM clusterAllReplicas('clicks_cluster', system.replicas)
WHERE database = 'rtc'
  AND table = 'tracks_local'
ORDER BY hostName();
```

### 查询结果

```text
所有副本：
is_readonly        = 0
is_session_expired = 0
queue_size         = 0
merges_in_queue    = 0
absolute_delay     = 0
```

### 解释

```text
不是 readonly。
不是 Keeper/ZooKeeper session 过期。
不是复制队列阻塞。
```

曾经看到过：

```text
last_queue_update_exception:
Code: 242. DB::Exception: Table is in readonly mode
```

但当前关键字段已恢复正常：

```text
is_readonly = 0
is_session_expired = 0
queue_size = 0
```

因此判断该 readonly 信息是历史异常，不是当前阻塞原因。

---

## 11. 全局 merge 查询

### 查询语句

```sql
SELECT
    hostName(),
    database,
    table,
    count()
FROM clusterAllReplicas('clicks_cluster', system.merges)
GROUP BY
    hostName(),
    database,
    table;
```

### 查询结果

```text
0 rows
```

### 解释

```text
整个 clicks_cluster 当时没有任何正在执行的 merge。
因此不是其他表正在执行 merge 抢占资源。
```

---

## 12. 后台线程池指标

### 查询语句

```sql
SELECT
    hostName(),
    metric,
    value
FROM clusterAllReplicas('clicks_cluster', system.metrics)
WHERE metric IN
(
    'BackgroundFetchesPoolTask',
    'BackgroundMergesAndMutationsPoolTask',
    'BackgroundSchedulePoolTask'
)
ORDER BY
    hostName() ASC,
    metric ASC;
```

### 查询结果摘要

```text
clickhouse-olap-0-0:
  BackgroundFetchesPoolTask            = 0
  BackgroundMergesAndMutationsPoolTask = 0
  BackgroundSchedulePoolTask           = 0

clickhouse-olap-3-0:
  BackgroundFetchesPoolTask            = 0
  BackgroundMergesAndMutationsPoolTask = 0
  BackgroundSchedulePoolTask           = 0

clickhouse-olap-4-0:
  BackgroundFetchesPoolTask            = 8
  BackgroundMergesAndMutationsPoolTask = 5
  BackgroundSchedulePoolTask           = 5
```

### 解释

```text
目标数据所在副本是 clickhouse-olap-0-0 / clickhouse-olap-3-0。
这两个目标副本后台池任务数为 0。
因此目标 shard 不是资源被占用。
```

---

## 13. TTL 候选 part 汇总变化

### 查询语句

```sql
SELECT
    hostName(),
    count() AS active_parts,
    sum(rows) AS rows,
    formatReadableSize(sum(bytes_on_disk)) AS size,
    sum(delete_ttl_info_min < now()) AS parts_need_ttl_merge,
    sum(delete_ttl_info_max < now()) AS parts_whole_expired,
    minIf(delete_ttl_info_min, delete_ttl_info_min > toDateTime(0)) AS earliest_ttl,
    max(delete_ttl_info_max) AS latest_ttl,
    now() AS now_time
FROM clusterAllReplicas('clicks_cluster', system.parts)
WHERE database = 'rtc'
  AND table = 'tracks_local'
  AND active = 1
GROUP BY hostName()
ORDER BY parts_need_ttl_merge DESC;
```

### 清理前结果

```text
clickhouse-olap-3-0:
  active_parts         = 94
  rows                 = 16243557
  size                 = 3.75 GiB
  parts_need_ttl_merge = 3
  parts_whole_expired  = 0
  earliest_ttl         = 2026-06-15 04:00:06
  latest_ttl           = 2026-07-15 23:59:59
  now_time             = 2026-06-15 15:38:03

clickhouse-olap-0-0:
  active_parts         = 94
  rows                 = 16243557
  size                 = 3.75 GiB
  parts_need_ttl_merge = 3
  parts_whole_expired  = 0
  earliest_ttl         = 2026-06-15 04:00:06
  latest_ttl           = 2026-07-15 23:59:59
  now_time             = 2026-06-15 15:38:03
```

### 清理后结果

```text
clickhouse-olap-3-0:
  active_parts         = 91
  rows                 = 14901888
  size                 = 3.44 GiB
  parts_need_ttl_merge = 2
  parts_whole_expired  = 0
  earliest_ttl         = 2026-06-15 16:01:22
  latest_ttl           = 2026-07-15 23:59:59
  now_time             = 2026-06-15 16:03:51

clickhouse-olap-0-0:
  active_parts         = 91
  rows                 = 14901888
  size                 = 3.44 GiB
  parts_need_ttl_merge = 2
  parts_whole_expired  = 0
  earliest_ttl         = 2026-06-15 16:01:22
  latest_ttl           = 2026-07-15 23:59:59
  now_time             = 2026-06-15 16:03:51
```

### 变化解读

```text
active_parts: 94 -> 91
rows: 16243557 -> 14901888
size: 3.75 GiB -> 3.44 GiB
parts_need_ttl_merge: 3 -> 2
earliest_ttl: 2026-06-15 04:00:06 -> 2026-06-15 16:01:22
```

说明最早 TTL 到期的 part 已经被处理，目标数据所在旧 part 被清理。

---

## 14. 旧 part 消失

### 查询语句

```sql
SELECT
    hostName(),
    now() AS now_time,
    partition,
    partition_id,
    name,
    active,
    rows,
    formatReadableSize(bytes_on_disk) AS size,
    min_time,
    max_time,
    delete_ttl_info_min,
    delete_ttl_info_max,
    delete_ttl_info_min < now() AS has_expired_rows,
    delete_ttl_info_max < now() AS whole_part_expired,
    modification_time
FROM clusterAllReplicas('clicks_cluster', system.parts)
WHERE database = 'rtc'
  AND table = 'tracks_local'
  AND name = 'f6b16beb58ea4cf291c183c1363d0e28_0_221251_3490'
ORDER BY hostName() ASC;
```

### 查询结果

```text
0 rows
```

### 解释

该查询没有加 `active = 1` 条件，因此说明：

```text
旧 part 不只是 inactive，而是已经从 system.parts 中不可见。
```

这表示旧 part 已经被替换并由清理线程移除。

---

## 15. 目标数据消失

### 查询语句

```sql
SELECT
    updated_time,
    object_id,
    _partition_id,
    _part
FROM rtc.tracks_all
WHERE cluster_id = '316957614615300406';
```

### 清理后结果

```text
0 rows
```

### 解释

```text
目标过期数据已被 TTL 清理。
```

---

## 16. 当前剩余过期 part

### 查询语句

```sql
SELECT
    hostName(),
    partition,
    partition_id,
    name,
    rows,
    formatReadableSize(bytes_on_disk) AS size,
    min_time,
    max_time,
    delete_ttl_info_min,
    delete_ttl_info_max,
    delete_ttl_info_min < now() AS has_expired_rows,
    delete_ttl_info_max < now() AS whole_part_expired,
    modification_time
FROM clusterAllReplicas('clicks_cluster', system.parts)
WHERE database = 'rtc'
  AND table = 'tracks_local'
  AND active = 1
  AND delete_ttl_info_min < now()
ORDER BY
    delete_ttl_info_min ASC,
    name ASC;
```

### 查询结果摘要

```text
共 6 行，分布在 clickhouse-olap-0-0 / clickhouse-olap-3-0。
由于两个节点是同一 shard 的副本，因此逻辑上是 3 个 part。
```

剩余过期 part：

```text
1. 大 part：
   name                = f6b16..._0_222410_3492
   rows                = 970607
   size                = 202.28 MiB
   delete_ttl_info_min = 2026-06-15 16:01:22
   delete_ttl_info_max = 2026-06-15 23:59:59
   has_expired_rows    = 1
   whole_part_expired  = 0

2. 小 part：
   name                = f6b16..._222443_222443_0
   rows                = 2
   size                = 2.33 KiB
   delete_ttl_info_min = 2026-06-15 16:22:21
   delete_ttl_info_max = 2026-06-15 16:23:08
   has_expired_rows    = 1
   whole_part_expired  = 1

3. 小 part：
   name                = f6b16..._222445_222445_0
   rows                = 2
   size                = 2.30 KiB
   delete_ttl_info_min = 2026-06-15 16:15:45
   delete_ttl_info_max = 2026-06-15 16:18:01
   has_expired_rows    = 1
   whole_part_expired  = 1
```

---

## 17. 为什么之前没立刻清理

当时状态：

```text
has_expired_rows = 1
whole_part_expired = 0
system.merges = 0
system.replication_queue = 0
system.mutations = 0
目标副本后台池空闲
replicas 正常
```

说明：

```text
不是正在执行。
不是排队。
不是 mutation。
不是 readonly。
不是资源占用。
```

真实原因是：

```text
ClickHouse 自动 TTL merge selector 当时尚未选中这个“部分过期”的大 part。
```

ClickHouse TTL 是后台异步清理，不是实时删除。过期数据只有在相关 part 被 TTL merge / merge 处理后才会物理删除。

---

## 18. 为什么后来会清理

后来状态变化：

```text
目标数据消失。
旧 part 从 system.parts 中消失。
parts_need_ttl_merge 从 3 降到 2。
rows / size 下降。
earliest_ttl 从 04:00:06 推进到 16:01:22。
没有人工 MATERIALIZE TTL。
```

因此判断：

```text
ClickHouse 后台自动 TTL merge 在观察过程中被调度并执行完成。
```

没有在 `system.merges` 中看到，是因为：

```text
system.merges 只显示正在执行中的 merge。
执行完成后不会保留历史。
如果 merge 执行较快，查询时可能抓不到。
```

---

## 19. 为什么看不到这次 merge 记录

当前环境没有：

```text
system.part_log
system.text_log
```

因此无法查询：

```text
具体什么时候 merge
merge_reason 是否为 TTLDeleteMerge
源 part 是哪些
新 part 是哪个
duration_ms 是多少
```

只能通过前后状态变化判断本次为自动 TTL merge。

如果以后需要追溯历史，需要开启或保留：

```text
1. system.part_log
2. system.text_log
3. query_log
```

---

## 20. 可选：手动处理命令说明

如果未来生产必须手动清理指定分区，建议只对目标 shard 的一个副本执行一次，不要全表执行。

目标 shard：

```text
clickhouse-olap-0-0 / clickhouse-olap-3-0
```

手动命令：

```sql
SET mutations_sync = 0;

ALTER TABLE rtc.tracks_local
MATERIALIZE TTL IN PARTITION tuple(20260515, 'OBJECT_FACE');
```

含义：

```text
SET mutations_sync = 0
=> 异步提交 mutation，不等待执行完成。

MATERIALIZE TTL
=> 强制对已有数据应用表 TTL 规则。

IN PARTITION tuple(20260515, 'OBJECT_FACE')
=> 只处理目标分区。
```

注意：

```text
不要在 clickhouse-olap-0-0 和 clickhouse-olap-3-0 都执行。
ReplicatedMergeTree 在同一 shard 一个副本提交后，另一个副本会同步处理。
不要加 ON CLUSTER，除非确认要所有 shard 都处理这个分区。
```

查看 mutation：

```sql
SELECT
    hostName(),
    mutation_id,
    command,
    create_time,
    is_done,
    parts_to_do,
    latest_failed_part,
    latest_fail_time,
    latest_fail_reason
FROM clusterAllReplicas('clicks_cluster', system.mutations)
WHERE database = 'rtc'
  AND table = 'tracks_local'
ORDER BY create_time DESC;
```

---

## 21. 后续巡检 SQL

### 查还有哪些 part 有过期行

```sql
SELECT
    hostName(),
    partition,
    partition_id,
    name,
    rows,
    formatReadableSize(bytes_on_disk) AS size,
    delete_ttl_info_min,
    delete_ttl_info_max,
    delete_ttl_info_min < now() AS has_expired_rows,
    delete_ttl_info_max < now() AS whole_part_expired,
    modification_time
FROM clusterAllReplicas('clicks_cluster', system.parts)
WHERE database = 'rtc'
  AND table = 'tracks_local'
  AND active = 1
  AND delete_ttl_info_min < now()
ORDER BY
    delete_ttl_info_min ASC,
    name ASC;
```

### 按 host 汇总 TTL 候选

```sql
SELECT
    hostName(),
    count() AS active_parts,
    sum(rows) AS rows,
    formatReadableSize(sum(bytes_on_disk)) AS size,
    sum(delete_ttl_info_min < now()) AS parts_need_ttl_merge,
    sum(delete_ttl_info_max < now()) AS parts_whole_expired,
    minIf(delete_ttl_info_min, delete_ttl_info_min > toDateTime(0)) AS earliest_ttl,
    max(delete_ttl_info_max) AS latest_ttl,
    now() AS now_time
FROM clusterAllReplicas('clicks_cluster', system.parts)
WHERE database = 'rtc'
  AND table = 'tracks_local'
  AND active = 1
GROUP BY hostName()
ORDER BY parts_need_ttl_merge DESC;
```

### 查当前是否有 merge

```sql
SELECT
    hostName(),
    database,
    table,
    partition_id,
    elapsed,
    progress,
    merge_type,
    result_part_name
FROM clusterAllReplicas('clicks_cluster', system.merges)
WHERE database = 'rtc'
  AND table = 'tracks_local'
ORDER BY elapsed DESC;
```

### 查是否有 replication queue

```sql
SELECT
    hostName(),
    type,
    count() AS tasks,
    min(create_time) AS oldest_task_time,
    max(dateDiff('minute', create_time, now())) AS oldest_age_min,
    sum(is_currently_executing) AS executing,
    sum(num_postponed) AS total_postponed,
    anyIf(postpone_reason, length(postpone_reason) > 0) AS sample_postpone_reason,
    anyIf(last_exception, length(last_exception) > 0) AS sample_last_exception
FROM clusterAllReplicas('clicks_cluster', system.replication_queue)
WHERE database = 'rtc'
  AND table = 'tracks_local'
GROUP BY
    hostName(),
    type
ORDER BY hostName(), tasks DESC;
```
