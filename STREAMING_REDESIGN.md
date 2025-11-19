# 流式传输重新设计

## 问题分析

### 当前架构的问题
1. **双重流式机制冲突**：
   - Token events (backend自定义)
   - Stream events (Claude API标准)
   - 两者同时修改同一个message state

2. **时序问题**：
   - message_stop 后仍有 token events
   - 导致 finalized 的消息被 partial 覆盖

3. **状态管理混乱**：
   - temp ID vs 真实 message ID
   - finalized flag 不够

## 重新设计方案

### 策略：使用状态机

```
States:
1. IDLE - 等待消息
2. TOKEN_STREAMING - 仅token流式（无stream_event）
3. STREAM_EVENT_MODE - 标准流式（优先）
4. FINALIZED - 消息完成
```

### 状态转换

```
IDLE
  ├─ token event → TOKEN_STREAMING
  └─ message_start → STREAM_EVENT_MODE

TOKEN_STREAMING
  ├─ token event → 继续累积
  ├─ message_start → STREAM_EVENT_MODE (切换)
  └─ done → FINALIZED

STREAM_EVENT_MODE
  ├─ content_block_* → 处理
  ├─ token event → **忽略** (优先stream)
  ├─ message_stop → FINALIZED
  └─ done → FINALIZED

FINALIZED
  ├─ token event → **忽略**
  ├─ stream event → **忽略**
  └─ done → 结束
```

### 实现要点

1. **添加状态枚举**：
```dart
enum MessageStreamingState {
  idle,
  tokenStreaming,
  streamEventMode,
  finalized,
}
```

2. **状态管理**：
```dart
class _MessageBuildState {
  MessageStreamingState state = MessageStreamingState.idle;
  final contentBlockTypes = <int, String>{};
  final textBlocksBuilder = <int, StringBuffer>{};
  final toolUseBlocks = <int, Map<String, dynamic>>{};
  final finalizedBlocks = <int>{};
  bool finalized = false;
}
```

3. **Token事件处理**：
```dart
if (eventType == 'token') {
  if (state == null) {
    // 创建新状态，进入 TOKEN_STREAMING
    state = MessageStreamingState.tokenStreaming;
  } else if (state.state == MessageStreamingState.streamEventMode ||
             state.state == MessageStreamingState.finalized) {
    // 忽略
    continue;
  }
  // 仅在 TOKEN_STREAMING 或 idle 时处理
}
```

4. **message_start处理**：
```dart
if (streamEventType == 'message_start') {
  if (state != null) {
    // 切换到 STREAM_EVENT_MODE
    state.state = MessageStreamingState.streamEventMode;
    // 清空token累积的数据？或保留？
  }
}
```

5. **Finalize时**：
```dart
if (streamEventType == 'message_stop') {
  state.state = MessageStreamingState.finalized;
  state.finalized = true;
}
```

## 优势

1. **清晰的状态管理** - 知道当前在哪个模式
2. **避免冲突** - stream_event优先，忽略冲突的token
3. **容易调试** - 状态转换日志清晰
4. **健壮性** - 每个状态下的行为明确

## 待决策

### Q1: message_start时，之前token累积的数据怎么办？

**选项A**: 丢弃token数据，使用stream_event重建
- 优点：干净，避免混合
- 缺点：可能丢失部分文本

**选项B**: 保留token数据，合并到stream_event
- 优点：不丢失数据
- 缺点：可能重复

**建议**: 选项A，因为stream_event会重新发送所有内容

### Q2: 如果只有token没有stream_event怎么办？

**回答**: TOKEN_STREAMING状态处理，正常构建消息

### Q3: 后端为什么message_stop后还发token？

**可能原因**:
1. 后端bug - token流和stream event流不同步
2. 后端设计 - token是backup机制
3. 网络延迟 - 事件乱序

**建议**: 前端必须防御性处理，忽略finalized后的token
