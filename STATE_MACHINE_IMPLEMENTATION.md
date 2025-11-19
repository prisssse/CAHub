# 状态机实现完成报告

## 实现概述

成功实现了流式消息处理的状态机机制，解决了双重流式传输（token events + stream events）冲突导致的消息重复问题。

## 状态机设计

### 状态枚举
```dart
enum _StreamingMode {
  idle,              // 初始状态，等待消息
  tokenMode,         // Token流式模式（普通对话）
  streamEventMode,   // Stream事件模式（工具调用等复杂消息）
  finalized,         // 消息已完成
}
```

### 状态转换图
```
idle
  ├─ 收到 token event → tokenMode
  └─ 收到 message_start → streamEventMode

tokenMode
  ├─ 继续收到 token → 累积文本
  ├─ 收到 message_start → streamEventMode (清空token数据)
  ├─ 收到 done → finalized (flush剩余tokens)
  └─ 收到 message_stop → finalized

streamEventMode
  ├─ 收到 token → **忽略** (防止冲突)
  ├─ 收到 content_block_* → 正常处理
  ├─ 收到 message_stop → finalized
  └─ 收到 done → finalized (无需flush)

finalized
  └─ 任何事件 → **忽略** (防止覆盖)
```

## 关键修改点

### 1. Token事件处理 (api_session_repository.dart:294-321)

**修改内容：**
- 检查当前模式，在 `streamEventMode` 或 `finalized` 时忽略token
- 在 `idle` 时进入 `tokenMode`
- 只在 `tokenMode` 时累积tokens

**代码逻辑：**
```dart
if (eventType == 'token') {
  if (currentMessageId != null && messageStates.containsKey(currentMessageId)) {
    final state = messageStates[currentMessageId]!;

    // 关键：检查模式
    if (state.mode == _StreamingMode.streamEventMode) {
      print('DEBUG SSE: ⊘ Ignoring token (in streamEventMode)');
      continue;
    } else if (state.mode == _StreamingMode.finalized) {
      print('DEBUG SSE: ⊘ Ignoring token (finalized)');
      continue;
    }
  }

  // 进入tokenMode
  if (state.mode == _StreamingMode.idle) {
    state.mode = _StreamingMode.tokenMode;
    print('DEBUG SSE: → Enter TOKEN_MODE');
  }

  // 累积token...
}
```

### 2. message_start处理 (api_session_repository.dart:387-417)

**修改内容：**
- 检测从 `tokenMode` 切换到 `streamEventMode`
- 清空token累积的数据（stream_event会重新发送完整内容）
- 将临时消息ID迁移到真实消息ID

**代码逻辑：**
```dart
if (streamEventType == 'message_start') {
  final messageId = message['id'] as String?;

  // 检查是否从token模式切换
  if (currentMessageId != null && currentMessageId!.startsWith('temp_')) {
    final tempState = messageStates[currentMessageId];
    if (tempState != null && tempState.mode == _StreamingMode.tokenMode) {
      print('DEBUG SSE: → Switching from TOKEN_MODE to STREAM_EVENT_MODE');

      // 清空token数据，stream_event会重建
      tempState.textBlocksBuilder.clear();
      tempState.contentBlockTypes.clear();
      tempState.mode = _StreamingMode.streamEventMode;
    }

    // 迁移状态到真实ID
    messageStates.remove(currentMessageId);
    messageStates[messageId] = tempState ?? _MessageBuildState();
  }

  currentMessageId = messageId;
  state.mode = _StreamingMode.streamEventMode;
  print('DEBUG SSE: → Enter STREAM_EVENT_MODE');
}
```

**为什么清空token数据？**
- Stream events会重新发送完整的消息内容
- 混合使用会导致重复或冲突
- 清空后由stream events完全接管构建过程

### 3. message_stop处理 (api_session_repository.dart:488-521)

**修改内容：**
- 设置 `mode = finalized`
- 只在未finalized时emit finalMessage

**代码逻辑：**
```dart
else if (streamEventType == 'message_stop') {
  if (currentMessageId != null && state != null && !state.finalized) {
    // 构建最终消息...

    if (blocks.isNotEmpty) {
      yield MessageStreamEvent(
        finalMessage: Message.fromBlocks(...),
      );

      // 关键：设置finalized模式
      state.mode = _StreamingMode.finalized;
      state.finalized = true;
      print('DEBUG SSE:     → FINALIZED');
    }
  }
}
```

### 4. done事件处理 (api_session_repository.dart:680-731)

**修改内容：**
- 只在 `tokenMode` 时flush剩余tokens
- 在 `streamEventMode` 时跳过（message_stop已处理）
- 在 `finalized` 时跳过

**代码逻辑：**
```dart
else if (eventType == 'done') {
  if (currentMessageId != null) {
    final state = messageStates[currentMessageId];

    if (state != null) {
      if (state.finalized) {
        print('DEBUG SSE: ⊘ Done event, already finalized');
      } else if (state.mode == _StreamingMode.streamEventMode) {
        print('DEBUG SSE: ⊘ Done event, in STREAM_EVENT_MODE (message_stop already finalized)');
        state.mode = _StreamingMode.finalized;
        state.finalized = true;
      } else if (state.mode == _StreamingMode.tokenMode && tokenBuffer.isNotEmpty) {
        // 仅在TOKEN_MODE时flush
        print('DEBUG SSE: → Flushing remaining tokens in TOKEN_MODE');

        // flush tokens并emit...

        state.mode = _StreamingMode.finalized;
        state.finalized = true;
      }
    }
  }

  yield MessageStreamEvent(isDone: true);
}
```

## 解决的问题

### ✅ 问题1: 消息重复3次
**根本原因：**
- message_stop发送1次
- done事件发送1次
- token事件在finalized后继续发送，覆盖final消息（导致又显示1次partial）

**解决方案：**
- 使用 `finalized` 标志防止重复emit
- 使用状态机防止token在finalized后继续处理
- 明确区分 tokenMode 和 streamEventMode

### ✅ 问题2: Token与Stream事件冲突
**根本原因：**
- Backend同时发送token events和stream events
- 两者都在修改同一个消息状态
- 没有协调机制

**解决方案：**
- 状态机明确当前处于哪种模式
- streamEventMode优先级更高
- 在streamEventMode时忽略所有token events

### ✅ 问题3: 临时ID与真实ID混乱
**根本原因：**
- Token流式使用临时ID（temp_xxx）
- Stream事件使用真实ID
- 两个ID指向同一个消息但状态分离

**解决方案：**
- 在message_start时检测临时ID
- 迁移状态从临时ID到真实ID
- 清空token数据，由stream events重建

## 预期效果

### 普通对话流程（仅Token模式）
```
Event: token → Enter TOKEN_MODE
Event: token → 累积...
Event: token → 累积...
Event: done → Flush tokens → EMIT FINAL → FINALIZED
```

### 工具调用流程（Stream事件模式）
```
Event: token → Enter TOKEN_MODE
Event: token → 累积...
Event: message_start → Switch to STREAM_EVENT_MODE → 清空token数据
Event: content_block_start → 创建text block
Event: content_block_delta → 追加文本 → EMIT PARTIAL
Event: content_block_stop → Block finalized → EMIT PARTIAL
Event: content_block_start → 创建tool_use block
Event: content_block_delta → 累积JSON
Event: content_block_stop → Parse JSON → EMIT PARTIAL
Event: message_stop → EMIT FINAL → FINALIZED
Event: done → Skip (already finalized)
```

### 混合流程（Token → Stream切换）
```
Event: token → Enter TOKEN_MODE
Event: token → 累积10个token → EMIT PARTIAL (基于token)
Event: message_start → Switch to STREAM_EVENT_MODE → 清空token数据
Event: content_block_* → 正常处理（完全基于stream events）
Event: token → Ignored (in STREAM_EVENT_MODE)
Event: token → Ignored (in STREAM_EVENT_MODE)
Event: message_stop → EMIT FINAL → FINALIZED
Event: token → Ignored (finalized)
Event: done → Skip (already finalized)
```

## 测试建议

### 1. 普通对话测试
```
输入: "你好"
预期:
- 进入 TOKEN_MODE
- 看到流式更新
- 消息只显示一次
- 日志显示: Enter TOKEN_MODE → EMIT FINAL at done
```

### 2. 工具调用测试
```
输入: "list files" 或其他触发工具的消息
预期:
- 先进入 TOKEN_MODE（如果有初始token）
- 切换到 STREAM_EVENT_MODE
- 看到 tool_use block
- 看到 tool_result block
- 消息只显示一次
- 日志显示: TOKEN_MODE → STREAM_EVENT_MODE → FINALIZED
```

### 3. 停止功能测试
```
操作: 发送消息后立即点击"停止"
预期:
- 收到 stopped 事件
- 消息停止更新
- 不会有重复
```

### 4. 连续对话测试
```
操作: 快速发送多条消息
预期:
- 每条消息独立处理
- 消息ID正确切换
- 没有混淆或重复
```

## 调试日志符号

- `✓` - 成功/完成
- `⟳` - 流式更新
- `→` - 开始/进入/状态转换
- `⊘` - 跳过/忽略
- `⚠` - 警告
- `✗` - 错误
- `⊗` - 停止

## 关键日志示例

### 正常Token流程
```
[SSE] Event: token
DEBUG SSE: → Enter TOKEN_MODE
DEBUG SSE: ⟳ Token update: 1 blocks
...
[SSE] Event: done
DEBUG SSE: → Flushing remaining tokens in TOKEN_MODE
DEBUG SSE: ✓✓✓ EMIT FINAL at done (TOKEN_MODE)
DEBUG SSE:     → FINALIZED
DEBUG SSE: ✓ Stream done
```

### 工具调用流程
```
[SSE] Event: token
DEBUG SSE: → Enter TOKEN_MODE
[SSE] Event: message
DEBUG SSE: → Switching from TOKEN_MODE to STREAM_EVENT_MODE
DEBUG SSE: → Enter STREAM_EVENT_MODE
[SSE] Event: token
DEBUG SSE: ⊘ Ignoring token (in streamEventMode)
[SSE]   Stream event: content_block_start
[SSE]   Stream event: content_block_delta
[SSE]   Stream event: content_block_stop
[SSE]   Stream event: message_stop
DEBUG SSE: ✓✓✓ EMIT FINAL at message_stop
DEBUG SSE:     → FINALIZED
[SSE] Event: token
DEBUG SSE: ⊘ Ignoring token (finalized)
[SSE] Event: done
DEBUG SSE: ⊘ Done event, already finalized
DEBUG SSE: ✓ Stream done
```

## 后续优化建议

### 1. 性能监控
可以添加每个事件的处理时间：
```dart
final startTime = DateTime.now();
// ... 处理事件
final duration = DateTime.now().difference(startTime);
if (duration.inMilliseconds > 10) {
  print('DEBUG SSE: ⚠ Event $eventType took ${duration.inMilliseconds}ms');
}
```

### 2. Token累积优化
当前阈值是10个token或遇到换行符，可以根据实际情况调整：
```dart
const _tokenBatchSize = 10;  // 可配置
```

### 3. 日志级别控制
生产环境可能需要减少日志输出：
```dart
const _debugMode = true;  // 开发时true，生产false
if (_debugMode) {
  print('DEBUG SSE: ...');
}
```

### 4. 状态持久化
如果需要支持应用重启后恢复流式状态，可以考虑将 `_MessageBuildState` 序列化。

## 相关文档

- `STREAMING_REDESIGN.md` - 设计文档
- `STREAMING_FIX.md` - 之前的修复记录（部分方案已被状态机替代）

## 完成时间

2025-11-18
