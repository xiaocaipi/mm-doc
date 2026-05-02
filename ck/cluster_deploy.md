# ClickHouse 集群部署文档

## 集群架构

### 节点分布

| Shard | Replica 1 | Replica 2 |
|-------|-----------|-----------|
| 1 | ck1 | ck2 |
| 2 | ck3 | - |

- Shard 1: 2个副本（ck1、ck2），数据互为备份
- Shard 2: 1个副本（ck3），存储另一部分数据

### 端口分配

| 节点 | HTTP | TCP (Native) | Keeper | Raft | Interserver |
|------|------|--------------|--------|------|-------------|
| ck1 | 18123 | 19003 | 19181 | 19234 | 19009 |
| ck2 | 18124 | 19001 | 19182 | 19235 | 19010 |
| ck3 | 18125 | 19002 | 19183 | 19236 | 19011 |

### 目录结构

```
/data/caidanfeng/data/mount_ck_cluster/
├── docker-compose.yml
├── ck1/
│   ├── conf/
│   │   ├── cluster.xml
│   │   ├── keeper.xml
│   │   ├── macros.xml
│   │   └── zookeeper.xml
│   ├── data/
│   ├── logs/
│   └── coordination/
├── ck2/
│   ├── conf/
│   │   ├── cluster.xml
│   │   ├── keeper.xml
│   │   ├── macros.xml
│   │   └── zookeeper.xml
│   ├── data/
│   ├── logs/
│   └── coordination/
├── ck3/
│   ├── conf/
│   │   ├── cluster.xml
│   │   ├── keeper.xml
│   │   ├── macros.xml
│   │   └── zookeeper.xml
│   ├── data/
│   ├── logs/
│   └── coordination/
```

---

## 配置文件

### docker-compose.yml

```yaml
version: '3.8'

services:
  ck1:
    image: clickhouse/clickhouse-server:25.1.8
    container_name: ck-node1
    network_mode: host
    ulimits:
      nofile:
        soft: 262144
        hard: 262144
    environment:
      CLICKHOUSE_USER: admin
      CLICKHOUSE_PASSWORD: sensetime
      CLICKHOUSE_DB: default
    volumes:
      - ./ck1/data:/var/lib/clickhouse
      - ./ck1/logs:/var/log/clickhouse-server
      - ./ck1/conf/cluster.xml:/etc/clickhouse-server/config.d/cluster.xml
      - ./ck1/conf/zookeeper.xml:/etc/clickhouse-server/config.d/zookeeper.xml
      - ./ck1/conf/keeper.xml:/etc/clickhouse-server/config.d/keeper.xml
      - ./ck1/conf/macros.xml:/etc/clickhouse-server/config.d/macros.xml
      - ./ck1/coordination:/var/lib/clickhouse/coordination

  ck2:
    image: clickhouse/clickhouse-server:25.1.8
    container_name: ck-node2
    network_mode: host
    ulimits:
      nofile:
        soft: 262144
        hard: 262144
    environment:
      CLICKHOUSE_USER: admin
      CLICKHOUSE_PASSWORD: sensetime
      CLICKHOUSE_DB: default
    volumes:
      - ./ck2/data:/var/lib/clickhouse
      - ./ck2/logs:/var/log/clickhouse-server
      - ./ck2/conf/cluster.xml:/etc/clickhouse-server/config.d/cluster.xml
      - ./ck2/conf/zookeeper.xml:/etc/clickhouse-server/config.d/zookeeper.xml
      - ./ck2/conf/keeper.xml:/etc/clickhouse-server/config.d/keeper.xml
      - ./ck2/conf/macros.xml:/etc/clickhouse-server/config.d/macros.xml
      - ./ck2/coordination:/var/lib/clickhouse/coordination

  ck3:
    image: clickhouse/clickhouse-server:25.1.8
    container_name: ck-node3
    network_mode: host
    ulimits:
      nofile:
        soft: 262144
        hard: 262144
    environment:
      CLICKHOUSE_USER: admin
      CLICKHOUSE_PASSWORD: sensetime
      CLICKHOUSE_DB: default
    volumes:
      - ./ck3/data:/var/lib/clickhouse
      - ./ck3/logs:/var/log/clickhouse-server
      - ./ck3/conf/cluster.xml:/etc/clickhouse-server/config.d/cluster.xml
      - ./ck3/conf/zookeeper.xml:/etc/clickhouse-server/config.d/zookeeper.xml
      - ./ck3/conf/keeper.xml:/etc/clickhouse-server/config.d/keeper.xml
      - ./ck3/conf/macros.xml:/etc/clickhouse-server/config.d/macros.xml
      - ./ck3/coordination:/var/lib/clickhouse/coordination
```

### cluster.xml (3个节点相同)

```xml
<clickhouse>
    <remote_servers>
        <clicks_cluster_human>
            <shard>
                <internal_replication>true</internal_replication>
                <replica>
                    <host>127.0.0.1</host>
                    <port>19003</port>
                    <interserver_http_port>19009</interserver_http_port>
                    <user>admin</user>
                    <password>sensetime</password>
                </replica>
                <replica>
                    <host>127.0.0.1</host>
                    <port>19001</port>
                    <interserver_http_port>19010</interserver_http_port>
                    <user>admin</user>
                    <password>sensetime</password>
                </replica>
            </shard>
            <shard>
                <internal_replication>true</internal_replication>
                <replica>
                    <host>127.0.0.1</host>
                    <port>19002</port>
                    <interserver_http_port>19011</interserver_http_port>
                    <user>admin</user>
                    <password>sensetime</password>
                </replica>
            </shard>
        </clicks_cluster_human>
    </remote_servers>
</clickhouse>
```

### zookeeper.xml (3个节点相同)

```xml
<clickhouse>
    <zookeeper>
        <node>
            <host>127.0.0.1</host>
            <port>19181</port>
        </node>
        <node>
            <host>127.0.0.1</host>
            <port>19182</port>
        </node>
        <node>
            <host>127.0.0.1</host>
            <port>19183</port>
        </node>
    </zookeeper>
</clickhouse>
```

### keeper.xml

#### ck1/conf/keeper.xml

```xml
<clickhouse>
    <http_port>18123</http_port>
    <tcp_port>19003</tcp_port>
    <interserver_http_port>19009</interserver_http_port>
    <keeper_server>
        <tcp_port>19181</tcp_port>
        <server_id>1</server_id>
        <log_storage_path>/var/lib/clickhouse/coordination/log</log_storage_path>
        <snapshot_storage_path>/var/lib/clickhouse/coordination/snapshots</snapshot_storage_path>
        <raft_configuration>
            <server>
                <id>1</id>
                <hostname>127.0.0.1</hostname>
                <port>19234</port>
            </server>
            <server>
                <id>2</id>
                <hostname>127.0.0.1</hostname>
                <port>19235</port>
            </server>
            <server>
                <id>3</id>
                <hostname>127.0.0.1</hostname>
                <port>19236</port>
            </server>
        </raft_configuration>
    </keeper_server>
</clickhouse>
```

#### ck2/conf/keeper.xml

```xml
<clickhouse>
    <http_port>18124</http_port>
    <tcp_port>19001</tcp_port>
    <interserver_http_port>19010</interserver_http_port>
    <keeper_server>
        <tcp_port>19182</tcp_port>
        <server_id>2</server_id>
        <log_storage_path>/var/lib/clickhouse/coordination/log</log_storage_path>
        <snapshot_storage_path>/var/lib/clickhouse/coordination/snapshots</snapshot_storage_path>
        <raft_configuration>
            <server>
                <id>1</id>
                <hostname>127.0.0.1</hostname>
                <port>19234</port>
            </server>
            <server>
                <id>2</id>
                <hostname>127.0.0.1</hostname>
                <port>19235</port>
            </server>
            <server>
                <id>3</id>
                <hostname>127.0.0.1</hostname>
                <port>19236</port>
            </server>
        </raft_configuration>
    </keeper_server>
</clickhouse>
```

#### ck3/conf/keeper.xml

```xml
<clickhouse>
    <http_port>18125</http_port>
    <tcp_port>19002</tcp_port>
    <interserver_http_port>19011</interserver_http_port>
    <keeper_server>
        <tcp_port>19183</tcp_port>
        <server_id>3</server_id>
        <log_storage_path>/var/lib/clickhouse/coordination/log</log_storage_path>
        <snapshot_storage_path>/var/lib/clickhouse/coordination/snapshots</snapshot_storage_path>
        <raft_configuration>
            <server>
                <id>1</id>
                <hostname>127.0.0.1</hostname>
                <port>19234</port>
            </server>
            <server>
                <id>2</id>
                <hostname>127.0.0.1</hostname>
                <port>19235</port>
            </server>
            <server>
                <id>3</id>
                <hostname>127.0.0.1</hostname>
                <port>19236</port>
            </server>
        </raft_configuration>
    </keeper_server>
</clickhouse>
```

### macros.xml

#### ck1/conf/macros.xml

```xml
<clickhouse>
    <macros>
        <cluster>clicks_cluster_human</cluster>
        <shard>1</shard>
        <replica>1</replica>
    </macros>
</clickhouse>
```

#### ck2/conf/macros.xml

```xml
<clickhouse>
    <macros>
        <cluster>clicks_cluster_human</cluster>
        <shard>1</shard>
        <replica>2</replica>
    </macros>
</clickhouse>
```

#### ck3/conf/macros.xml

```xml
<clickhouse>
    <macros>
        <cluster>clicks_cluster_human</cluster>
        <shard>2</shard>
        <replica>1</replica>
    </macros>
</clickhouse>
```

### macros.xml 配置详解

macros.xml 定义了**每个节点在集群中的身份标识**。

#### 各字段含义

| 字段 | 含义 | 作用 |
|------|------|------|
| `cluster` | 集群名称 | 标识节点属于哪个集群，与 cluster.xml 中定义的集群名一致 |
| `shard` | 分片编号 | 标识节点属于哪个 shard（数据分片） |
| `replica` | 副本编号 | 标识节点是该 shard 的第几个副本 |

#### 三个节点的 macros 配置对比

| 节点 | shard | replica | 含义 |
|------|-------|---------|------|
| ck1 | **1** | **1** | Shard 1 的第 1 个副本 |
| ck2 | **1** | **2** | Shard 1 的第 2 个副本 |
| ck3 | **2** | **1** | Shard 2 的第 1 个副本 |

#### 实际作用

创建 ReplicatedMergeTree 表时，macros 中的 `{cluster}`, `{shard}`, `{replica}` 会自动替换：

```sql
CREATE TABLE test_table ON CLUSTER clicks_cluster_human
ENGINE = ReplicatedMergeTree('/clickhouse/tables/{cluster}/{shard}/test_table', '{replica}')
ORDER BY id;
```

替换后的结果：

| 节点 | 替换后的 ZooKeeper 路径 | 替换后的 replica 名称 |
|------|------------------------|----------------------|
| ck1 | `/clickhouse/tables/clicks_cluster_human/1/test_table` | `1` |
| ck2 | `/clickhouse/tables/clicks_cluster_human/1/test_table` | `2` |
| ck3 | `/clickhouse/tables/clicks_cluster_human/2/test_table` | `1` |

**关键点**：ck1 和 ck2 都指向同一个 ZooKeeper 路径，所以它们是**同一个 shard 的两个副本**，数据会自动同步。ck3 指向不同的路径，是**另一个 shard**。

#### 集群架构图解

```
┌─────────────────────────────────────────────────────┐
│                 clicks_cluster_human                 │
├─────────────────────────────────────────────────────┤
│                                                     │
│  Shard 1 (存储前一半数据)                            │
│  ├── Replica 1 (ck1) ──┬── 数据互为备份            │
│  └── Replica 2 (ck2) ──┘   自动同步                 │
│                                                     │
│  Shard 2 (存储后一半数据)                            │
│  └── Replica 1 (ck3) ─── 独立存储                   │
│                                                     │
└─────────────────────────────────────────────────────┘
```

---

## 集群架构详解

### 当前集群配置

| Shard | Replica 数量 | 节点 | 说明 |
|-------|-------------|------|------|
| Shard 1 | 2 个 | ck1, ck2 | 有备份，数据互为副本 |
| Shard 2 | 1 个 | ck3 | 无备份，只有单节点 |

### 数据分布示例

假设 1 亿条数据通过 Distributed 表写入：

```
Shard 1: 5000 万条
  ├── ck1: 5000 万条 (副本1)
  └── ck2: 5000 万条 (副本2，和 ck1 相同，自动同步)

Shard 2: 5000 万条
  └── ck3: 5000 万条 (只有一份，无备份)
```

### 高可用分析

| 场景 | 结果 |
|------|------|
| ck1 挂了 | Shard 1 还有 ck2，数据不丢失 |
| ck2 挂了 | Shard 1 还有 ck1，数据不丢失 |
| ck3 挂了 | **Shard 2 数据丢失**（无备份） |

### 扩展建议

如需让 Shard 2 也具备高可用，可添加 ck4 节点：

```xml
<!-- ck4/conf/macros.xml -->
<clickhouse>
    <macros>
        <cluster>clicks_cluster_human</cluster>
        <shard>2</shard>
        <replica>2</replica>
    </macros>
</clickhouse>
```

扩展后的架构：

| Shard | Replica 1 | Replica 2 |
|-------|-----------|-----------|
| 1 | ck1 | ck2 |
| 2 | ck3 | ck4 |

### 集群管理

```bash
# 启动集群
cd /data/caidanfeng/data/mount_ck_cluster
docker compose up -d

# 停止集群
docker compose down

# 查看状态
docker compose ps

# 查看日志
docker compose logs -f ck1
docker compose logs -f ck2
docker compose logs -f ck3
```

### 连接节点

```bash
# 连接节点1 (端口 19003)
docker exec ck-node1 clickhouse-client --port 19003 --user admin --password sensetime

# 连接节点2 (端口 19001)
docker exec ck-node2 clickhouse-client --port 19001 --user admin --password sensetime

# 连接节点3 (端口 19002)
docker exec ck-node3 clickhouse-client --port 19002 --user admin --password sensetime

# HTTP 接口访问
curl http://127.0.0.1:18123
curl http://127.0.0.1:18124
curl http://127.0.0.1:18125
```

### 集群查询

```sql
-- 查看集群节点
SELECT cluster, shard_num, replica_num, host_name, port
FROM system.clusters
WHERE cluster = 'clicks_cluster_human';

-- 查看 Keeper 状态
SELECT name, value FROM system.zookeeper WHERE path = '/';

-- 查看复制状态
SELECT database, table, engine, replica_name
FROM system.replicas;
```

### 创建分布式表

```sql
-- 创建本地表（ReplicatedMergeTree）
CREATE TABLE test_table ON CLUSTER clicks_cluster_human
(
    id UInt32,
    name String,
    created_at DateTime
)
ENGINE = ReplicatedMergeTree('/clickhouse/tables/{cluster}/{shard}/test_table', '{replica}')
ORDER BY id;

-- 创建分布式表
CREATE TABLE test_dist_table ON CLUSTER clicks_cluster_human
(
    id UInt32,
    name String,
    created_at DateTime
)
ENGINE = Distributed(clicks_cluster_human, default, test_table, id);

-- 插入数据（自动分发到各 shard）
INSERT INTO test_dist_table VALUES (1, 'test', now());

-- 查询分布式表（聚合所有 shard 数据）
SELECT * FROM test_dist_table ORDER BY id;
```

---

## 注意事项

1. **端口冲突**: 确保所有端口未被占用，特别是 interserver_http_port
2. **用户认证**: cluster.xml 中必须配置 user/password 用于节点间通信
3. **数据同步**: 同一 shard 的 replica 会自动同步数据
4. **Keeper 集群**: 3个 Keeper 组成 Raft，保证元数据一致性