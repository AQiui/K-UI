-- ============================================================
-- KUI · D1 读取额度优化索引
-- ------------------------------------------------------------
-- 背景：D1 免费版只有 500 万行读/天，按「扫描行数」计费。
--       agents 表级查询缺少索引时，每次 agent 上报 / 拉配置都会
--       对 nodes 全表扫描，一天就能把额度烧光。
--
-- 用法：Cloudflare Dashboard → D1 → kui-db → Console，粘贴执行。
--       注意：若当天额度已耗尽（D1_ERROR daily row read limit），
--       任何查询（含 DDL）都会被拒绝，需等 UTC 00:00 重置后再跑。
--       代码里的 initializeDbSchema 已带这些 CREATE INDEX，
--       部署后冷启动也会自动补建，本文件仅用于「立刻生效」。
-- ============================================================

-- 1. 最关键：agent 拉配置(/api/config)与流量上报都按 vps_ip 过滤 nodes
CREATE INDEX IF NOT EXISTS idx_nodes_vps_ip ON nodes(vps_ip);

-- 2. 过期回执清理 DELETE ... WHERE created_at < ? 此前是全表扫描
CREATE INDEX IF NOT EXISTS idx_receipts_created_at ON report_receipts(created_at);

-- 3. 历史流量清理（新增 30 天滚动删除）
CREATE INDEX IF NOT EXISTS idx_traffic_stats_ts ON traffic_stats(timestamp);

-- 4. 离线巡检 SELECT ... WHERE last_report < ? AND alert_sent = 0
CREATE INDEX IF NOT EXISTS idx_servers_last_report ON servers(last_report, alert_sent);

-- 5. 公开大盘筛选 is_hidden != 'true'
CREATE INDEX IF NOT EXISTS idx_probe_servers_hidden ON probe_servers(is_hidden);

-- 6. 代理池在线筛选 last_seen >= ?
CREATE INDEX IF NOT EXISTS idx_proxy_ctrl_last_seen ON proxy_ctrl_servers(last_seen);

-- 7. 删除用户时批量转交节点
CREATE INDEX IF NOT EXISTS idx_nodes_username ON nodes(username);

-- ------------------------------------------------------------
-- 自查：确认索引已生效
-- ------------------------------------------------------------
SELECT name, tbl_name FROM sqlite_master WHERE type = 'index' AND name LIKE 'idx_%' ORDER BY tbl_name, name;

-- 确认查询走索引（应出现 SEARCH ... USING INDEX，而不是 SCAN）
EXPLAIN QUERY PLAN SELECT * FROM nodes WHERE vps_ip = '1.2.3.4';
EXPLAIN QUERY PLAN DELETE FROM report_receipts WHERE created_at < 0;

-- 各表行数（行数 × 全扫次数 = 每天消耗的行读额度）
SELECT 'nodes' AS t, COUNT(*) AS rows FROM nodes
UNION ALL SELECT 'report_receipts', COUNT(*) FROM report_receipts
UNION ALL SELECT 'traffic_stats', COUNT(*) FROM traffic_stats
UNION ALL SELECT 'probe_servers', COUNT(*) FROM probe_servers
UNION ALL SELECT 'servers', COUNT(*) FROM servers;
