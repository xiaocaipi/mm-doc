# ClickHouse `rtc.tracks_local` TTL 未清理生产排查 Runbook

## 0. 当前结论摘要

本次排查目标是：`rtc.tracks_all` 中一条数据已经超过 `31 天 TTL`，但仍能查询到。

目标数据：

```text
cluster_id   = 316957614615300406
updated_time = 2026-05-15 08:15:01
object_id    = 1d48263a-4ff3-11f1-fc20-00014a00901e
```

已定位到该数据所在底层 part：

```text
table         = rtc.tracks_local
partition     = (20260515, 'OBJECT_FACE')
partition_id  = f6b16beb58ea4cf291c183c1363d0e28
part          = f6b16beb58ea4cf291c183c1363d0e28_0_221251_3490
```

该 part 的 TTL 信息：

```text
rows                = 2314404
min_time            = 2026-05-15 00:00:00
max_time            = 2026-05-15 23:59:59
delete_ttl_info_min = 2026-06-15 04:00:06
delete_ttl_info_max = 2026-06-15 23:59:59
now()               = 2026-06-15 12:14:57
```

判断：

```text
delete_ttl_info_min < now()  => 该 part 中已有部分行过期
delete_ttl_info_max > now()  => 整个 part 尚未全部过期
```

TTL 设置：

```text
ttl_only_drop_parts                     = 0
merge_with_ttl_timeout                  = 14400
max_number_of_merges_with_ttl_in_pool   = 2
max_replicated_merges_with_ttl_in_queue = 1
```

因此当前判断是：

```text
1. 数据本身已经满足 TTL 条件。
2. 该数据所在 part 已部分过期。
3. ttl_only_drop_parts = 0，ClickHouse 理论上允许通过 TTL merge 删除 part 内部的过期行。
4. 当前所有 replicas 不是 readonly，queue_size = 0，merges_in_queue = 0。
5. 普通 merge 已经可以执行，但目前看到的是 Regular merge，不是 TTL merge，也不是目标分区。
6. 当前问题更像是 TTL merge 尚未被调度到目标分区，或 TTL merge 被限流 / 调度延迟。
```

---

## 1. 生产环境执行原则

以下 SQL 分为两类：

### 只读查询

只读查询用于确认状态，生产环境可优先执行。

### 操作命令

操作命令会改变 ClickHouse 后台 merge / TTL merge 状态，或触发 part 重写。执行前需要确认窗口期和资源余量。

建议处理顺序：

```text
1. 先执行只读查询，确认 TTL 候选 part、replica 状态、merge 状态。
2. 如果怀疑 merge / TTL merge 被停止，先执行 SYSTEM START MERGES / SYSTEM START TTL MERGES。
3. 如果 START 后仍没有 TTL merge，并且业务必须立即清理该分区，再执行单分区 MATERIALIZE TTL。
4. 不建议直接全表 MATERIALIZE TTL 或 OPTIMIZE FINAL。
```

---

# A. 只读查询 SQL

## A1. 确认目标数据是否仍存在

```sql
SELECT
    updated_time,
    object_id,
    _partition_id,
    _part
FROM rtc.tracks_all
WHERE cluster_id = '316957614615300406';
```

预期判断：

```text
如果仍返回数据，说明 TTL 还没有实际清理。
如果无返回，说明该数据已经被 TTL 或其他方式清理。
```

---

## A2. 从底层 local 表确认数据所在副本、分区和 part

```sql
SELECT
    hostName(),
    updated_time,
    object_id,
    _partition_id,
    _part
FROM clusterAllReplicas('clicks_cluster', rtc.tracks_local)
WHERE cluster_id = '316957614615300406'
ORDER BY hostName();
```

重点字段：

```text
hostName()      数据实际所在副本
_partition_id  所在分区 ID
_part          所在 part 名
```

---

## A3. 查看表 TTL 定义

```sql
SELECT
    hostName(),
    database,
    name,
    engine,
    create_table_query
FROM clusterAllReplicas('clicks_cluster', system.tables)
WHERE database = 'rtc'
  AND name IN ('tracks_local', 'tracks_all')
FORMAT Vertical;
```

重点确认：

```text
1. TTL 是否配置在 tracks_local 上。
2. TTL 是否基于 updated_time。
3. TTL 是否为 updated_time + INTERVAL 31 DAY 或等价表达式。
4. tracks_all 是否只是 Distributed 表。
```

---

## A4. 查看目标 part 的 TTL 元信息

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
ORDER BY hostName();
```

判断标准：

```text
has_expired_rows = 1 且 whole_part_expired = 0
=> part 内部已有部分行过期，但整个 part 还没全部过期，需要 TTL merge 重写 part 才能删除过期行。

whole_part_expired = 1
=> 整个 part 都已过期，理论上更容易被 TTL drop / TTL merge 清理。

delete_ttl_info_min / delete_ttl_info_max 为 1970 或异常
=> 需要检查 TTL 定义是否正确、TTL 是否 materialize、是否查错表。
```

---

## A5. 查看目标分区 TTL 候选 part 数量

```sql
SELECT
    hostName(),
    partition,
    count() AS active_parts,
    sum(rows) AS rows,
    formatReadableSize(sum(bytes_on_disk)) AS size,
    sum(delete_ttl_info_min < now()) AS parts_has_expired_rows,
    sum(delete_ttl_info_max < now()) AS whole_expired_parts,
    minIf(delete_ttl_info_min, delete_ttl_info_min > toDateTime(0)) AS min_ttl,
    max(delete_ttl_info_max) AS max_ttl,
    now() AS now_time
FROM clusterAllReplicas('clicks_cluster', system.parts)
WHERE database = 'rtc'
  AND table = 'tracks_local'
  AND active = 1
  AND partition = tuple(20260515, 'OBJECT_FACE')
GROUP BY
    hostName(),
    partition
ORDER BY hostName();
```

判断标准：

```text
parts_has_expired_rows > 0
=> 该分区存在需要 TTL merge 的 part。

whole_expired_parts > 0
=> 该分区存在整块已过期的 part。

parts_has_expired_rows > 0，但长期没有 TTL merge
=> TTL merge 可能没有正常调度，或被限流 / 资源限制。
```

---

## A6. 全表维度查看 TTL 候选 part 积压

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

判断标准：

```text
parts_need_ttl_merge 很多
=> TTL 候选 part 积压较多。

parts_need_ttl_merge 很多，但 system.merges 中没有 TTL merge
=> TTL merge 没正常跑，或被调度策略 / 限流压住。
```

---

## A7. 查看 TTL 相关 MergeTree 设置

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

判断标准：

```text
ttl_only_drop_parts = 1
=> ClickHouse 更倾向于只删除整块都过期的 part，部分过期行可能不会被立即重写删除。

ttl_only_drop_parts = 0
=> 允许通过 TTL merge 重写 part，删除 part 内部过期行。

merge_with_ttl_timeout = 14400
=> TTL merge 调度间隔约为 4 小时，不是到期立即删除。

max_number_of_merges_with_ttl_in_pool 较小
=> TTL merge 并发较保守。

max_replicated_merges_with_ttl_in_queue 较小
=> ReplicatedMergeTree 中 TTL merge 入队较保守。
```

---

## A8. 查看当前是否有 `tracks_local` merge 正在执行

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

判断标准：

```text
0 rows
=> 当前 tracks_local 没有任何 merge，更没有 TTL merge。

merge_type = Regular
=> 普通 merge，不是 TTL merge。

merge_type 或 part_log.merge_reason 中出现 TTL 相关信息
=> TTL merge 正在执行或曾经执行。
```

---

## A9. 只看目标分区当前是否在 merge

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

判断标准：

```text
有结果
=> 目标分区正在 merge。

无结果
=> 目标分区当前没有 merge。
```

---

## A10. 查看最近 24 小时 TTL merge 历史

```sql
SELECT
    hostname,
    event_time,
    event_type,
    merge_reason,
    partition_id,
    part_name,
    rows,
    duration_ms,
    error,
    exception
FROM clusterAllReplicas('clicks_cluster', system.part_log)
WHERE database = 'rtc'
  AND table = 'tracks_local'
  AND event_time > now() - INTERVAL 24 HOUR
  AND event_type = 'MergeParts'
  AND toString(merge_reason) ILIKE '%TTL%'
ORDER BY event_time DESC
LIMIT 100;
```

判断标准：

```text
有记录且 error = 0
=> 最近 TTL merge 执行过。

无记录
=> 最近 24 小时没有 TTL merge。若同时存在 TTL 候选 part，可判断 TTL merge 没有正常跑起来。

有记录但 error != 0 或 exception 非空
=> TTL merge 执行失败，需要看 exception。
```

---

## A11. 查看目标分区最近 24 小时 merge 历史

```sql
SELECT
    hostname,
    event_time,
    event_type,
    merge_reason,
    partition_id,
    part_name,
    rows,
    duration_ms,
    error,
    exception
FROM clusterAllReplicas('clicks_cluster', system.part_log)
WHERE database = 'rtc'
  AND table = 'tracks_local'
  AND event_time > now() - INTERVAL 24 HOUR
  AND event_type = 'MergeParts'
  AND partition_id = 'f6b16beb58ea4cf291c183c1363d0e28'
ORDER BY event_time DESC
LIMIT 100;
```

判断标准：

```text
merge_reason = Regular
=> 目标分区最近只有普通 merge。

merge_reason 包含 TTL
=> 目标分区已经执行过 TTL merge。

无记录
=> 目标分区最近 24 小时没有 merge。
```

---

## A12. 查看副本状态是否正常

```sql
SELECT
    hostName(),
    database,
    table,
    zookeeper_path,
    replica_name,
    is_leader,
    can_become_leader,
    is_readonly,
    is_session_expired,
    queue_size,
    inserts_in_queue,
    merges_in_queue,
    part_mutations_in_queue,
    log_max_index,
    log_pointer,
    log_max_index - log_pointer AS log_lag,
    absolute_delay,
    total_replicas,
    active_replicas,
    last_queue_update,
    last_queue_update_exception,
    zookeeper_exception
FROM clusterAllReplicas('clicks_cluster', system.replicas)
WHERE database = 'rtc'
  AND table = 'tracks_local'
ORDER BY hostName()
FORMAT Vertical;
```

判断标准：

```text
is_readonly = 1
=> 副本只读，TTL merge / part 替换可能无法正常执行。

is_session_expired = 1
=> Keeper/ZooKeeper session 异常。

queue_size > 0
=> replication queue 有积压。

merges_in_queue > 0
=> 有 merge 任务在 replication queue 里等待。

log_lag 较大
=> 副本消费复制日志落后。

last_queue_update_exception 包含 readonly，但 is_readonly = 0
=> 多数情况下是历史异常残留，当前是否 readonly 以 is_readonly 字段为准。
```

---

## A13. 快速查看所有副本 readonly / queue 状态

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

判断标准：

```text
所有副本 is_readonly = 0，is_session_expired = 0，queue_size = 0，merges_in_queue = 0
=> 当前不是 replica / replication queue 卡住。
```

---

## A14. 查看 replication queue 汇总

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

判断标准：

```text
GET_PART 很多
=> 副本在拉取 part，TTL merge 可能等待复制完成。

MERGE_PARTS 很多
=> merge 队列积压。

total_postponed 很大
=> 任务被反复推迟。

sample_postpone_reason / sample_last_exception 非空
=> 直接查看原因，例如磁盘不足、part 缺失、Keeper 异常等。
```

---

## A15. 查看 replication queue 明细

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

重点字段：

```text
postpone_reason
last_exception
num_postponed
is_currently_executing
```

---

## A16. 查看后台 merge / mutation / schedule 池

```sql
SELECT
    hostName(),
    metric,
    value
FROM clusterAllReplicas('clicks_cluster', system.metrics)
WHERE metric IN
(
    'BackgroundMergesAndMutationsPoolTask',
    'BackgroundMergesAndMutationsPoolSize',
    'BackgroundSchedulePoolTask',
    'BackgroundSchedulePoolSize',
    'BackgroundFetchesPoolTask',
    'BackgroundFetchesPoolSize'
)
ORDER BY hostName(), metric;
```

判断标准：

```text
BackgroundMergesAndMutationsPoolTask 接近 BackgroundMergesAndMutationsPoolSize
=> merge / mutation 后台池可能满，TTL merge 等资源。

BackgroundSchedulePoolTask 接近 BackgroundSchedulePoolSize
=> 后台调度池可能紧张。

BackgroundFetchesPoolTask 接近 BackgroundFetchesPoolSize
=> fetch 线程池可能紧张。
```

---

## A17. 查看磁盘空间

```sql
SELECT
    hostName(),
    name,
    path,
    formatReadableSize(free_space) AS free,
    formatReadableSize(total_space) AS total,
    round(free_space / total_space * 100, 2) AS free_pct
FROM clusterAllReplicas('clicks_cluster', system.disks)
ORDER BY free_pct ASC;
```

判断标准：

```text
free_pct 很低
=> merge / TTL merge 可能因为空间不足无法执行或被推迟。
```

---

## A18. 查看是否有人执行过 STOP / START MERGES

如果开启了 `system.query_log`，执行：

```sql
SELECT
    hostName(),
    event_time,
    user,
    query
FROM clusterAllReplicas('clicks_cluster', system.query_log)
WHERE event_time > now() - INTERVAL 7 DAY
  AND type = 'QueryFinish'
  AND (
        query ILIKE '%STOP MERGES%'
     OR query ILIKE '%START MERGES%'
     OR query ILIKE '%STOP TTL MERGES%'
     OR query ILIKE '%START TTL MERGES%'
  )
ORDER BY event_time DESC
LIMIT 100;
```

判断标准：

```text
有 STOP MERGES / STOP TTL MERGES，但没有后续 START
=> merge / TTL merge 可能曾被人为停止。

无记录
=> 不能完全证明没停过，可能 query_log 没开或日志过期。
```

---

## A19. 如果执行 MATERIALIZE TTL，查看 mutation 状态

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
ORDER BY create_time DESC;
```

判断标准：

```text
is_done = 0 且 parts_to_do 下降
=> mutation 正在处理。

is_done = 0 且 parts_to_do 长时间不变
=> mutation 可能卡住。

latest_fail_reason 非空
=> mutation 失败，需要处理失败原因。
```

---

## A20. 最终验证目标数据是否已清理

```sql
SELECT
    updated_time,
    object_id,
    _partition_id,
    _part
FROM rtc.tracks_all
WHERE cluster_id = '316957614615300406';
```

如果还有数据，再查底层副本：

```sql
SELECT
    hostName(),
    updated_time,
    object_id,
    _partition_id,
    _part
FROM clusterAllReplicas('clicks_cluster', rtc.tracks_local)
WHERE cluster_id = '316957614615300406'
ORDER BY hostName();
```

判断标准：

```text
无返回
=> 目标数据已清理。

仍有返回
=> 目标数据仍未清理，需要看其是否换到了新的 part，以及新 part 的 delete_ttl_info_min / delete_ttl_info_max。
```

---

# B. 操作命令

## B1. 恢复普通 merge / TTL merge 开关

用途：排除 `SYSTEM STOP MERGES` 或 `SYSTEM STOP TTL MERGES` 导致后台 merge 不跑。

```sql
SYSTEM START MERGES ON CLUSTER clicks_cluster rtc.tracks_local;
SYSTEM START TTL MERGES ON CLUSTER clicks_cluster rtc.tracks_local;
```

说明：

```text
这两条不是强制重写全表。
这两条不是立刻删除数据。
这两条只是恢复普通 merge 和 TTL merge 后台调度开关。
如果本来就是 started 状态，通常没有额外影响。
```

执行后观察：

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

---

## B2. 强制只对目标分区应用 TTL

用途：如果业务需要立即清理目标分区中的过期数据，且自动 TTL merge 长时间不执行，可以只对目标分区执行 TTL 物化。

目标分区：

```text
partition = (20260515, 'OBJECT_FACE')
```

执行：

```sql
ALTER TABLE rtc.tracks_local
ON CLUSTER clicks_cluster
MATERIALIZE TTL IN PARTITION tuple(20260515, 'OBJECT_FACE');
```

风险说明：

```text
该命令会重写相关 part。
会带来 IO / CPU / 磁盘压力。
建议只对目标分区执行，不要直接全表执行。
执行后需要观察 system.mutations。
```

观察 mutation：

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
ORDER BY create_time DESC;
```

---

## B3. 不建议直接执行的命令

除非已经评估资源和影响，否则不建议直接执行：

```sql
ALTER TABLE rtc.tracks_local
ON CLUSTER clicks_cluster
MATERIALIZE TTL;
```

不建议：

```sql
OPTIMIZE TABLE rtc.tracks_local
ON CLUSTER clicks_cluster
FINAL;
```

原因：

```text
全表 MATERIALIZE TTL 会重写大量 part，生产环境风险较高。
全表 OPTIMIZE FINAL 会产生巨大 CPU / IO / 磁盘压力。
当前更安全的方式是只处理目标分区。
```

---

# C. 如何最终判断是否“卡住”

## C1. 不一定算卡住的情况

```text
1. delete_ttl_info_min 刚刚小于 now()。
2. merge_with_ttl_timeout = 14400，TTL merge 本身不是实时执行。
3. system.part_log 最近有 TTL merge 成功记录。
4. system.merges 偶尔能看到 TTL merge。
5. TTL 候选 part 数量在下降。
```

## C2. 可以认为 TTL merge 没正常调度 / 卡住的情况

满足以下多项时，可以认为 TTL merge 没正常跑起来：

```text
1. delete_ttl_info_min 已经早于 now() 超过 merge_with_ttl_timeout。
2. ttl_only_drop_parts = 0。
3. system.parts 中 parts_need_ttl_merge > 0。
4. system.merges 长时间没有 tracks_local 的 TTL merge。
5. system.part_log 24 小时内没有 TTL merge 记录。
6. system.replicas 全部 is_readonly = 0，queue_size = 0。
7. 后台 merge pool 没有被打满。
8. 过期 parts 数量长期不下降。
```

结合本次已知结果，目前可以判断为：

```text
不是 readonly 卡住。
不是 replication queue 卡住。
不是 ttl_only_drop_parts 导致必须等整块 part 过期。
普通 merge 已恢复执行。
但 TTL merge 尚未跑到目标分区。
```

---

# D. 推荐执行顺序

## 第 1 步：确认目标数据仍存在

执行 A1、A2。

## 第 2 步：确认目标 part 是否已经 TTL 过期

执行 A4、A5。

## 第 3 步：确认 TTL 配置

执行 A7。

## 第 4 步：确认是否有 TTL merge 在跑

执行 A8、A9。

## 第 5 步：确认最近是否有 TTL merge 历史

执行 A10、A11。

## 第 6 步：确认副本和队列状态

执行 A13、A14、A15。

## 第 7 步：确认后台池和磁盘

执行 A16、A17。

## 第 8 步：恢复 merge 开关

执行 B1。

## 第 9 步：观察 2～5 分钟

再次执行 A8、A10。

## 第 10 步：如果仍未清理且业务要求立即处理

执行 B2，只对分区 `tuple(20260515, 'OBJECT_FACE')` 物化 TTL。

## 第 11 步：观察 mutation 并最终验证

执行 A19、A20。
