# IDaaS 对接Flashcat配置手册

## 一、对接概述

本文档说明如何将阿里云 IDaaS 作为 OIDC 身份提供商，对接Flashcat监控系统，实现单点登录。

**认证流程：** 用户访问Flashcat → 跳转 IDaaS 登录 → IDaaS 回调Flashcat携带授权码 → Flashcat换取用户信息 → 自动创建/更新用户 → 登录完成


## 二、IDaaS 侧配置

### 2.1 创建 OIDC 应用

1. 登录 IDaaS 控制台，进入目标实例
2. **应用 > 应用管理 > 创建应用**，选择 **标准协议（OIDC）**
3. 创建完成后，记录以下信息：

| 配置项 | 获取位置 | 用途 |
| :--- | :--- | :--- |
| `client_id` | 通用配置标签页 | 填到Flashcat `ClientId` |
| `client_secret` | 通用配置标签页 | 填到Flashcat `ClientSecret` |
| **Issuer** | 登录访问标签页 > 应用配置信息 | 填到Flashcat `SsoAddr` |

### 2.2 配置回调地址

在 IDaaS 应用的 **Redirect URI** 列表中，添加Flashcat回调地址：

```
http://<Flashcat域名>/callback
```


## 三、Flashcat侧配置

编辑 `config.toml` 文件：

```toml
[SSO.OIDC]
Enable = true
DisplayName = 'IDaaS登录'
RedirectURL = 'http://<Flashcat域名>/callback'
SsoAddr = 'https://<IDaaS实例域名>/v2/<实例ID>/<应用ID>/oidc'
ClientId = '<从IDaaS获取的client_id>'
ClientSecret = '<从IDaaS获取的client_secret>'
DefaultRoles = ['Standard']
CoverAttributes = true
Scopes = ['openid', 'profile', 'email', 'phone']

[SSO.OIDC.Attributes]
Username = 'sub'
Nickname = 'name'
Phone = 'phone_number'
Email = 'email'
```

**必填项说明：**

| 配置项 | 说明 | 示例 |
| :--- | :--- | :--- |
| `SsoAddr` | IDaaS 的 Issuer 地址 | `https://xxxx.aliyunidaas.com/v2/idaas_xxx/app_xxx/oidc` |
| `ClientId` | IDaaS 应用 client_id | `app_xxxxx` |
| `ClientSecret` | IDaaS 应用 client_secret | 复制粘贴即可 |
| `RedirectURL` | Flashcat回调地址，**必须与 IDaaS 中配置的一致** | `http://n9e.company.com/callback` |


## 四、验证与排错

### 4.1 登录测试

1. 重启Flashcat：`systemctl restart n9e`
2. 访问Flashcat登录页，点击 **IDaaS登录** 按钮
3. 跳转到 IDaaS 完成登录，验证能否正常返回Flashcat

### 4.2 常见问题

| 现象 | 可能原因 | 解决方法 |
| :--- | :--- | :--- |
| 点击登录后跳转失败 | `RedirectURL` 与 IDaaS 配置不一致 | 检查两边回调地址完全一致 |
| 登录成功但无用户信息 | 字段映射不匹配 | 开启 DEBUG 日志，查看实际返回字段，调整 `[Attributes]` |
| 手机号/邮箱未同步 | Scope 未包含对应字段 | 确保 Scopes 中包含 `phone` 和 `email` |


## 五、配置速查表

| Flashcat配置项 | 值来源 | IDaaS 中位置 |
| :--- | :--- | :--- |
| `SsoAddr` | Issuer 地址 | 登录访问 > 应用配置信息 |
| `ClientId` | client_id | 通用配置 |
| `ClientSecret` | client_secret | 通用配置 |
| `RedirectURL` | 自定义 | 需同步添加到 IDaaS Redirect URI |

---

> **提示：** Flashcat会自动通过 `SsoAddr` 发现授权端点、令牌端点等，无需手动配置。
