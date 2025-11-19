# 流式传输系统重构说明

## 修复的问题

### 1. 消息重复问题 ✅
**原因：**
- Token事件、Stream事件、message_stop、done事件都在发送消息
- 同一条消息被emit了4-5次，导致UI显示重复

**解决方案：**
- 使用 `state.finalized` 标志跟踪消息是否已经finalized
- 只在 message_stop 时发送 finalMessage（如果未finalized）
- done 事件只flush残留的tokens（如果消息未finalized）
- 清晰区分 partialMessage（流式更新）和 finalMessage（完成）

### 2. 工具调用结果不显示 ✅
**原因：**
- tool_result 以 content_block_start 形式到达，但没有立即标记为finalized
- 之前添加的立即emit逻辑与其他逻辑冲突

**解决方案：**
- 在 content_block_start 收到 tool_result 时立即添加到 finalizedBlocks
- tool_result 不需要等待 content_block_stop
- 在 content_block_stop 时会再次emit，包含完整的block列表
- _buildContentBlocks 中 tool_result 总是被包含（不检查finalized）

### 3. 事件处理混乱 ✅
**原因：**
- 代码逻辑分散，难以追踪消息流
- 缺少清晰的日志标识

**解决方案：**
- 完全重写 sendMessageStream 方法
- 按事件类型清晰分组（1-7）
- 添加详细的调试日志，使用符号标识：
  - `✓` 成功/完成
  - `⟳` 流式更新
  - `→` 开始/进入
  - `⊘` 跳过
  - `⚠` 警告
  - `✗` 错误
  - `⊗` 停止

## 新的事件处理流程

```
=== 1. run 事件 ===
→ Yield runId for stop functionality

=== 2. session_id ===
→ Yield sessionId (once)

=== 3. token 事件 (token-level streaming) ===
→ 累积10个token
→ Yield partialMessage
→ 重复...

=== 4. message 事件 ===

  4a. stream_event: message_start
      → 创建新的 messageState
      → 设置 currentMessageId

  4b. stream_event: content_block_start
      → 创建 text/thinking/tool_use/tool_result block
      → tool_result 立即标记为 finalized

  4c. stream_event: content_block_delta
      → text_delta: 追加文本，Yield partialMessage
      → input_json_delta: 累积JSON

  4d. stream_event: content_block_stop
      → 标记 block 为 finalized
      → 解析 tool_use 的 input JSON
      → Yield partialMessage (with finalized block)

  4e. stream_event: message_stop
      → 检查 !state.finalized
      → Yield finalMessage
      → 设置 state.finalized = true

  4f. payload type: user (tool results)
      → 解析 content blocks
      → 判断是否全是 tool_result
      → Yield finalMessage (role: assistant 或 user)

  4g. payload type: result
      → Yield stats

  4h. payload type: assistant (fallback)
      → 仅在没有流式传输时使用
      → Yield finalMessage

=== 5. done 事件 ===
→ Flush 残留 tokens (如果 !finalized)
→ Yield isDone: true
→ return

=== 6. error 事件 ===
→ Yield error + isDone: true
→ return

=== 7. stopped 事件 ===
→ Yield isDone: true
→ return
```

## 关键改进

### 1. 消息去重逻辑
```dart
// message_stop 时
if (!state.finalized) {
  yield finalMessage
  state.finalized = true
}

// done 事件时
if (tokenBuffer.isNotEmpty && !state.finalized) {
  yield finalMessage
  state.finalized = true
}
```

### 2. Tool Result 处理
```dart
// content_block_start 收到 tool_result
else if (blockType == 'tool_result') {
  state.toolUseBlocks[index] = {...};
  state.finalizedBlocks.add(index);  // 立即finalized
  // 不需要立即emit，content_block_stop会处理
}

// _buildContentBlocks 中
else if (blockType == 'tool_result' && toolBlocks.containsKey(index)) {
  // 总是包含，不检查 finalized
  blocks.add(ContentBlock(...));
}
```

### 3. 详细日志
```dart
print('[SSE] Event: $eventType');           // 所有事件
print('[SSE] ✓ Run ID: $runId');            // 成功捕获
print('[SSE] ⟳ Token update: ${blocks.length} blocks');  // 流式更新
print('[SSE] → Message started: $messageId');  // 开始
print('[SSE] ⊘ Skipping...');                // 跳过
print('[SSE] ⚠ No state...');                // 警告
print('[SSE] ✗ Error: ...');                 // 错误
```

## 测试要点

### 1. 基本对话
- [ ] 发送普通文本消息
- [ ] 检查是否只显示一次
- [ ] 检查流式更新是否平滑

### 2. 工具调用
- [ ] 发送触发工具调用的消息（如 "list files"）
- [ ] 检查 tool_use 是否显示
- [ ] 检查 tool_result 是否在流式中立即显示
- [ ] 检查是否没有重复

### 3. 连续对话
- [ ] 在流式回复中发送新消息
- [ ] 检查是否支持持续消息功能
- [ ] 检查消息顺序是否正确

### 4. 停止功能
- [ ] 在流式回复中点击"停止"
- [ ] 检查是否收到 stopped 事件
- [ ] 检查 UI 是否正确停止

### 5. Token流式
- [ ] 检查是否每10个token更新一次
- [ ] 检查遇到换行符是否立即更新
- [ ] 检查 done 时是否flush残留token

### 6. 多轮对话
- [ ] 一个请求触发多轮Agent对话
- [ ] 检查每条消息是否只显示一次
- [ ] 检查消息ID是否正确切换

## 日志示例

正常流程应该看到：
```
=== Starting new stream ===
[SSE] Event: run
[SSE] ✓ Run ID: run_xxx
[SSE] Event: session
[SSE] ✓ Session ID: session_xxx
[SSE] Event: message
[SSE] Message type: stream_event
[SSE]   Stream event: message_start
[SSE]   → Message started: msg_xxx
[SSE]   Stream event: content_block_start
[SSE]   → Block 0 started: text
[SSE]   Stream event: content_block_delta
[SSE]   ⟳ Text delta at 0
[SSE]   Stream event: content_block_stop
[SSE]   → Block 0 finalized
[SSE]   ⟳ Block stop: 1 blocks
[SSE]   Stream event: message_stop
[SSE] ✓ Message finalized: 1 blocks
[SSE] Event: done
[SSE] ✓ Stream done
```

## 备份文件

原始文件已备份到：
- `api_session_repository_backup.dart`

如需回滚：
```bash
cd E:\PycharmProjects\CodeAgentHub\cc_mobile\lib\repositories
cp api_session_repository_backup.dart api_session_repository.dart
```

## 代码质量改进

1. **清晰的控制流**: 每个事件类型有明确的处理块
2. **防御性编程**: 所有空值检查，所有异常捕获
3. **详细日志**: 便于调试和追踪问题
4. **性能优化**: Token累积减少emit频率
5. **状态管理**: 使用 finalized 标志避免重复
6. **类型安全**: 严格的类型检查和转换

## 下一步

1. 测试所有场景
2. 根据实际日志调整
3. 可能需要微调 token 累积阈值（当前10个）
4. 考虑添加性能监控（每个事件处理时间）
