# Issue #60：长耗时 UI Test 的 AX 查询审计

## 结论

本次审计确认，长耗时 UI Test 的主要问题不是单一的 `hasFocus` 断言，而是部分断言为了寻找一个明确目标，先通过标题匹配取得元素集合，再调用 `allElementsBoundByIndex` 枚举整个集合。集合快照会把无关元素也纳入一次 AX 查询，并且在轮询中重复发生。

已将正常断言路径中可以明确定位的 feed 卡片和选集卡片改为稳定 `accessibilityIdentifier` 查询。失败诊断报告仍保留全量枚举，因为它的目的就是列出当前所有持焦按钮，不能与正常断言混用。

## 审计范围与方法

审计对象来自 CI run [33953132195](https://github.com/Debiancc/bilibili_tv/actions/runs/33953132195)：

- `CarouselPageBounceReproTests.testChainedCarouselPagingDoesNotSnapBack`
- `FeedFocusNavigationTests.testChainedFeedFocusNavigationAcrossShelves`
- `DetailFocusNavigationTests.testChainedLongSynopsisEpisodeFocusNavigation`
- `FeedDetailNavigationTests.testShelfCardSelectPresentsDetailAndFocusReturns`

通过 `xcodebuild` 的 XCTest 日志统计以下事件：元素存在性检查、元素查找、`allElementsBoundByIndex`、遥控器按键以及显式 `waitForExistence` 等待。日志中的 AX 查询事件没有提供可稳定分离的单次耗时，因此本次不把测试总时长简单等同于 AX 查询耗时；总时长还包括应用启动、焦点动画、页面转场和遥控器事件处理。

## CI 基线

CI 使用 Xcode 26.6 / tvOS 26.2，四条用例均通过。下面的“AX 事件”是日志事件次数，不是耗时（单位：秒）。

| 用例 | 总时长 | 存在性检查 | 查找 | 全量集合快照 | 按键 | 显式等待 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Carousel | 45.741 | 51 | 50 | 0 | 33 | 1 |
| Feed | 30.210 | 37 | 76 | 5 | 36 | 1 |
| Detail | 29.144 | 10 | 93 | 83 | 32 | 3 |
| Feed → Detail | 12.646 | 2 | 5 | 4 | 4 | 2 |

### 具体归因

- Carousel 没有全量集合快照；约 54 次 `hero.current-page` marker 查询与 33 次方向键交错发生，主要成本是轮播动画和焦点落位等待。
- Feed 的重复标题匹配会在不同 shelf 中扫描相同 label 的元素集合；它还包含 36 次方向键，因此墙钟时间不能只归因于 AX。
- Detail 是最明确的查询热点：长路径约 83 次 `allElementsBoundByIndex`，并伴随 32 次方向键和 3 次显式等待。
- Feed → Detail 的约 3 秒等待集中在详情页转场后等待 `追剧` 按钮及焦点稳定，当前证据不足以证明这是 AX 查询阻塞，应与查询热点分开记录。

## 本地复测

本地使用 Xcode beta、tvOS 27.0 模拟器，复用 `build-for-testing` 产物，四条用例逐条运行，且关闭并行测试。

| 用例 | 原查询方案总时长 | 原方案全量集合快照 | identifier 方案总时长 | identifier 方案全量集合快照 |
| --- | ---: | ---: | ---: | ---: |
| Carousel | 37.469 | 0 | 45.036 | 0 |
| Feed | 28.470 | 5 | 31.309 | 0 |
| Detail 长路径 | 27.157 | 90 | 28.888 | 0 |
| Feed → Detail | 12.850 | 4 | 14.631 | 0 |

单次本地运行的墙钟时间受模拟器负载、tvOS 焦点动画和启动状态影响，不能据此宣称总时长下降或上升。此次改动的可重复收益是查询范围收窄：正常断言不再枚举无关元素集合。四条重点用例及 detail 短路径均通过。

本地日志还会出现 tvOS 模拟器缺少 `PhotosFramework.axbundle` 和 `PhotoLibraryServices.axbundle` 的 AXLoading 警告；CI 与本地都出现，且本次用例通过，属于测试环境噪声，不是应用断言失败。

## 已实施的收敛

- Feed 卡片 identifier：`feed.<shelfID>.card.<itemID>`。
- Detail 选集 identifier：`detail.episode.<episodeID>`。
- Feed、Feed → Detail 以及 Detail 的正常焦点断言改用 `app.buttons[identifier]`。
- Detail 短路径的“任一选集卡片持焦”也改为检查固定 episode identifier 集合。
- 保留几何断言中的 `frame`：这些断言验证的是返回同一卡片实例和滚动可见性，不能用 identifier 替代其语义。
- 保留 `focusedButtonsReport` 的 `allElementsBoundByIndex`：该方法只在失败取证时使用，用来报告当前所有持焦按钮。

## 后续判断标准

新增 UI Test 时，如果目标元素在测试语义中是明确的，应优先给生产视图添加稳定 `accessibilityIdentifier`，并在测试中直接查询；只有“报告当前整个可访问性树”这类诊断需求才使用全量集合枚举。

这符合 XCTest 的查询语义：`allElementsBoundByIndex` 会立即求值并返回绑定的元素集合，`hasFocus` 表示 tvOS 当前焦点状态，`frame` 表示元素几何区域。参考 Apple 官方文档：[XCUIElementQuery.allElementsBoundByIndex](https://developer.apple.com/documentation/xcuiautomation/xcuielementquery/allelementsboundbyindex)、[XCUIElementAttributes.hasFocus](https://developer.apple.com/documentation/xcuiautomation/xcuielementattributes/hasfocus)、[XCUIElementAttributeName.frame](https://developer.apple.com/documentation/xctest/xcuielement/attributename/frame)。
