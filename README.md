# BookCard

本地优先的微信读书阅读进度与笔记浏览器，支持 macOS 14+、iOS 17+ 和 iPadOS 17+。使用 Swift 6 工具链，无第三方应用依赖。

## 代码结构

核心数据与业务只维护一套，通过本地 Swift Package `BookCardCore` 提供给两个应用目标；UI 和设备交互独立维护。

| 目录 / 目标 | 职责 |
|---|---|
| `Sources/BookCardCore/` | 数据模型、网关请求、同步、搜索、排序、笔记分组、标题补全、钥匙串和 SwiftData 存储 |
| `Apps/macOS/` / `BookCard-macOS` | 原生 Mac 窗口、导航栏、列表、菜单和弹窗 |
| `Apps/Mobile/iPhone/` | iPhone 的底部 Tab 和逐级笔记导航 |
| `Apps/Mobile/iPad/` | iPad 的侧栏、分栏导航和自适应书籍网格 |
| `Apps/Mobile/Components/` | 移动端通用组件、Key 输入、状态提示与设置交互 |
| `BookCard-iOS` | 打包支持 iPhone 和 iPad 的通用应用，根据设备选择各自的 UI 入口 |

共享包不依赖 SwiftUI、AppKit 或 UIKit；使用 Combine 发布业务状态。页面选择、弹窗、设备判断和导航均留在各自 UI 层。两种应用使用相同的公开业务接口，不复制同步逻辑。iPad 窄窗口会折叠分栏为逐级导航。

## 使用

macOS 可双击 `build/BookCard.app`；移动端使用下方模拟器脚本，或从 Xcode 运行到自己的设备。第一次启动，点击官方 Key 页面，在微信读书登录后生成 Key，粘贴到应用并点击「连接并读取数据」。主界面提供两个功能：

- **我读过的书**：遍历当前书架和笔记本中的书籍进度，展示所有扫描到的书籍（包括未读、在读、已读完），默认按进度降序；仅可选择进度升序或降序，选择会保存在本机。进度未获取的书籍仍显示，数值排序时放在末尾。旧版本保存的其他排序规则回退为进度降序。仅在接口返回正数时长时显示阅读时长，缺失或为 0 时隐藏。
- **我的笔记**：同步所有笔记本，按书籍、公众号列出笔记来源，按章节或文章分组展示划线和想法。Mac/iPad 使用分栏浏览，iPhone 使用列表进入详情。支持来源搜索、笔记内容搜索与类型筛选。

两个功能分别同步进度与笔记，互不依赖另一个功能的明细接口。首次打开尚未完成同步的功能时自动同步。每完成一个来源即通过 SwiftData 事务保存该来源的记录，失败来源保留旧数据并提示。缓存可离线浏览。

## 编译和测试

```sh
./scripts/build-app.sh
open build/BookCard.app
./scripts/test.sh

# iPhone / iPad 模拟器（需要完整 Xcode、已安装的 iOS 运行时和 Python 3）
./scripts/run-ios.sh iphone
./scripts/run-ios.sh ipad

# 仅构建移动端，不启动模拟器
./scripts/build-ios.sh simulator
./scripts/build-ios.sh device
```

macOS 脚本和共享包测试仅需 Command Line Tools。`BookCard.xcodeproj` 提供 `BookCard-macOS` 和 `BookCard-iOS` 两个共享 Scheme，可直接选择 Mac、iPhone 或 iPad 运行和断点调试；`Package.swift` 用于共享包开发、测试和 macOS 命令行构建。

macOS 构建脚本生成本机临时签名的应用，未做公证或发布签名；重新编译后钥匙串可能要求重新授权。模拟器构建使用本机临时签名，以支持钥匙串；真机编译验证关闭签名。真机运行时，在 Xcode 的 `BookCard-iOS` 目标配置自己的 Signing Team，连接设备并开启开发者模式后运行；无需在仓库保存证书或 Team ID。

## 数据和隐私

- Key 仅保存到各设备的系统钥匙串（服务 `local.BookCard.WeRead`），不进入缓存、日志或仓库，不通过 iCloud 同步。
- 原生 URLSession 直接访问官方 HTTPS 网关，禁用重定向，不经开发者服务器。
- 请求使用平铺参数和 `skill_version: 1.0.4`；遇到升级提示或不兼容响应，保留缓存并显示错误。
- macOS 的 SwiftData 数据库保存于 `~/Library/Application Support/BookCard/`，iOS/iPadOS 保存于各自应用沙箱的 `Library/Application Support/BookCard/`。数据库名为 `{Key 的 SHA256}.store`，由 SwiftData 管理数据库及 `-wal`、`-shm` 辅助文件。文件权限 0600、目录权限 0700；未额外加密，可能进入系统备份。
- 书籍、笔记明细、每条笔记、阅读进度与同步状态分别建模；笔记关联来源并支持级联清除。同步只保存当前数据域或来源，不再编码和重写整份 JSON。UI 仍通过共享核心提供的内存快照浏览、搜索和排序。
- 各设备独立保存 Key 和缓存；共享业务代码不代表设备间自动共享数据。SwiftData 的 CloudKit 同步明确关闭。
- 每个 Key 使用独立数据库。不假设更换 Key 就是同一个账号。
- 首次读取某个 Key 的旧 JSON 缓存时，完整迁移到 SwiftData 并提交成功后删除对应 JSON；失败时保留原文件供重试。持久化迁移标记防止残留旧文件覆盖较新数据。之后不再生成 JSON 缓存，也不提供导入、导出或备份功能。
- 移除 Key 保留离线阅读；清除本地数据会删除该应用所有 Key 对应的缓存。两项操作都不修改微信读书服务端数据。
- 单个来源完成并通过数量、身份和分页校验后提交事务，事务失败回滚该次更新。发现旧笔记缺失时保留旧缓存并提示；旧来源也保留，直至用户主动清除本地数据。首次同步完成标记、缓存过期和网络请求策略不随此次存储更换而改变。

## MVP 范围

- 列表合并书架 `books` 和所有分页的笔记本；不声称这是所有历史阅读记录。
- 暂不展示有声书、文章收藏入口、周期阅读统计或卡片。
- 公众号按原项目规则提取文章 ID 分组；划线和想法共用接口提供的文章标题。标题缺失时通过独立、无 Key 的网络会话读取公众号公开页面的 og:title，并缓存标题。公开页面不可访问时保留笔记，显示“文章（标题暂缺）”。旧版缓存缺少文章 ID，下次同步时补全。
- 普通书签只在上游统计中存在，不当作划线显示；不承诺非书籍想法覆盖。
- 首次打开「我的笔记」遍历全部笔记本及其分页内容，每本书展示自己的同步时间；「我读过的书」独立遍历阅读进度。
- 接口只读；网络失败、Key 无效时已缓存数据可继续浏览。

## 验证边界

`./scripts/test.sh` 运行共享包的 XCTest，覆盖网关错误、分页与数量校验、SwiftData 持久化与 Key 隔离、按来源更新、事务回滚、旧 JSON 迁移与重试、残留文件防覆盖、级联清除，以及三个界面共用的搜索、排序和笔记分组公开接口。真实账号的连通性、Key 生命周期及服务端数据形态，需要在应用中用自己的 Key 实测。未使用或读取用户其他集成中的凭证。

参考：
- https://github.com/Tencent/WeChatReading/tree/main/skills
