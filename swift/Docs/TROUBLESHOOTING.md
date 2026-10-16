# 连接排查

## 「读取服务器数据失败」，但 3X-UI 正常

2026-10-16 实际遇到过一次：**不是应用的问题，是本地代理（Clash 系，fake-ip 模式）当时连不上搬瓦工 API**，代理节点恢复后自行好转。

### 故障机理

应用把 `api.64clouds.com` 交给系统解析 → 代理返回 fake-ip → 应用连向 fake-ip → 流量进代理的 TUN → 代理用它选中的节点去连真实服务器，节点无响应 → 应用 20 秒超时。

### 判断步骤

1. **先看另一个数据源**。3X-UI 正常而搬瓦工失败，说明不是整机断网。
2. **看解析结果**。地址落在 `198.18.0.0/15`（`198.18.x.x` / `198.19.x.x`）基本可以断定是 fake-ip。这是 RFC 2544 的基准测试保留网段，不是公网地址，不要当成真实地址去分析。
3. **`连接耗时 0.000000s` + 超时 = TCP 根本没建立**，不是 TLS 或应用层的问题：

   ```bash
   curl -o /dev/null -s -w '%{http_code} connect=%{time_connect}s total=%{time_total}s\n' --max-time 20 https://api.64clouds.com/
   ```

4. **用 DoH 拿真实 IP**（UDP 53 通常也被代理劫持，普通 `dig` 拿到的还是 fake-ip）：

   ```bash
   curl -s 'https://dns.alidns.com/resolve?name=api.64clouds.com&type=A'
   ```

5. **绕过 fake-ip 直连真实 IP**，这是区分「服务器坏了」和「代理坏了」最快的一招。直连通、默认路径不通，就是代理节点的问题：

   ```bash
   curl -o /dev/null -s -w '%{http_code}\n' --max-time 20 --resolve api.64clouds.com:443:<真实IP> https://api.64clouds.com/
   ```

6. **佐证**：`scutil --proxy` 的 `ExceptionsList` 里会出现代理工具自己加的 `198.18.0.0/15`。

### 处理

换代理节点，或让 `api.64clouds.com` 走直连规则。应用本身不需要改。

### 可选加固（未做）

- 解析结果落在 fake-ip 网段且连接失败时，错误提示直接写「疑似本地代理节点不通」，而不是笼统的「请检查连接」。
- 适当放宽 `getServiceInfo` 的 20 秒超时。
