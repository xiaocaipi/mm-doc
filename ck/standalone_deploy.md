# ClickHouse 单机版部署文档

## 部署信息

| 项目 | 值 |
|------|-----|
| 部署方式 | Docker run |
| 容器名称 | ck-25_1_8 |
| 镜像版本 | clickhouse/clickhouse-server:25.1.8 |
| 目标主机 | 172.20.25.104 |
| 网络模式 | host |

## 端口分配

| 端口类型 | 端口 | 说明 |
|---------|------|------|
| HTTP | 8123 | 默认 HTTP 接口端口 |
| TCP (Native) | 9000 | 客户端连接端口 |
| Keeper | 9181 | ClickHouse Keeper 客户端端口 |
| Keeper Raft | 9234 | Keeper 内部 Raft 通信端口 |

## 目录结构

```
/data/caidanfeng/data/mount_ck/
├── ck_conf/
│   ├── cluster.xml      # 集群定义（单节点）
│   ├── keeper.xml       # Keeper 配置
│   └── macros.xml       # 宏定义
├── ck_data/             # 数据存储目录
│   ├── access/          # 访问控制数据
│   ├── coordination/    # Keeper 数据
│   ├── data/            # 表数据
│   ├── metadata/        # 元数据
│   ├── store/           # 数据存储
│   └── ...
├── ck_logs/             # 日志目录
└── ck_cluster/          # 未使用的集群目录
```

---

## 配置文件

### cluster.xml

```xml
<clickhouse>
    <remote_servers>
        <clicks_cluster_human>
            <shard>
                <replica>
                    <host>172.20.25.104</host>
                    <port>9000</port>
                </replica>
            </shard>
        </clicks_cluster_human>
    </remote_servers>
</clickhouse>
```

**说明：** 定义了名为 `clicks_cluster_human` 的集群，包含 1 个 shard、1 个 replica。

### keeper.xml

```xml
<clickhouse>
    <keeper_server>
        <!-- 客户端连接端口（ClickHouse 引擎连接到这个端口） -->
        <tcp_port>9181</tcp_port>

        <!-- 唯一 server id -->
        <server_id>1</server_id>

        <!-- 日志与快照保存目录 -->
        <log_storage_path>/var/lib/clickhouse/coordination/log</log_storage_path>
        <snapshot_storage_path>/var/lib/clickhouse/coordination/snapshots</snapshot_storage_path>

        <!-- RAFT 配置（注意端口不能等于 tcp_port） -->
        <raft_configuration>
            <server>
                <id>1</id>
                <hostname>172.20.25.104</hostname>
                <port>9234</port> <!-- 必须和 tcp_port 不同 -->
            </server>
        </raft_configuration>
    </keeper_server>
</clickhouse>
```

**说明：** 启用内置 ClickHouse Keeper，用于存储 ReplicatedMergeTree 表的元数据。

### macros.xml

```xml
<clickhouse>
    <macros>
        <shard>1</shard>
        <replica>default1</replica>
    </macros>
</clickhouse>
```

**说明：** 定义节点身份标识，用于 ReplicatedMergeTree 表的 ZK 路径替换。

---

## 启动命令

```bash
docker run -d --name ck-25_1_8 --net=host \
  --ulimit nofile=262144:262144 \
  -e CLICKHOUSE_USER=admin \
  -e CLICKHOUSE_PASSWORD=sensetime \
  -e CLICKHOUSE_DB=default \
  -v /data/caidanfeng/data/mount_ck/ck_data:/var/lib/clickhouse \
  -v /data/caidanfeng/data/mount_ck/ck_logs:/var/log/clickhouse-server \
  -v /data/caidanfeng/data/mount_ck/ck_conf/cluster.xml:/etc/clickhouse-server/config.d/cluster.xml \
  -v /data/caidanfeng/data/mount_ck/ck_conf/keeper.xml:/etc/clickhouse-server/config.d/keeper.xml \
  -v /data/caidanfeng/data/mount_ck/ck_conf/macros.xml:/etc/clickhouse-server/config.d/macros.xml \
  clickhouse/clickhouse-server:25.1.8
```

---

## 容器管理

```bash
# 启动容器
docker start ck-25_1_8

# 停止容器
docker stop ck-25_1_8

# 删除容器
docker rm ck-25_1_8

# 查看状态
docker ps -a --filter "name=ck-25_1_8"

# 查看日志
docker logs -f ck-25_1_8

# 进入容器
docker exec -it ck-25_1_8 bash
```

---

## 连接方式

### clickhouse-client

```bash
# 本机连接
docker exec -it ck-25_1_8 clickhouse-client --user admin --password sensetime

# 远程连接
clickhouse-client --host 172.20.25.104 --port 9000 --user admin --password sensetime
```

### HTTP 接口

```bash
# 测试连接
curl http://172.20.25.104:8123

# 执行查询
curl "http://172.20.25.104:8123/?user=admin&password=sensetime" -d "SELECT 1"

# 查询数据库列表
curl "http://172.20.25.104:8123/?user=admin&password=sensetime" -d "SHOW DATABASES"
```

---

## 现有数据库

| 数据库 | 说明 |
|--------|------|
| default | 默认数据库 |
| bdp | 业务数据库 |
| rtc | 业务数据库 |
| sensexplorer | 业务数据库 |
| system | 系统数据库 |

---

## 常用查询

```sql
-- 查看集群信息
SELECT cluster, shard_num, replica_num, host_name, port
FROM system.clusters;

-- 查看数据库列表
SHOW DATABASES;

-- 查看表列表
SHOW TABLES FROM bdp;

-- 查看 Keeper 状态
SELECT name, value FROM system.zookeeper WHERE path = '/';

-- 查看复制状态
SELECT database, table, engine, replica_name
FROM system.replicas;

-- 查看版本
SELECT version();
```

---

## 注意事项

1. **网络模式：** 使用 host 网络模式，容器直接使用宿主机端口
2. **Keeper 单节点：** 单机版 Keeper 只有 1 个节点，不具备高可用
3. **数据持久化：** 数据和日志通过 volume 挂载到宿主机
4. **用户认证：** 默认用户 admin/sensetime
5. **ulimit 配置：** 需要设置 nofile 为 262144，否则可能影响性能