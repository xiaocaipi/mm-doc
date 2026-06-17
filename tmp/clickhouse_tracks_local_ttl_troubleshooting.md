# ClickHouse `tracks_local` TTL 未清理排查记录

## 1. 背景

排查目标：`rtc.tracks_local` / `rtc.tracks_all` 中有一条数据按 TTL 规则应被清理，但当前仍然可以查询到。

目标数据：

```sql
SELECT updated_time, object_id
FROM rtc.tracks_all
WHERE cluster_id = '316957614615300406';
```

查询结果：

```text
updated_time = 2026-05-15 08:15:01
object_id    = 1d48263a-4ff3-11f1-fc20-00014a00901e
```

表 TTL 规则：`31 天`。

因此该数据理论过期时间约为：

```text
2026-06-15 08:15:01
```

后续查询中 `now()` 为：

```text
2026-06-15 12:14:57
```

所以该行本身已经满足 TTL 删除条件。

---

## 2. 定位数据所在 part

通过虚拟列定位数据所在分区和 part：

```sql
SELECT
    updated_time,
    object_id,
    _partition_id,
    _part
FROM rtc.tracks_all
WHERE cluster_id = '316957614615300406';
```

结果：

```text
_partition_id = f6b16beb58ea4cf291c183c1363d0e28
_part         = f6b16beb58ea4cf291c183c1363d0e28_0_221251_3490
```

进一步从 `system.parts` 查询该 part：

```sql
SELECT
    hostName(),
    now(),
    partition,
    name,
    active,
    rows,
    min_time,
    max_time,
    delete_ttl_info_min,
    delete_ttl_info_max
FROM clusterAllReplicas('clicks_cluster', system.parts)
WHERE database = 'rtc'
  AND table = 'tracks_local'
  AND active = 1
  AND name = 'f6b16beb58ea4cf291c183c1363d0e28_0_221251_3490';
```

结果关键信息：

```text
hostName()          = clickhouse-olap-0-0 / clickhouse-olap-3-0
partition           = (20260515, 'OBJECT_FACE')
rows                = 2314404
min_time            = 2026-05-15 00:00:00
max_time            = 2026-05-15 23:59:59
delete_ttl_info_min = 2026-06-15 04:00:06
delete_ttl_info_max = 2026-06-15 23:59:59
now()               = 2026-06-15 12:14:57
```

判断：

```text
delete_ttl_info_min < now()  => 已有部分行过期
delete_ttl_info_max > now()  => 整个 part 尚未全部过期
```

结论：该 part 是 **部分行已过期**，不是整块 part 全部过期。  
如果要删除其中已过期行，需要 ClickHouse 执行 TTL merge 重写 part。

---

## 3. 确认不是 `ttl_only_drop_parts` 导致

查询 TTL 相关 MergeTree 设置：

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
);
```

结果：

```text
ttl_only_drop_parts                    = 0
merge_with_ttl_timeout                 = 14400
max_number_of_merges_with_ttl_in_pool  = 2
max_replicated_merges_with_ttl_in_queue = 1
```

判断：

- `ttl_only_drop_parts = 0`：ClickHouse 允许通过 TTL merge 删除 part 内部的部分过期行。
- `merge_with_ttl_timeout = 14400`：TTL merge 调度间隔约为 4 小时，不是到点立即删除。
- `max_number_of_merges_with_ttl_in_pool = 2`：每个节点同时执行 TTL merge 的数量较保守。
- `max_replicated_merges_with_ttl_in_queue = 1`：ReplicatedMergeTree 中 TTL merge 入队数量较保守。

结论：这条数据未清理 **不是因为 `ttl_only_drop_parts = 1` 等整块 part 过期**。

---

## 4. 检查是否有 merge 正在执行

查询 `tracks_local` 当前正在执行的 merge：

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

最初结果：

```text
0 rows
```

说明当时：

```text
tracks_local 当前没有任何 merge
自然也没有 TTL merge
```

后续执行恢复命令后再次查询，出现：

```text
hostName()    = clickhouse-olap-4-0
table         = tracks_local
partition_id  = 0aa6344b309497f19e3cfdf0e5c50cc1
merge_type    = Regular
```

说明：

```text
普通 merge 已恢复执行
但当前看到的是 Regular merge，不是 TTL merge
且分区不是目标分区 f6b16beb58ea4cf291c183c1363d0e28
```

---

## 5. 检查副本是否 readonly 或 replication queue 堵塞

查询副本状态：

```sql
SELECT
    hostName(),
    table,
    is_readonly,
    queue_size,
    merges_in_queue
FROM clusterAllReplicas('clicks_cluster', system.replicas)
WHERE database = 'rtc'
  AND table = 'tracks_local';
```

结果：

```text
所有副本：
is_readonly     = 0
queue_size      = 0
merges_in_queue = 0
```

说明当前：

```text
副本不是 readonly
replication queue 没有积压
merge queue 没有积压
```

之前在 `system.replicas` 中看到过：

```text
last_queue_update_exception:
Code: 242. DB::Exception: Table is in readonly mode
```

但当前关键字段是：

```text
is_readonly = 0
is_session_expired = 0
queue_size = 0
```

因此该 readonly 信息更像是历史异常残留，不能说明当前仍然 readonly。

---

## 6. 如何判断 TTL merge 是否卡住

根据已查结果，目前可以判断为：

```text
1. 数据本身已经超过 31 天 TTL
2. 所在 part 的 delete_ttl_info_min 已小于 now()
3. ttl_only_drop_parts = 0，允许部分过期行被 TTL merge 删除
4. 当前或最初 system.merges 中 tracks_local 无 TTL merge
5. system.replicas 中 is_readonly = 0，queue_size = 0，merges_in_queue = 0
```

因此可以判断：

```text
有 TTL 候选 part，但 TTL merge 当前没有被调度到目标分区。
```

如果该状态持续超过 `merge_with_ttl_timeout = 14400` 秒，并且 `system.part_log` 中也没有 TTL merge 记录，则可以进一步判断为：

```text
TTL merge 调度异常、被限流，或没有正常自动跑起来。
```

---

## 7. 建议继续确认 TTL merge 历史

查询最近是否执行过 TTL merge：

```sql
SELECT
    hostname,
    event_time,
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

判断：

```text
有记录且 error = 0
=> TTL merge 最近确实执行过，只是可能还没轮到目标分区。

无记录
=> 最近 24 小时没有 TTL merge，结合已有过期 part，可认为 TTL merge 没有正常跑起来。
```

也可以查询目标分区的 merge 历史：

```sql
SELECT
    hostname,
    event_time,
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

---

## 8. 检查后台 merge 线程池

如果 TTL 候选 part 存在，但一直没有 TTL merge，需要看后台池是否被占满：

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

判断：

```text
BackgroundMergesAndMutationsPoolTask ≈ BackgroundMergesAndMutationsPoolSize
=> 后台 merge/mutation 池满，TTL merge 在等资源。

BackgroundMergesAndMutationsPoolTask 很低
=> 不是线程池满，更可能是 TTL 没被调度或被 TTL 限流。
```

---

## 9. 恢复 merge / TTL merge 开关

ClickHouse 没有一个非常直观的系统表字段可以直接查询：

```text
该表是否处于 SYSTEM STOP MERGES 状态
该表是否处于 SYSTEM STOP TTL MERGES 状态
```

排查时通常直接执行 START 恢复：

```sql
SYSTEM START MERGES ON CLUSTER clicks_cluster rtc.tracks_local;
SYSTEM START TTL MERGES ON CLUSTER clicks_cluster rtc.tracks_local;
```

这两条命令的含义：

- 不会强制重写全表。
- 不会立刻删除数据。
- 只是恢复普通 merge 和 TTL merge 的后台调度开关。
- 如果本来就是 started 状态，通常没有额外影响。

执行后观察：

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

如果看到 `merge_type = Regular`，说明普通 merge 能跑。  
如果看到 TTL 相关 merge type 或 `part_log.merge_reason` 中出现 TTL，说明 TTL merge 已经跑起来。

---

## 10. 如果需要立即处理目标分区

目标分区：

```text
partition = (20260515, 'OBJECT_FACE')
partition_id = f6b16beb58ea4cf291c183c1363d0e28
```

建议只对该分区强制应用 TTL：

```sql
ALTER TABLE rtc.tracks_local
ON CLUSTER clicks_cluster
MATERIALIZE TTL IN PARTITION tuple(20260515, 'OBJECT_FACE');
```

然后观察 mutation：

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

注意：

```text
MATERIALIZE TTL 会重写相关 part，有 IO / CPU / 磁盘压力。
不要直接全表执行 MATERIALIZE TTL 或 OPTIMIZE FINAL。
优先只处理目标分区。
```

---

## 11. 当前排查结论

基于已执行 SQL，当前结论为：

```text
tracks_local 的目标数据已满足 TTL 条件；
该数据所在 part 已部分过期；
ttl_only_drop_parts = 0，允许 TTL merge 删除部分过期行；
当前所有副本不是 readonly，replication queue 不堵；
普通 merge 已经可以运行；
但目前看到的是 Regular merge，不是 TTL merge，且不是目标分区。
```

因此：

```text
TTL 清理没有被当前副本状态阻塞；
更像是 TTL merge 尚未被调度到目标分区，或 TTL merge 被限流/调度延迟。
```

建议处理顺序：

```text
1. 执行 SYSTEM START MERGES / SYSTEM START TTL MERGES，排除 merge 开关被 stop。
2. 观察 system.merges 和 system.part_log，确认是否出现 TTL merge。
3. 如果业务需要立即清理目标分区，执行 MATERIALIZE TTL IN PARTITION。
4. 如果 TTL 长期不跑，再评估调大 TTL merge 并发限制：
   - max_number_of_merges_with_ttl_in_pool
   - max_replicated_merges_with_ttl_in_queue
```
